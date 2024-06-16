-module(wm_virtres).

-behaviour(gen_fsm).

-export([start_link/1, start/1, stop/0]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, code_change/4, terminate/3]).
-export([sleeping/2, validating/2, creating/2, uploading/2, downloading/2, running/2, destroying/2]).

-include("../../lib/wm_log.hrl").
-include("../../../include/wm_scheduler.hrl").
-include("../../../include/wm_general.hrl").
-include("../../lib/wm_entity.hrl").

-record(mstate,
        {spool = "" :: string(),
         wait_ref = undefined :: string(),
         part_id = undefined :: string(),
         template_node = undefined :: #node{},
         remote = undefined :: #remote{},
         job_id = undefined :: string(),
         task_id = undefined :: integer(),
         part_mgr_id = undefined :: string(),
         rediness_timer = undefined :: reference(),
         ssh_prov_conn_timer = undefined :: reference(),
         ssh_prov_client_pid = undefined :: pid(),
         ssh_tunnel_conn_timer = undefined :: reference(),
         ssh_tunnel_client_pid = undefined :: pid(),
         forwarded_ports = [] :: [inet:port_number()],
         part_check_timer = undefined :: reference(),
         upload_ref = undefined :: reference(),
         download_ref = undefined :: reference(),
         action = create :: atom()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Args) ->
    gen_fsm:start_link(?MODULE, Args, []).

-spec start([term()]) -> {ok, pid()} | ignore | {error, term()}.
start(Args) ->
    gen_fsm:start(?MODULE, Args, []).

-spec stop() -> term().
stop() ->
    gen_fsm:sync_send_all_state_event(?MODULE, stop).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init(term()) ->
              {ok, atom(), term()} |
              {ok, atom(), term(), hibernate | infinity | non_neg_integer()} |
              {stop, term()} |
              ignore.
-spec handle_event(term(), atom(), term()) ->
                      {next_state, atom(), term()} |
                      {next_state, atom(), term(), hibernate | infinity | non_neg_integer()} |
                      {stop, term(), term()} |
                      {stop, term(), term(), term()}.
-spec handle_sync_event(term(), atom(), atom(), term()) ->
                           {next_state, atom(), term()} |
                           {next_state, atom(), term(), hibernate | infinity | non_neg_integer()} |
                           {reply, term(), atom(), term()} |
                           {reply, term(), atom(), term(), hibernate | infinity | non_neg_integer()} |
                           {stop, term(), term()} |
                           {stop, term(), term(), term()}.
-spec handle_info(term(), atom(), term()) ->
                     {next_state, atom(), term()} |
                     {next_state, atom(), term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec code_change(term(), atom(), term(), term()) -> {ok, term()}.
-spec terminate(term(), atom(), term()) -> ok.
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    JobId = MState#mstate.job_id,
    case wm_virtres_handler:get_remote(JobId) of
        {ok, Remote} ->
            wm_factory:notify_initiated(virtres, MState#mstate.task_id),
            {ok, sleeping, MState#mstate{remote = Remote}};
        _ ->
            ?LOG_ERROR("Remote not found for job: ~p", [JobId]),
            {stop, "Remote not found"}
    end.

handle_sync_event(get_current_state, _From, State, MState) ->
    {reply, State, State, MState}.

handle_event(job_canceled, _, #mstate{job_id = JobId, task_id = TaskId} = MState) ->
    ?LOG_DEBUG("Job ~p was canceled, it's resources will be destroyed (task_id: ~p)", [JobId, TaskId]),
    ok = wm_virtres_handler:cancel_relocation(JobId),  %FIXME call does not exist and not used
    gen_fsm:send_event(self(), start_destroying),
    {next_state, destroying, MState};
handle_event(job_finished,
             _,
             #mstate{job_id = JobId,
                     part_mgr_id = PartMgrNodeId,
                     spool = Spool} =
                 MState) ->
    ?LOG_DEBUG("Job has finished => start data downloading: ~p", [JobId]),
    {ok, Ref, Files} = wm_virtres_handler:start_job_data_downloading(PartMgrNodeId, JobId, get_ssh_swm_dir(Spool)),
    ?LOG_INFO("Downloading has been started [jobid=~p, ref=~10000p]: ~p", [JobId, Ref, Files]),
    {next_state, downloading, MState#mstate{download_ref = Ref}};
handle_event(destroy,
             _,
             #mstate{task_id = TaskId,
                     job_id = JobId,
                     part_id = PartId,
                     remote = Remote} =
                 MState) ->
    ?LOG_DEBUG("Destroy remote partition for job ~p (task_id: ~p)", [JobId, TaskId]),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
handle_event(Event, StateName, MState) ->
    ?LOG_DEBUG("Unexpected event: ~p [virtres state: ~p, mstate: ~p]", [Event, StateName, MState]),
    {next_state, StateName, MState}.

handle_info(ssh_check_prov_port,
            StateName,
            MState =
                #mstate{ssh_prov_conn_timer = OldTRef,
                        ssh_prov_client_pid = SshProvClientPid,
                        job_id = JobId,
                        part_mgr_id = PartMgrNodeId}) ->
    catch timer:cancel(OldTRef),
    ConnectToPort = wm_conf:g(ssh_prov_listen_port, {?DEFAULT_SSH_PROVISION_PORT, integer}),
    Username = "root",
    Password = "",
    case try_ssh_connection(ConnectToPort,
                            SshProvClientPid,
                            JobId,
                            StateName,
                            PartMgrNodeId,
                            get_ssh_user_dir(),
                            Username,
                            Password)
    of
        ok ->
            wm_ssh_client:disconnect(SshProvClientPid),  % we just ensure sshd is ready
            gen_fsm:send_event(self(), ssh_prov_connected),
            {next_state, creating, MState};
        not_ready ->
            ?LOG_DEBUG("SSH server is not ready yet, connection will be repeated"),
            Timer = wm_virtres_handler:wait_for_ssh_connection(ssh_check_prov_port),
            {next_state, creating, MState#mstate{ssh_prov_conn_timer = Timer}}
    end;
handle_info(ssh_check_swm_port,
            StateName,
            MState =
                #mstate{ssh_tunnel_conn_timer = OldTRef,
                        ssh_tunnel_client_pid = SshTunnelClientPid,
                        job_id = JobId,
                        spool = Spool,
                        part_mgr_id = PartMgrNodeId}) ->
    catch timer:cancel(OldTRef),
    ConnectToPort = wm_conf:g(ssh_daemon_listen_port, {?DEFAULT_SSH_DAEMON_PORT, integer}),
    Username = "swm",
    Password = "swm",
    case try_ssh_connection(ConnectToPort,
                            SshTunnelClientPid,
                            JobId,
                            StateName,
                            PartMgrNodeId,
                            get_ssh_swm_dir(Spool),
                            Username,
                            Password)
    of
        ok ->
            gen_fsm:send_event(self(), ssh_swm_connected),
            {next_state, creating, MState};
        not_ready ->
            ?LOG_DEBUG("SSH server is not ready yet, connection will be repeated"),
            Timer = wm_virtres_handler:wait_for_ssh_connection(ssh_check_swm_port),
            {next_state, creating, MState#mstate{ssh_tunnel_conn_timer = Timer}}
    end;
handle_info(part_check,
            StateName,
            MState =
                #mstate{rediness_timer = OldTRef,
                        job_id = JobId,
                        spool = Spool}) ->
    ?LOG_DEBUG("Readiness check (job=~p, virtres state: ~p)", [JobId, StateName]),
    catch timer:cancel(OldTRef),
    case wm_virtres_handler:is_job_partition_ready(JobId) of
        false ->
            ?LOG_DEBUG("Not all nodes are UP (job ~p)", [JobId]),
            Timer = wm_virtres_handler:wait_for_wm_resources_readiness(),
            {next_state, StateName, MState#mstate{rediness_timer = Timer}};
        true ->
            ?LOG_DEBUG("All nodes are UP (job ~p) => upload data", [JobId]),
            wm_virtres_handler:update_job([{state, ?JOB_STATE_TRANSFERRING}], MState#mstate.job_id),
            {ok, Ref} =
                wm_virtres_handler:start_job_data_uploading(MState#mstate.part_mgr_id, JobId, get_ssh_swm_dir(Spool)),
            ?LOG_INFO("Uploading has started [~p]", [Ref]),
            {next_state, uploading, MState#mstate{upload_ref = Ref}}
    end;
handle_info(part_fetch,
            StateName,
            MState =
                #mstate{part_check_timer = OldTRef,
                        job_id = JobId,
                        remote = Remote}) ->
    ?LOG_DEBUG("Partition creation check (job ~p, virtres state: ~p)", [JobId, StateName]),
    catch timer:cancel(OldTRef),
    {ok, WaitRef} = wm_virtres_handler:request_partition(JobId, Remote),
    {next_state, StateName, MState#mstate{wait_ref = WaitRef}};
handle_info(_Info, StateName, MState) ->
    {next_state, StateName, MState}.

code_change(_, StateName, MState, _) ->
    {ok, StateName, MState}.

terminate(State, StateName, #mstate{job_id = JobId}) ->
    Msg = io_lib:format("Virtres termination: ~p, ~p, ~p", [State, StateName, JobId]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% FSM state transitions
%% ============================================================================

-spec sleeping(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
sleeping(activate,
         #mstate{task_id = ID,
                 job_id = JobId,
                 remote = Remote} =
             MState) ->
    ?LOG_DEBUG("Received 'activate' [sleeping] (~p)", [ID]),
    {ok, WaitRef} = wm_virtres_handler:request_partition_existence(JobId, Remote),
    {next_state, validating, MState#mstate{wait_ref = WaitRef}}.

-spec validating(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
validating({partition_exists, Ref, false},
           #mstate{action = create,
                   job_id = JobId,
                   wait_ref = Ref,
                   remote = Remote} =
               MState) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    case is_local_job(Job) of
        true ->
            ?LOG_DEBUG("No partition will be spawned (local job): ~p", [JobId]),
            {next_state, running, MState#mstate{upload_ref = finished}};
        false ->
            ?LOG_INFO("Spawn a new partition for job ~p", [JobId]),
            {ok, WaitRef} = wm_virtres_handler:spawn_partition(Job, Remote),
            {next_state, creating, MState#mstate{wait_ref = WaitRef}}
    end;
validating({partition_exists, Ref, true},
           #mstate{action = create,
                   wait_ref = Ref,
                   job_id = JobId} =
               MState) ->
    ?LOG_INFO("Remote partition exits => reuse for job ~p", [JobId]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
validating({partition_exists, Ref, false},
           #mstate{action = destroy,
                   wait_ref = Ref,
                   job_id = JobId} =
               MState) ->
    ?LOG_DEBUG("No resources found for job ~s", [JobId]),
    {stop, {shutdown, {normal, Ref}}, MState};
validating({partition_exists, Ref, true},
           #mstate{action = destroy,
                   wait_ref = Ref,
                   job_id = JobId,
                   part_id = PartId,
                   remote = Remote} =
               MState) ->
    ?LOG_DEBUG("Destroy remote partition while validating for job ~p", [JobId]),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
validating({error, Ref, Msg}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Could not validate partition for job ~p: ~p", [JobId, Msg]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, validating, MState#mstate{part_check_timer = Timer}};
validating({Ref, 'EXIT', timeout}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Timeout when validating partition for job ~p => try to fetch the partition later", [JobId]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, validating, MState#mstate{part_check_timer = Timer}}.

-spec creating(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
creating({partition_spawned, Ref, NewPartExtId}, #mstate{job_id = JobId, wait_ref = Ref} = MState) ->
    ?LOG_INFO("Partition spawned => check status: ~p, job ~p", [NewPartExtId, JobId]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
creating({partition_fetched, Ref, Partition},
         #mstate{job_id = JobId,
                 wait_ref = Ref,
                 template_node = TplNode} =
             MState) ->
    PartId = wm_entity:get(id, Partition),
    ?LOG_DEBUG("Partition fetched for job ~p, partition id: ~p", [JobId, PartId]),
    case wm_entity:get(state, Partition) of
        up ->
            case wm_ssh_client:start_link() of
                {ok, SshProvClientPid} ->
                    ?LOG_INFO("SSH provision client process started, pid: ~p, job: ~p", [SshProvClientPid, JobId]),
                    {ok, PartMgrNodeId} = wm_virtres_handler:ensure_entities_created(JobId, Partition, TplNode),
                    Timer = wm_virtres_handler:wait_for_ssh_connection(ssh_check_prov_port),
                    {next_state,
                     creating,
                     MState#mstate{wait_ref = Ref,
                                   part_id = PartId,
                                   ssh_prov_conn_timer = Timer,
                                   ssh_prov_client_pid = SshProvClientPid,
                                   part_mgr_id = PartMgrNodeId}};
                {error, Error} ->
                    ?LOG_ERROR("Can't get SSH provision client: ~p, job: ~p", [Error, JobId]),
                    {stop, {shutdown, Error}, MState}
            end;
        Other ->
            ?LOG_DEBUG("Partition fetched, but it is not fully created: ~p, job: ~p", [Other, JobId]),
            Timer = wm_virtres_handler:wait_for_partition_fetch(),
            {next_state, creating, MState#mstate{part_check_timer = Timer}}
    end;
creating(ssh_prov_connected, #mstate{job_id = JobId, part_mgr_id = PartMgrNodeId} = MState) ->
    ?LOG_INFO("SSH for provisioning is ready for job ~p", [JobId]),
    case wm_virtres_handler:upload_swm_worker(PartMgrNodeId, get_ssh_user_dir()) of
        ok ->
            ?LOG_INFO("SWM worker uploaded, wait for ssh tunnel for job ~p", [JobId]),
            case wm_ssh_client:start_link() of
                {ok, SshTunnelClientPid} ->
                    ?LOG_INFO("SSH tunnel client process started, pid: ~p, job: ~p", [SshTunnelClientPid, JobId]),
                    Timer = wm_virtres_handler:wait_for_ssh_connection(ssh_check_swm_port),
                    {next_state,
                     creating,
                     MState#mstate{ssh_tunnel_conn_timer = Timer, ssh_tunnel_client_pid = SshTunnelClientPid}};
                {error, Error} ->
                    ?LOG_ERROR("Can't get SSH tunnel client: ~p, job: ~p", [Error, JobId]),
                    {stop, {shutdown, Error}, MState}
            end;
        {error, Error} ->
            ?LOG_ERROR("SWM worker uploading failed: ~p", [Error]),
            {stop, {shutdown, Error}, MState}
    end;
creating(ssh_swm_connected, #mstate{job_id = JobId, ssh_tunnel_client_pid = SshClientPid} = MState) ->
    {next_state,
     creating,
     MState#mstate{wait_ref = undefined,
                   rediness_timer = wm_virtres_handler:wait_for_wm_resources_readiness(),
                   forwarded_ports = start_port_forwarding(SshClientPid, JobId)}};
creating({error, Ref, Error}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Partition creation failed: ~p, job id: ~p => try later", [Error, JobId]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
creating({Ref, 'EXIT', timeout}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Timeout when creating partition for job ~p => check it later", [JobId]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}}.

-spec uploading(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
uploading({Ref, ok}, #mstate{upload_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Uploading has finished (~p)", [Ref]),
    ?LOG_DEBUG("Let the job be scheduled again with preset nodes request (~p)", [JobId]),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_QUEUED}], JobId),
    {next_state, running, MState#mstate{upload_ref = finished}};
uploading({Ref, {error, Node, Reason}}, #mstate{upload_ref = Ref} = MState) ->
    ?LOG_DEBUG("Uploading to ~p has failed: ~s", [Node, Reason]),
    handle_remote_failure(MState);
uploading({Ref, 'EXIT', Reason}, #mstate{upload_ref = Ref} = MState) ->
    ?LOG_DEBUG("Uploading has unexpectedly exited: ~p", [Reason]),
    handle_remote_failure(MState).

-spec running(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
running({Ref, Status}, #mstate{} = MState) ->
    ?LOG_INFO("Got orphaned message with reference ~p [running, ~p]", [Ref, Status]),
    {next_state, running, MState}.

-spec downloading(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
downloading({Ref, ok}, #mstate{download_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Downloading has finished => delete entities [~p, ~p]", [Ref, JobId]),
    stop_port_forwarding(JobId),
    gen_fsm:send_event(self(), start_destroying),
    {next_state, destroying, MState#mstate{download_ref = finished}};
downloading({Ref, {error, File, Reason}}, #mstate{download_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_WARN("Downloading of ~p has failed: ~p", [File, Reason]),
    stop_port_forwarding(JobId),
    gen_fsm:send_event(self(), start_destroying),
    {next_state, destroying, MState#mstate{download_ref = finished}};
downloading({Ref, 'EXIT', Reason}, #mstate{download_ref = Ref} = MState) ->
    ?LOG_DEBUG("Downloading has unexpectedly exited: ~p", [Reason]),
    handle_remote_failure(MState);
downloading({Ref, Status}, MState) ->
    ?LOG_ERROR("Got orphaned message with reference ~p [downloading, ~p]", [Ref, Status]),
    {next_state, downloading, MState}.

-spec destroying(term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
destroying(start_destroying,
           #mstate{task_id = TaskId,
                   job_id = JobId,
                   part_id = PartId,
                   remote = Remote} =
               MState) ->
    ?LOG_DEBUG("Destroy remote partition for job ~p (task_id: ~p)", [JobId, TaskId]),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
    ok = wm_virtres_handler:remove_relocation_entities(JobId),
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
destroying({delete_in_progress, Ref, Reply}, #mstate{} = MState) ->
    ?LOG_DEBUG("Partition deletion is in progress [~p]: ~p", [Ref, Reply]),
    {next_state, destroying, MState};
destroying({partition_deleted, Ref, ReturnValue}, #mstate{wait_ref = Ref} = MState) ->
    ?LOG_DEBUG("Partition deleted: ~p", [ReturnValue]),
    {stop, normal, MState};
destroying({Ref, Status}, MState) ->
    ?LOG_INFO("Got orphaned message with reference ~p [destroying, ~p]", [Ref, Status]),
    {next_state, destroying, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec handle_remote_failure(#mstate{}) -> {atom(), atom(), #mstate{}}.
handle_remote_failure(#mstate{job_id = JobId, task_id = TaskId} = MState) ->
    ?LOG_INFO("Force state ~p for job ~p [~p]", [?JOB_STATE_QUEUED, JobId, TaskId]),
    wm_virtres_handler:update_job({state, ?JOB_STATE_QUEUED}, MState#mstate.job_id),
    %TODO Try to delete resource several, but limited number of times
    {stop, normal, MState}.

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{extra, {Action, JobId, Node}} | T], MState) ->
    parse_args(T,
               MState#mstate{action = Action,
                             job_id = JobId,
                             template_node = Node});
parse_args([{task_id, ID} | T], MState) ->
    parse_args(T, MState#mstate{task_id = ID});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec is_local_job(#job{}) -> boolean().
is_local_job(#job{nodes = [Node]}) ->
    Node == wm_self:get_node_id();
is_local_job(_) ->
    false.

-spec get_wm_api_port() -> inet:port_number().
get_wm_api_port() ->
    {ok, SelfNode} = wm_self:get_node(),
    ApiPort = wm_entity:get(api_port, SelfNode),
    ParentPort = wm_conf:g(parent_api_port, {?DEFAULT_PARENT_API_PORT, integer}),
    {"out", ParentPort, ApiPort}.

-spec start_port_forwarding(pid(), job_id()) -> [inet:port_number()].
start_port_forwarding(SshClientPid, JobId) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),

    ListenHost = "localhost",
    RemoteHost = "localhost",
    ResourcesRequest = wm_entity:get(request, Job),
    PortsToForward = wm_resource_utils:get_port_tuples(ResourcesRequest) ++ [get_wm_api_port()],

    lists:foldl(fun ({"out", ListenPort, PortToForward}, OpenedPorts) ->
                        case wm_ssh_client:make_tunnel(SshClientPid, ListenHost, ListenPort, RemoteHost, PortToForward)
                        of
                            {ok, OpenedPort} ->
                                ?LOG_INFO("Tunnel is opened successfully for ports: ~p -> ~p (job: ~p)",
                                          [OpenedPort, PortToForward, JobId]),
                                [OpenedPort | OpenedPorts];
                            {error, Error} ->
                                ?LOG_ERROR("Can't open ssh tunnel (~p:~p <=> ~p:~p), error: ~p",
                                           [ListenHost, ListenPort, RemoteHost, PortToForward, Error]),
                                OpenedPorts
                        end;
                    ({"in", RemotePortToOpen, _}, OpenedPorts) ->
                        [RemotePortToOpen | OpenedPorts]
                end,
                [],
                PortsToForward).

-spec stop_port_forwarding(job_id()) -> ok.
stop_port_forwarding(_JobId) ->
    ok.  %TODO: stop port forwarding?

-spec try_ssh_connection(pos_integer(), pid(), job_id(), atom(), node_id(), string(), string(), string()) ->
                            ok | not_ready.
try_ssh_connection(ConnectToPort, SshClientPid, JobId, StateName, PartMgrNodeId, HostCertsDir, Username, Password) ->
    ?LOG_DEBUG("SSH readiness check (job ~p, virtres state: ~p, port=~p)", [JobId, StateName, ConnectToPort]),
    {ok, PartMgrNode} = wm_conf:select(node, {id, PartMgrNodeId}),
    ConnectToHost = wm_entity:get(gateway, PartMgrNode),
    case wm_ssh_client:connect(SshClientPid, ConnectToHost, ConnectToPort, Username, Password, HostCertsDir) of
        ok ->
            ok;
        {error, _} ->
            not_ready
    end.

-spec get_ssh_user_dir() -> string().
get_ssh_user_dir() ->
    HomeDir = os:getenv("HOME"),
    filename:join(HomeDir, ".ssh").

-spec get_ssh_swm_dir(string()) -> string().
get_ssh_swm_dir(Spool) ->
    filename:join([Spool, "secure/host"]).
