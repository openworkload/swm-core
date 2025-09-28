-module(wm_virtres).

-behaviour(gen_statem).

-export([start_link/1, start/1, stop/0]).
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([sleeping/3, validating/3, creating/3, uploading/3, downloading/3, running/3, destroying/3]).

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
         readiness_timer = undefined :: reference(),
         ssh_prov_conn_timer = undefined :: reference(),
         ssh_prov_client_pid = undefined :: pid(),
         worker_reupload_timer = undefined :: reference(),
         ssh_tunnel_conn_timer = undefined :: reference(),
         ssh_tunnel_client_pid = undefined :: pid(),
         proxy_pids = [] :: [pid()],
         part_check_timer = undefined :: reference(),
         upload_ref = undefined :: reference(),
         download_ref = undefined :: reference(),
         err_msg = "" :: string(),
         action = create :: atom()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Args) ->
    gen_statem:start_link(?MODULE, Args, []).

-spec start([term()]) -> {ok, pid()} | ignore | {error, term()}.
start(Args) ->
    gen_statem:start(?MODULE, Args, []).

-spec stop() -> term().
stop() ->
    gen_statem:call(?MODULE, stop).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec callback_mode() -> state_functions.
-spec init(term()) ->
              {ok, atom(), term()} |
              {ok, atom(), term(), hibernate | infinity | non_neg_integer()} |
              {stop, term()} |
              ignore.
-spec code_change(term(), atom(), term(), term()) -> {ok, term()}.
-spec terminate(term(), atom(), term()) -> ok.
callback_mode() ->
    state_functions.

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

code_change(_, StateName, MState, _) ->
    {ok, StateName, MState}.

terminate(State, StateName, #mstate{job_id = JobId}) ->
    Msg = io_lib:format("Virtres termination: ~p, ~p, ~p", [State, StateName, JobId]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% State machine transitions
%% ============================================================================

-spec sleeping({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
sleeping({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
sleeping(cast,
         activate,
         #mstate{task_id = ID,
                 job_id = JobId,
                 remote = Remote,
                 err_msg = ErrMsg} =
             MState) ->
    ?LOG_DEBUG("Received 'activate' [sleeping] (~p)", [ID]),
    wm_virtres_handler:update_job([{state_details, "Preparing to start"}], JobId, ErrMsg),
    {ok, WaitRef} = wm_virtres_handler:request_partition_existence(JobId, Remote),
    {next_state, validating, MState#mstate{wait_ref = WaitRef}};
sleeping(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
sleeping(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec validating({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
validating({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
validating(cast,
           {partition_exists, Ref, false},
           #mstate{action = create,
                   job_id = JobId,
                   wait_ref = Ref,
                   remote = Remote,
                   err_msg = ErrMsg} =
               MState) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    case is_local_job(Job) of
        true ->
            ?LOG_DEBUG("No partition will be spawned (local job): ~p", [JobId]),
            {next_state, running, MState#mstate{upload_ref = finished}};
        false ->
            ?LOG_INFO("Spawn a new partition for job ~p", [JobId]),
            wm_virtres_handler:update_job([{state_details, "Initiate resources creation"}], JobId, ErrMsg),
            {ok, WaitRef} = wm_virtres_handler:spawn_partition(Job, Remote),
            {next_state, creating, MState#mstate{wait_ref = WaitRef}}
    end;
validating(cast,
           {partition_exists, Ref, true},
           #mstate{action = create,
                   wait_ref = Ref,
                   job_id = JobId,
                   err_msg = ErrMsg} =
               MState) ->
    ?LOG_INFO("Remote partition exits => reuse for job ~p", [JobId]),
    wm_virtres_handler:update_job([{state_details, "Fetch the partition details"}], JobId, ErrMsg),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
validating(cast,
           {partition_exists, Ref, false},
           #mstate{action = destroy,
                   wait_ref = Ref,
                   job_id = JobId,
                   err_msg = ErrMsg} =
               MState) ->
    ?LOG_DEBUG("No resources found for job ~s", [JobId]),
    wm_virtres_handler:update_job([{state_details, "Remote resources destroyed"}], JobId, ErrMsg),
    {stop, {shutdown, {normal, Ref}}, MState};
validating(cast,
           {partition_exists, Ref, true},
           #mstate{action = destroy,
                   wait_ref = Ref,
                   job_id = JobId,
                   part_id = PartId,
                   remote = Remote,
                   err_msg = ErrMsg} =
               MState) ->
    ?LOG_DEBUG("Destroy remote partition while validating for job ~p", [JobId]),
    wm_virtres_handler:update_job([{state_details, "Destroying remote resources"}], JobId, ErrMsg),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
validating(cast,
           {error, Ref, Msg},
           #mstate{wait_ref = Ref,
                   job_id = JobId,
                   err_msg = ErrMsg} =
               MState) ->
    ?LOG_INFO("Could not validate partition for job ~p: ~p", [JobId, Msg]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    wm_virtres_handler:update_job([{state_details, "Could not validate the partition"}], JobId, ErrMsg),
    {next_state, validating, MState#mstate{part_check_timer = Timer}};
validating(cast,
           {Ref, 'EXIT', timeout},
           #mstate{wait_ref = Ref,
                   job_id = JobId,
                   err_msg = ErrMsg} =
               MState) ->
    ?LOG_INFO("Timeout when validating partition for job ~p => try to fetch the partition later", [JobId]),
    wm_virtres_handler:update_job([{state_details, "Timeout when validating partition"}], JobId, ErrMsg),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, validating, MState#mstate{part_check_timer = Timer}};
validating(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
validating(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec creating({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
creating({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
creating(cast,
         {partition_spawned, Ref, NewPartExtId},
         #mstate{job_id = JobId,
                 wait_ref = Ref,
                 err_msg = ErrMsg} =
             MState) ->
    ?LOG_INFO("Partition spawned => check status: ~p, job ~p", [NewPartExtId, JobId]),
    wm_virtres_handler:update_job([{state_details, "Partition spawned"}], JobId, ErrMsg),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
creating(cast,
         {partition_fetched, Ref, Partition},
         #mstate{job_id = JobId,
                 wait_ref = Ref,
                 template_node = TplNode,
                 err_msg = ErrMsg} =
             MState) ->
    PartId = wm_entity:get(id, Partition),
    ?LOG_DEBUG("Partition fetched for job ~p, partition id: ~p", [JobId, PartId]),
    case wm_entity:get(state, Partition) of
        up ->
            wm_virtres_handler:update_job([{state_details, "Waiting for ssh provisioning port"}], JobId, ErrMsg),
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
            wm_virtres_handler:update_job([{state_details, "Waiting for partition readiness"}], JobId, ErrMsg),
            Timer = wm_virtres_handler:wait_for_partition_fetch(),
            {next_state, creating, MState#mstate{part_check_timer = Timer}}
    end;
creating(cast,
         ssh_prov_connected,
         #mstate{job_id = JobId,
                 part_mgr_id = PartMgrNodeId,
                 err_msg = ErrMsg} =
             MState) ->
    ?LOG_INFO("SSH for provisioning is ready for job ~p", [JobId]),
    wm_virtres_handler:update_job([{state_details, "Uploading the worker"}], JobId, ErrMsg),
    case wm_virtres_handler:upload_swm_worker(PartMgrNodeId, get_ssh_user_dir()) of
        ok ->
            ?LOG_INFO("SWM worker uploaded, wait for ssh tunnel for job ~p", [JobId]),
            wm_virtres_handler:update_job([{state_details, "Start secured tunnel"}], JobId, ErrMsg),
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
        {error, not_ready} ->
            ?LOG_DEBUG("New node is not ready to accept the worker file fia sftp => try again later"),
            Timer = wm_virtres_handler:try_upload_worker_later(),
            {next_state, creating, MState#mstate{worker_reupload_timer = Timer}};
        {error, Error} ->
            ?LOG_ERROR("SWM worker uploading failed: ~p", [Error]),
            {stop, {shutdown, Error}, MState}
    end;
creating(cast,
         ssh_swm_connected,
         #mstate{job_id = JobId,
                 ssh_tunnel_client_pid = SshClientPid,
                 err_msg = ErrMsg} =
             MState) ->
    wm_virtres_handler:update_job([{state_details, "Sky Port connected"}], JobId, ErrMsg),
    ForwardedPortTuples = start_port_forwarding(SshClientPid, JobId),
    {next_state,
     creating,
     MState#mstate{wait_ref = undefined,
                   readiness_timer = wm_virtres_handler:wait_for_wm_resources_readiness(),
                   proxy_pids = start_proxies(JobId, ForwardedPortTuples)}};
creating(cast, {error, Ref, {Msg, {part_id, PartId}}}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    ErrorMsg = "Partition creation error: " ++ binary_to_list(Msg),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_ERROR}, {state_details, ErrorMsg}], JobId),
    ?LOG_ERROR("Partition cannot be created for job ~p (~p)", [JobId, ErrorMsg]),
    gen_statem:cast(self(), start_destroying),
    {next_state,
     destroying,
     MState#mstate{download_ref = finished,
                   part_id = PartId,
                   err_msg = ErrorMsg}};
creating(cast, {error, Ref, Error}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    wm_virtres_handler:update_job([{state_details, "Partition has not been created yet"}], JobId),
    ?LOG_DEBUG("Partition has not been created yet for job ~p (~p)", [JobId, Error]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
creating(cast, {Ref, 'EXIT', timeout}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    wm_virtres_handler:update_job([{state_details, "Timeout when creating partition"}], JobId),
    ?LOG_INFO("Timeout when creating partition for job ~p => check it later", [JobId]),
    Timer = wm_virtres_handler:wait_for_partition_fetch(),
    {next_state, creating, MState#mstate{part_check_timer = Timer}};
creating(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
creating(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec uploading({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
uploading({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
uploading(cast, {Ref, ok}, #mstate{upload_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Uploading has finished (~p)", [Ref]),
    ?LOG_DEBUG("Let the job be scheduled again with preset nodes request (~p)", [JobId]),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_QUEUED}, {state_details, "Data uploaded, starting"}], JobId),
    {next_state, running, MState#mstate{upload_ref = finished}};
uploading(cast, {Ref, {error, Node, Reason}}, #mstate{upload_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_DEBUG("Uploading to ~p has failed: ~s", [Node, Reason]),
    wm_virtres_handler:update_job([{state_details, "Data uploading failed"}], JobId),
    handle_remote_failure(MState);
uploading(cast, {Ref, 'EXIT', Reason}, #mstate{upload_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_DEBUG("Uploading has unexpectedly exited: ~p", [Reason]),
    wm_virtres_handler:update_job([{state_details, "Uploading has unexpectedly exited"}], JobId),
    handle_remote_failure(MState);
uploading(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
uploading(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec running({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
running({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
running(cast, {Ref, Status}, #mstate{} = MState) ->
    ?LOG_INFO("Got orphaned message with reference ~p [running, ~p]", [Ref, Status]),
    {next_state, running, MState};
running(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
running(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec downloading({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
downloading({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
downloading(cast, {Ref, ok}, #mstate{download_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Downloading has finished => delete entities [~p, ~p]", [Ref, JobId]),
    wm_virtres_handler:update_job([{state_details, "Destroying remote resources"}], JobId),
    stop_port_forwarding(MState),
    gen_statem:cast(self(), start_destroying),
    {next_state, destroying, MState#mstate{download_ref = finished}};
downloading(cast, {Ref, {error, File, Reason}}, #mstate{download_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_WARN("Downloading of ~p has failed: ~p", [File, Reason]),
    wm_virtres_handler:update_job([{state_details, "Data downloading failed"}], JobId),
    stop_port_forwarding(MState),
    gen_statem:cast(self(), start_destroying),
    {next_state, destroying, MState#mstate{download_ref = finished}};
downloading(cast, {Ref, 'EXIT', Reason}, #mstate{download_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_DEBUG("Downloading has unexpectedly exited: ~p", [Reason]),
    wm_virtres_handler:update_job([{state_details, "Data downloading has unexpectedly exited"}], JobId),
    handle_remote_failure(MState);
downloading(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
downloading(cast, {Ref, Status}, MState) ->
    ?LOG_ERROR("Got orphaned message with reference ~p [downloading, ~p]", [Ref, Status]),
    {next_state, downloading, MState};
downloading(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec destroying({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
destroying({call, From}, get_current_state, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
destroying(cast,
           start_destroying,
           #mstate{task_id = TaskId,
                   job_id = JobId,
                   part_id = PartId,
                   remote = Remote,
                   err_msg = ErrMsg} =
               MState) ->
    ?LOG_DEBUG("Destroy remote partition ~p for job ~p (task_id: ~p)", [PartId, JobId, TaskId]),
    wm_virtres_handler:update_job([{state_details, "Start the partition resources destroying"}], JobId, ErrMsg),
    case wm_virtres_handler:delete_partition(PartId, Remote) of
        {ok, WaitRef} ->
            ok = wm_virtres_handler:remove_relocation_entities(JobId),
            {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
        {error, not_found} ->
            ?LOG_INFO("Partition was not destroyed (was not found) for job ~p: ~p", [JobId, PartId]),
            {stop, normal, MState}
    end;
destroying(cast, {delete_in_progress, Ref, Reply}, #mstate{job_id = JobId, err_msg = ErrMsg} = MState) ->
    ?LOG_DEBUG("Partition deletion is in progress [~p]: ~p", [Ref, Reply]),
    wm_virtres_handler:update_job([{state_details, "Partition resources deletion is in progress"}], JobId, ErrMsg),
    {next_state, destroying, MState};
destroying(cast, {partition_deleted, Ref, ReturnValue}, #mstate{wait_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_DEBUG("Partition deleted: ~p", [ReturnValue]),
    wm_virtres_handler:update_job([{state_details, "Remote resources were destroyed"}], JobId),
    {stop, normal, MState};
destroying(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
destroying(cast, {Ref, Status}, MState) ->
    ?LOG_WARN("Got orphaned message with reference ~p [destroying, ~p]", [Ref, Status]),
    {next_state, destroying, MState};
destroying(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec handle_remote_failure(#mstate{}) -> {atom(), atom(), #mstate{}}.
handle_remote_failure(#mstate{job_id = JobId, task_id = TaskId} = MState) ->
    ?LOG_INFO("Force state ~p for job ~p [~p]", [?JOB_STATE_QUEUED, JobId, TaskId]),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_QUEUED}, {state_details, "Job failed and requeued"}], JobId),
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

-spec get_wm_api_port() -> {string(), inet:port_number(), inet:port_number()}.
get_wm_api_port() ->
    {ok, SelfNode} = wm_self:get_node(),
    ApiPort = wm_entity:get(api_port, SelfNode),
    ParentPort = wm_conf:g(parent_api_port, {?DEFAULT_PARENT_API_PORT, integer}),
    {"out", ParentPort, ApiPort}.

-spec start_port_forwarding(pid(), job_id()) -> [{string(), inet:port_number(), inet:port_number()}].
start_port_forwarding(SshClientPid, JobId) ->
    ListenHost = "localhost",
    RemoteHost = "localhost",
    JobPorts = wm_resource_utils:get_job_networking_info(JobId, ports),
    PortsToForward = JobPorts ++ [get_wm_api_port()],

    lists:foldl(fun ({"out", ListenPort, PortToForward}, OpenPortTuples) ->
                        case wm_ssh_client:make_tunnel(SshClientPid, ListenHost, ListenPort, RemoteHost, PortToForward)
                        of
                            {ok, OpenedPort} ->
                                ?LOG_INFO("Tunnel is opened successfully for ports: ~p -> ~p (job: ~p)",
                                          [OpenedPort, PortToForward, JobId]),
                                [{"out", OpenedPort, PortToForward} | OpenPortTuples];
                            {error, Error} ->
                                ?LOG_ERROR("Can't open ssh tunnel (~p:~p <=> ~p:~p), error: ~p",
                                           [ListenHost, ListenPort, RemoteHost, PortToForward, Error]),
                                OpenPortTuples
                        end;
                    ({"in", RemotePortToOpen, _}, OpenPortTuples) ->
                        [{"in", RemotePortToOpen, RemotePortToOpen} | OpenPortTuples]
                end,
                [],
                PortsToForward).

-spec stop_port_forwarding(#mstate{}) -> ok.
stop_port_forwarding(#mstate{job_id = JobId, proxy_pids = ProxyPids}) ->
    ?LOG_INFO("Stop ports forwarding for job ~p", [JobId]),
    [wm_tcp_proxy:stop(Pid) || Pid <- ProxyPids],
    %TODO: stop port forwarding?
    ok.

-spec start_proxies(job_id(), [{string(), inet:port_number(), inet:port_number()}]) -> [pid()].
start_proxies(JobId, ForwardedPortTuples) ->
    JobAddr = wm_resource_utils:get_job_networking_info(JobId, submission_address),
    ?LOG_INFO("Start proxing ~p ports for job ~p to job submission address: ~p",
              [length(ForwardedPortTuples), JobId, JobAddr]),
    lists:foldl(fun ({"out", PortDst, PortSrc}, ProxyPids) ->
                        case wm_tcp_proxy:start_link(PortSrc, JobAddr, PortDst) of
                            {ok, Pid} ->
                                ?LOG_DEBUG("Started proxy ~p -> ~p:~p with pid=~p", [PortSrc, JobAddr, PortDst, Pid]),
                                [Pid | ProxyPids];
                            {error, Reason} ->
                                ?LOG_ERROR("Failed to start proxy ~p -> ~p:~p: ~p",
                                           [PortSrc, JobAddr, PortDst, Reason]),
                                ProxyPids
                        end;
                    ({"in", _, _}, ProxyPids) ->
                        ProxyPids
                end,
                [],
                ForwardedPortTuples).

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

-spec handle_event(term(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
handle_event(job_canceled, _, #mstate{job_id = JobId, task_id = TaskId} = MState) ->
    ?LOG_DEBUG("Job ~p was canceled, it's resources will be destroyed (task_id: ~p)", [JobId, TaskId]),
    ok = wm_virtres_handler:cancel_relocation(JobId),  %FIXME call does not exist and not used
    gen_statem:cast(self(), start_destroying),
    {next_state, destroying, MState};
handle_event(job_finished,
             _,
             #mstate{job_id = JobId,
                     part_mgr_id = PartMgrNodeId,
                     spool = Spool} =
                 MState) ->
    ?LOG_DEBUG("Job has finished => start data downloading: ~p", [JobId]),
    case wm_virtres_handler:start_job_data_downloading(PartMgrNodeId, JobId, get_ssh_swm_dir(Spool)) of
        {ok, Ref, Files} ->
            ?LOG_INFO("Downloading has been started [jobid=~p, ref=~10000p]: ~p", [JobId, Ref, Files]),
            wm_virtres_handler:update_job([{state_details, "Job finished, results downloading started"}], JobId),
            {next_state, downloading, MState#mstate{download_ref = Ref}};
        {error, Error} ->
            ?LOG_ERROR("Downloading cannot be started: ~p", [Error]),
            wm_virtres_handler:update_job([{state_details, "Job finished, results downloading failed"}], JobId),
            {next_state, downloading, MState#mstate{download_ref = undefined}}
    end;
handle_event(destroy,
             _,
             #mstate{task_id = TaskId,
                     job_id = JobId,
                     part_id = PartId,
                     remote = Remote} =
                 MState) ->
    ?LOG_DEBUG("Destroy remote partition for job ~p (task_id: ~p)", [JobId, TaskId]),
    wm_virtres_handler:update_job([{state_details, "Destroying partition resources"}], JobId),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
handle_event({error, PartId, not_found}, StateName, MState) ->
    ?LOG_DEBUG("Partition ~p  not found", [PartId]),
    {next_state, StateName, MState};
handle_event(Event, StateName, MState) ->
    ?LOG_DEBUG("Unexpected event: ~p [virtres state: ~p, mstate: ~p]", [Event, StateName, MState]),
    {next_state, StateName, MState}.

-spec handle_info(atom(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
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
            gen_statem:cast(self(), ssh_prov_connected),
            {next_state, creating, MState};
        not_ready ->
            ?LOG_DEBUG("SSH server is not ready yet, connection will be repeated"),
            wm_virtres_handler:update_job([{state_details, "Waiting for provisioning port readiness"}], JobId),
            Timer = wm_virtres_handler:wait_for_ssh_connection(ssh_check_prov_port),
            {next_state, creating, MState#mstate{ssh_prov_conn_timer = Timer}}
    end;
handle_info(try_worker_upload, _, MState = #mstate{worker_reupload_timer = OldTRef}) ->
    ?LOG_DEBUG("Try to upload swm worker"),
    catch timer:cancel(OldTRef),
    gen_statem:cast(self(), ssh_prov_connected),
    {next_state, creating, MState#mstate{worker_reupload_timer = undefined}};
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
            gen_statem:cast(self(), ssh_swm_connected),
            {next_state, creating, MState};
        not_ready ->
            ?LOG_DEBUG("SSH server is not ready yet, connection will be repeated"),
            wm_virtres_handler:update_job([{state_details, "Waiting for Sky Port port readiness"}], JobId),
            Timer = wm_virtres_handler:wait_for_ssh_connection(ssh_check_swm_port),
            {next_state, creating, MState#mstate{ssh_tunnel_conn_timer = Timer}}
    end;
handle_info(part_check,
            StateName,
            MState =
                #mstate{readiness_timer = OldTRef,
                        job_id = JobId,
                        spool = Spool}) ->
    ?LOG_DEBUG("Readiness check (job=~p, virtres state: ~p)", [JobId, StateName]),
    catch timer:cancel(OldTRef),
    case wm_virtres_handler:is_job_partition_ready(JobId) of
        false ->
            ?LOG_DEBUG("Not all nodes are UP (job ~p)", [JobId]),
            Timer = wm_virtres_handler:wait_for_wm_resources_readiness(),
            wm_virtres_handler:update_job([{state_details, "Waiting  for Sky Port port readiness"}], JobId),
            {next_state, StateName, MState#mstate{readiness_timer = Timer}};
        true ->
            ?LOG_DEBUG("All nodes are UP (job ~p) => upload data", [JobId]),
            wm_virtres_handler:update_job([{state, ?JOB_STATE_TRANSFERRING}, {state_details, "Uploading data"}], JobId),
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
