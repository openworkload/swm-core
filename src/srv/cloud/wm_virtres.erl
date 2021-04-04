-module(wm_virtres).

-behaviour(gen_fsm).

-export([start_link/1, start/1, stop/0]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, code_change/4, terminate/3]).
-export([sleeping/2, validating/2, creating/2, uploading/2, downloading/2, running/2, destroying/2]).

-include("../../lib/wm_log.hrl").
-include("../../../include/wm_scheduler.hrl").
-include("../../lib/wm_entity.hrl").

-record(mstate,
        {wait_ref = undefined :: string(),
         part_id = undefined :: string(),
         template_node = undefined :: #node{},
         remote = undefined :: #remote{},
         job_id = undefined :: string(),
         task_id = undefined :: integer(),
         part_mgr_id = undefined :: string(),
         rediness_timer = undefined :: reference(),
         upload_ref = undefined :: reference(),
         download_ref = undefined :: reference(),
         action = create :: atom()}).

-define(DEFAULT_CLOUD_NODE_API_PORT, 10001).
-define(REDINESS_CHECK_PERIOD, 10000).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Args) ->
    gen_fsm:start_link(?MODULE, Args, []).

-spec start([term()]) -> {ok, pid()} | ignore | {error, term()}.
start(Args) ->
    gen_fsm:start(?MODULE, Args, []).

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
    JobID = MState#mstate.job_id,
    case get_remote(JobID) of
        {ok, Remote} ->
            ?LOG_INFO("Virtual resources manager has been started, "
                      "remote: ~p",
                      [wm_entity:get_attr(name, Remote)]),
            wm_factory:notify_initiated(virtres, MState#mstate.task_id),
            {ok, sleeping, MState#mstate{remote = Remote}};
        _ ->
            ?LOG_ERROR("Remote not found for job: ~p", [JobID]),
            {stop, {shutdown, "Remote not found"}, MState}
    end.

handle_sync_event(_Event, _From, State, MState) ->
    {reply, State, State, MState}.

handle_event(job_finished, running, #mstate{job_id = JobID} = MState) ->
    ?LOG_DEBUG("Job has finished => start data downloading: ~p", [JobID]),
    {ok, Ref, Files} = wm_virtres_handler:start_downloading(MState),
    ?LOG_INFO("Downloading has been started [jobid=~p, "
              "ref=~p]: ~p",
              [JobID, Ref, Files]),
    {next_state, downloading, MState#mstate{download_ref = Ref}};
handle_event(destroy, running, #mstate{} = MState) ->
    delete_partition(running, MState#mstate{action = destroy});
handle_event(Event, State, MState) ->
    ?LOG_DEBUG("Unexpected event: ~p [state=~p]", [Event, State]),
    {next_state, State, MState}.

handle_info(readiness_check, StateName, MState = #mstate{rediness_timer = OldTRef, job_id = JobID}) ->
    ?LOG_DEBUG("Readiness check (job ~p)", [JobID]),
    catch timer:cancel(OldTRef),
    case wm_virtres_handler:is_job_partition_ready(JobID) of
        false ->
            ?LOG_DEBUG("Not all nodes are UP (job ~p)", [JobID]),
            MState2 = wait_for_wm_resources_readiness(MState),
            {next_state, StateName, MState2};
        true ->
            ?LOG_DEBUG("All nodes are UP (job ~p) => upload "
                       "data",
                       [JobID]),
            wm_virtres_handler:update_job([{state, ?JOB_STATE_TRANSFERRING}], MState#mstate.job_id),
            {ok, Ref} = wm_virtres_handler:start_uploading(MState#mstate.part_mgr_id, JobID),
            ?LOG_INFO("Uploading has started [~p]", [Ref]),
            {next_state, uploading, MState#mstate{upload_ref = Ref}}
    end;
handle_info(_Info, StateName, MState) ->
    {next_state, StateName, MState}.

code_change(_, StateName, MState, _) ->
    {ok, StateName, MState}.

terminate(State, StateName, #mstate{job_id = JobID}) ->
    Msg = io_lib:format("Virtres termination: ~p, ~p, ~p", [State, StateName, JobID]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% FSM state transitions
%% ============================================================================

sleeping(activate,
         #mstate{task_id = ID,
                 job_id = JobID,
                 remote = Remote} =
             MState) ->
    ?LOG_DEBUG("Received 'activate' [sleeping] (~p)", [ID]),
    {NextState, WaitRef} = wm_virtres_handler:validate_partition(JobID, Remote),
    {next_state, NextState, MState#mstate{wait_ref = WaitRef}}.

validating({partition_exists, Ref, false}, #mstate{action = create} = MState) ->
    spawn_partition(sleeping, MState);
validating({partition_exists, Ref, true},
           #mstate{action = create,
                   remote = Remote,
                   job_id = JobID} =
               MState) ->
    {NextState, WaitRef} = wm_virtres_handler:request_partition_existence(JobID, Remote),
    {next_state, NextState, MState#mstate{wait_ref = WaitRef}};
validating({partition_exists, Ref, false}, #mstate{action = destroy, job_id = JobID} = MState) ->
    ?LOG_DEBUG("No resources found for job ~s", [JobID]),
    {stop, {shutdown, {normal, Ref}}, MState};
validating({partition_exists, Ref, true}, #mstate{action = destroy} = MState) ->
    delete_partition(validating, MState).

creating({Ref, create_in_progress}, #mstate{} = MState) ->
    ?LOG_DEBUG("Partition creation is in progress [~p]", [Ref]),
    {next_state, creating, MState};
creating({create_partition, Ref, NewPartExtId}, #mstate{} = MState) ->
    {ok, PartMgrNodeId} = add_entities_to_conf(MState),
    MState2 = wait_for_wm_resources_readiness(MState),
    {next_state, creating, MState2#mstate{wait_ref = Ref, part_mgr_id = PartMgrNodeId}};
creating({Ref, Status}, MState) ->
    ?LOG_ERROR("Got orphaned message with reference "
               "~p [creating, ~p]",
               [Ref, Status]),
    {next_state, creating, MState}.

uploading({Ref, ok}, #mstate{upload_ref = Ref, job_id = JobID} = MState) ->
    ?LOG_INFO("Uploading has finished (~p)", [Ref]),
    ?LOG_DEBUG("Let the job be scheduled again with "
               "preset node ids (~p)",
               [JobID]),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_QUEUED}], MState#mstate.job_id),
    {next_state, running, MState#mstate{upload_ref = finished}};
uploading({Ref, {error, Node, Reason}}, #mstate{upload_ref = Ref} = MState) ->
    ?LOG_DEBUG("Uploading to ~p has failed: ~s", [Node, Reason]),
    handle_remote_failure(MState);
uploading({Ref, 'EXIT', Reason}, #mstate{upload_ref = Ref} = MState) ->
    ?LOG_DEBUG("Uploading has unexpectedly exited: ~p", [Reason]),
    handle_remote_failure(MState);
uploading(check_uploading, #mstate{} = MState) ->
    {next_state, uploading, MState};
uploading({Ref, Status}, MState) ->
    ?LOG_ERROR("Got orphaned message with reference "
               "~p [uploading, ~p]",
               [Ref, Status]),
    {next_state, creating, MState}.

running({Ref, Status}, #mstate{} = MState) ->
    ?LOG_INFO("Got orphaned message with reference "
              "~p [running, ~p]",
              [Ref, Status]),
    {next_state, running, MState}.

downloading({Ref, ok}, #mstate{download_ref = Ref, job_id = JobID} = MState) ->
    ?LOG_INFO("Downloading has finished => delete entities "
              "[~p, ~p]",
              [Ref, JobID]),
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    ok = wm_relocator:remove_relocation_entities(Job),
    gen_fsm:send_event(self(), start_destroying),
    {next_state, destroying, MState#mstate{download_ref = finished}};
downloading({Ref, {error, Node, Reason}}, #mstate{download_ref = Ref} = MState) ->
    ?LOG_DEBUG("Downloading from ~p has failed: ~p", [Node, Reason]),
    handle_remote_failure(MState);
downloading({Ref, 'EXIT', Reason}, #mstate{download_ref = Ref} = MState) ->
    ?LOG_DEBUG("Downloading has unexpectedly exited: ~p", [Reason]),
    handle_remote_failure(MState);
downloading(check_downloading, #mstate{} = MState) ->
    {next_state, downloading, MState};
downloading({Ref, Status}, MState) ->
    ?LOG_ERROR("Got orphaned message with reference "
               "~p [downloading, ~p]",
               [Ref, Status]),
    {next_state, downloading, MState}.

destroying(start_destroying, #mstate{} = MState) ->
    delete_partition(destroying, MState);
destroying({Ref, delete_in_progress}, #mstate{} = MState) ->
    ?LOG_DEBUG("Cloud partition deletion is in progress "
               "[~p]",
               [Ref]),
    {next_state, destroying, MState};
destroying({Ref, ok}, #mstate{} = MState) ->
    process_received_ref(destroying, MState);
destroying({Ref, Status}, MState) ->
    ?LOG_INFO("Got orphaned message with reference "
              "~p [destroying, ~p]",
              [Ref, Status]),
    {next_state, destroying, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec get_remote(string()) -> {ok, #remote{}}.
get_remote(JobID) ->
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    AccountID = wm_entity:get_attr(account_id, Job),
    ?LOG_INFO("Validate partition (job: ~p, account: "
              "~p)",
              [JobID, AccountID]),
    wm_conf:select(remote, {account_id, AccountID}).

delete_partition(State,
                 #mstate{task_id = TaskID,
                         job_id = JobID,
                         part_id = PartId,
                         remote = Remote} =
                     MState) ->
    ?LOG_DEBUG("Destroy remote partition for job ~p "
               "(task_id: ~p)",
               [JobID, TaskID]),
    case wm_virtres_handler:delete_partition() of
        {ok, Ref} ->
            {next_state, destroying, MState#mstate{action = destroy, wait_ref = Ref}};
        {error, not_found} ->
            ?LOG_WARN("Deleting partition not found [~p]", [MState#mstate.part_id]),
            {stop, {shutdown, {not_found, TaskID, State}}, MState}
    end.

process_received_ref(State, #mstate{} = MState) ->
    ok.  %case get_session_attr(last_status, MState) of

    %{ok, LastStatus} ->
      %handle_session(LastStatus, MState);

    %{error, not_found} ->
      %?LOG_INFO("Got orphaned message without session [~p]", [SID]),
      %{stop, {shutdown, {not_found, SID, State}}, MState}

  %end.

handle_session(creation_in_progress, #mstate{} = MState) ->
    ?LOG_DEBUG("Cloud partition creation is still in "
               "progress"),
    {next_state, creating, MState};
handle_session(creation_complete, #mstate{} = MState) ->
    ?LOG_INFO("Virtual resources creation is finished"),
    MState2 = handle_stack_created(MState),
    {next_state, creating, MState2};
handle_session(creation_failed, #mstate{} = MState) ->
    ?LOG_ERROR("Remote resources creation has failed"),
    handle_remote_failure(MState);
handle_session(deletion_in_progress, #mstate{} = MState) ->
    ?LOG_DEBUG("Cloud partition deletion is still in "
               "progress"),
    {next_state, destroying, MState};
handle_session(deletion_complete, #mstate{} = MState) ->
    {stop, normal, MState};
handle_session(deletion_failed, #mstate{} = MState) ->
    ?LOG_ERROR("Remote resources deletion has failed"),
    handle_remote_failure(MState).

handle_remote_failure(#mstate{job_id = JobID, task_id = TaskID} = MState) ->
    ?LOG_INFO("Return state ~p for job ~p [~p]", [?JOB_STATE_QUEUED, JobID, TaskID]),
    wm_virtres_handler:update_job({state, ?JOB_STATE_QUEUED}, MState#mstate.job_id),
    %TODO Try to delete resource several times
    {stop, normal, MState}.

handle_stack_created(#mstate{action = destroy, job_id = JobID} = MState) ->
    ?LOG_DEBUG("Resources destroying for job ~p: stack "
               "is found (was created)",
               [JobID]),
    MState;
handle_stack_created(#mstate{action = create} = MState) ->
    {ok, PartMgrNodeId} = add_entities_to_conf(MState),
    MState2 = wait_for_wm_resources_readiness(MState),
    MState2#mstate{part_mgr_id = PartMgrNodeId}.

parse_args([], MState) ->
    MState;
parse_args([{extra, {Action, JobID, Node}} | T], MState) ->
    parse_args(T,
               MState#mstate{action = Action,
                             job_id = JobID,
                             template_node = Node});
parse_args([{task_id, ID} | T], MState) ->
    parse_args(T, MState#mstate{task_id = ID});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

spawn_partition(State,
                #mstate{task_id = TaskID,
                        template_node = TplNode,
                        job_id = JobID,
                        remote = Remote} =
                    MState) ->
    NodeName = wm_entity:get_attr(name, TplNode),
    ?LOG_INFO("Spawn a new partition (template: ~p)", [NodeName]),
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    Options =
        #{image_name => "cirros",
          flavor_name => "m1.micro",
          partition_name => wm_virtres_handlers:get_partition_name(JobID),
          node_count => get_requested_nodes_number(Job)},
    {ok, Creds} = wm_virtres_handler:get_credentials(Remote),
    {ok, Ref} = wm_gate:create_partition(self(), Remote, Creds, Options),
    {next_state, creating, MState#mstate{wait_ref = Ref}}.

get_requested_nodes_number(Job) ->
    F = fun(Resource, Acc) ->
           case wm_entity:get_attr(name, Resource) of
               "node" ->
                   Acc + wm_entity:get_attr(count, Resource);
               _ ->
                   Acc
           end
        end,
    Result = lists:foldl(F, 0, wm_entity:get_attr(request, Job)),
    integer_to_binary(Result).

add_entities_to_conf(#mstate{job_id = JobID, remote = Remote} = MState) ->
    PartName = wm_virtres_handlers:get_partition_name(JobID),
    {ok, PubPartMgrIp, PriPartMgrIp, NodeIps} = wm_gate:get_partition_ips(PartName, Remote),
    PartID = wm_utils:uuid(v4),
    PartMgrName = get_partition_manager_name(JobID),
    case clone_nodes(PartID, PartMgrName, NodeIps, MState) of
        [] ->
            {error, "Could not clone nodes for job " ++ JobID};
        ComputeNodes ->
            ComputeNodeIds = [wm_entity:get_attr(id, X) || X <- ComputeNodes],
            PartMgrNode = create_partition_manager_node(PartID, JobID, PubPartMgrIp, PriPartMgrIp, MState),
            NewNodes = [PartMgrNode | ComputeNodes],
            Partition = create_part_entity(PartID, ComputeNodeIds, JobID, PartMgrNode, MState),
            wm_conf:update(NewNodes),
            1 = wm_conf:update(Partition),
            ?LOG_INFO("Remote nodes [job ~p]: ~p", [JobID, NewNodes]),
            ?LOG_INFO("Remote partition [job ~p]: ~p", [JobID, Partition]),
            PartMgrNodeId = wm_entity:get_attr(id, PartMgrNode),
            JobRss = get_allocated_resources(PartID, [PartMgrNodeId | ComputeNodeIds]),
            ?LOG_DEBUG("New job resources [job ~p]: ~p", [JobID, JobRss]),
            wm_virtres_handler:update_job([{nodes, ComputeNodeIds}, {resources, JobRss}], MState#mstate.job_id),
            wm_topology:reload(),
            {ok, PartMgrNodeId}
    end.

get_allocated_resources(PartID, NodeIds) ->
    GetNodeRes =
        fun(NodeID) ->
           wm_entity:set_attr([{name, "node"}, {count, 1}, {properties, [{id, NodeID}]}], wm_entity:new(resource))
        end,
    NodeRss = [GetNodeRes(X) || X <- NodeIds],
    PartRes =
        wm_entity:set_attr([{name, "partition"}, {count, 1}, {properties, [{id, PartID}]}, {resources, NodeRss}],
                           wm_entity:new(resource)),
    [PartRes].

create_part_entity(PartID, NodeIds, JobID, PartMgrNode, #mstate{job_id = JobID}) ->
    NameStr = wm_entity:get_attr(name, PartMgrNode),
    HostStr = wm_entity:get_attr(host, PartMgrNode),
    PartMgrId = wm_entity:get_attr(id, PartMgrNode),
    Cluster = wm_topology:get_subdiv(),
    Part1 = wm_entity:new(partition),
    Part2 =
        wm_entity:set_attr([{id, PartID},
                            {state, up},
                            {subdivision, cluster},
                            {subdivision_id, wm_entity:get_attr(id, Cluster)},
                            {name, wm_virtres_handlers:get_partition_name(JobID)},
                            {manager, NameStr ++ "@" ++ HostStr},
                            {nodes, [PartMgrId | NodeIds]},
                            {comment, "Cloud partition for job " ++ JobID}],
                           Part1),
    Cluster1 = wm_topology:get_subdiv(cluster),
    OldPartIDs = wm_entity:get_attr(partitions, Cluster1),
    Cluster2 = wm_entity:set_attr({partitions, [PartID | OldPartIDs]}, Cluster1),
    1 = wm_conf:update(Part2),
    1 = wm_conf:update(Cluster2),
    Part2.

get_partition_manager_name(JobID) ->
    "swm-" ++ string:slice(JobID, 0, 8) ++ "-phead".

get_compute_node_name(JobID, Index) ->
    "swm-" ++ string:slice(JobID, 0, 8) ++ "-node" ++ integer_to_list(Index).

get_cloud_node_api_port() ->
    ?DEFAULT_CLOUD_NODE_API_PORT.

get_role_id(RoleName) ->
    {ok, Role} = wm_conf:select(role, {name, RoleName}),
    wm_entity:get_attr(id, Role).

create_partition_manager_node(PartID, JobID, PubPartMgrIp, PriPartMgrIp, #mstate{template_node = TplNode} = MState) ->
    RemoteID = wm_entity:get_attr(remote_id, TplNode),
    NodeName = get_partition_manager_name(JobID),
    ApiPort = get_cloud_node_api_port(),
    NodeID = wm_utils:uuid(v4),
    wm_entity:set_attr([{id, NodeID},
                        {name, NodeName},
                        {host, PriPartMgrIp},
                        {gateway, PubPartMgrIp},
                        {api_port, ApiPort},
                        {roles, [get_role_id("partition")]},
                        {remote_id, RemoteID},
                        {resources, []},
                        {subdivision, partition},
                        {subdivision_id, PartID},
                        {parent, wm_utils:get_short_name(node())},
                        {comment, "Cloud partition manager node for job " ++ JobID}],
                       wm_entity:new(node)).

clone_nodes(_, _, [], #mstate{} = MState) ->
    ?LOG_ERROR("Could not clone nodes, because there "
               "are no node IPs"),
    [];
clone_nodes(PartID, ParentName, NodeIps, #mstate{job_id = JobID, template_node = TplNode} = MState) ->
    RemoteID = wm_entity:get_attr(remote_id, TplNode),
    ApiPort = get_cloud_node_api_port(),
    JobRes =
        wm_entity:set_attr([{name,
                             "job"}, % special resource to pin node to job
                            {count, 1},
                            {properties, [{id, JobID}]}],
                           wm_entity:new(resource)),
    Rss = [JobRes | wm_entity:get_attr(resources, TplNode)],
    NewNode =
        fun({SeqNum, IP}) ->
           wm_entity:set_attr([{id, wm_utils:uuid(v4)},
                               {name, get_compute_node_name(JobID, SeqNum)},
                               {host, IP},
                               {api_port, ApiPort},
                               {roles, [get_role_id("compute")]},
                               {subdivision, partition},
                               {subdivision_id, PartID},
                               {remote_id, RemoteID},
                               {resources, Rss},
                               {parent, ParentName},
                               {comment, "Cloud compute node for job " ++ JobID}],
                              wm_entity:new(node))
        end,
    ListOfPairs =
        lists:zip(
            lists:seq(0, length(NodeIps) - 1), NodeIps),
    [NewNode(P) || P <- ListOfPairs].

wait_for_wm_resources_readiness(#mstate{} = MState) ->
    TRef = wm_utils:wake_up_after(?REDINESS_CHECK_PERIOD, readiness_check),
    MState#mstate{rediness_timer = TRef}.
