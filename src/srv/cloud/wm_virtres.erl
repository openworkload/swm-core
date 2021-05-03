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
            ?LOG_INFO("Virtual resources manager has been started, remote: ~p", [wm_entity:get_attr(name, Remote)]),
            wm_factory:notify_initiated(virtres, MState#mstate.task_id),
            {ok, sleeping, MState#mstate{remote = Remote}};
        _ ->
            ?LOG_ERROR("Remote not found for job: ~p", [JobId]),
            {stop, {shutdown, "Remote not found"}, MState}
    end.

handle_sync_event(get_current_state, _From, State, MState) ->
    {reply, State, State, MState}.

handle_event(job_finished, running, #mstate{job_id = JobId, part_mgr_id = PartMgrNodeId} = MState) ->
    ?LOG_DEBUG("Job has finished => start data downloading: ~p", [JobId]),
    {ok, Ref, Files} = wm_virtres_handler:start_downloading(PartMgrNodeId, JobId),
    ?LOG_INFO("Downloading has been started [jobid=~p, ref=~p]: ~p", [JobId, Ref, Files]),
    {next_state, downloading, MState#mstate{download_ref = Ref}};
handle_event(destroy,
             running,
             #mstate{task_id = TaskId,
                     job_id = JobId,
                     part_id = PartId,
                     remote = Remote} =
                 MState) ->
    ?LOG_DEBUG("Destroy remote partition for job ~p (task_id: ~p)", [JobId, TaskId]),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}};
handle_event(Event, State, MState) ->
    ?LOG_DEBUG("Unexpected event: ~p [state=~p]", [Event, State]),
    {next_state, State, MState}.

handle_info(readiness_check, StateName, MState = #mstate{rediness_timer = OldTRef, job_id = JobId}) ->
    ?LOG_DEBUG("Readiness check (job=~p, state=~p)", [JobId, StateName]),
    catch timer:cancel(OldTRef),
    case wm_virtres_handler:is_job_partition_ready(JobId) of
        false ->
            ?LOG_DEBUG("Not all nodes are UP (job ~p)", [JobId]),
            Timer = wm_virtres_handler:wait_for_wm_resources_readiness(),
            {next_state, StateName, MState#mstate{rediness_timer = Timer}};
        true ->
            ?LOG_DEBUG("All nodes are UP (job ~p) => upload data", [JobId]),
            wm_virtres_handler:update_job([{state, ?JOB_STATE_TRANSFERRING}], MState#mstate.job_id),
            {ok, Ref} = wm_virtres_handler:start_uploading(MState#mstate.part_mgr_id, JobId),
            ?LOG_INFO("Uploading has started [~p]", [Ref]),
            {next_state, uploading, MState#mstate{upload_ref = Ref}}
    end;
handle_info(part_fetch,
            StateName,
            MState =
                #mstate{part_check_timer = OldTRef,
                        job_id = JobId,
                        remote = Remote}) ->
    ?LOG_DEBUG("Partition creation check (job=~p, state=~p)", [JobId, StateName]),
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

sleeping(activate,
         #mstate{task_id = ID,
                 job_id = JobId,
                 remote = Remote} =
             MState) ->
    ?LOG_DEBUG("Received 'activate' [sleeping] (~p)", [ID]),
    {ok, WaitRef} = wm_virtres_handler:request_partition_existence(JobId, Remote),
    {next_state, validating, MState#mstate{wait_ref = WaitRef}}.

validating({partition_exists, Ref, false},
           #mstate{action = create,
                   job_id = JobId,
                   wait_ref = Ref,
                   template_node = TplNode,
                   remote = Remote} =
               MState) ->
    ?LOG_INFO("Spawn a new partition (template: ~p)", [wm_entity:get_attr(name, TplNode)]),
    {ok, WaitRef} = wm_virtres_handler:spawn_partition(JobId, Remote),
    {next_state, creating, MState#mstate{wait_ref = WaitRef}};
validating({partition_exists, Ref, true},
           #mstate{action = create,
                   remote = Remote,
                   wait_ref = Ref,
                   job_id = JobId} =
               MState) ->
    ?LOG_INFO("Remote partition exits => reuse for job ~p", [JobId]),
    {ok, WaitRef} = wm_virtres_handler:request_partition(JobId, Remote),
    {next_state, creating, MState#mstate{wait_ref = WaitRef}};
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
    {next_state, destroying, MState#mstate{action = destroy, wait_ref = WaitRef}}.

creating({partition_spawned, Ref, NewPartExtId},
         #mstate{job_id = JobId,
                 wait_ref = Ref,
                 template_node = TplNode,
                 remote = Remote} =
             MState) ->
    ?LOG_INFO("Partition spawned => check status: ~p, job ~p", [NewPartExtId, JobId]),
    {ok, WaitRef} = wm_virtres_handler:request_partition(JobId, Remote),
    {next_state, creating, MState#mstate{wait_ref = WaitRef}};
creating({partition_fetched, Ref, Partition},
         #mstate{job_id = JobId,
                 wait_ref = Ref,
                 template_node = TplNode,
                 remote = Remote} =
             MState) ->
    case wm_entity:get_attr(state, Partition) of
        up ->
            {ok, PartMgrNodeId} = wm_virtres_handler:ensure_entities_created(JobId, Partition, TplNode),
            Timer = wm_virtres_handler:wait_for_wm_resources_readiness(),
            MState2 =
                MState#mstate{wait_ref = undefined,
                              job_id = JobId,
                              rediness_timer = Timer,
                              part_mgr_id = PartMgrNodeId},
            {next_state, creating, MState2};
        Other ->
            ?LOG_DEBUG("Partition fetched, but it is not fully created: ~p", [Other]),
            Timer = wm_virtres_handler:wait_for_partition_fetch(),
            {ok, WaitRef} = wm_virtres_handler:request_partition(JobId, Remote),
            {next_state, creating, MState#mstate{part_check_timer = Timer, wait_ref = WaitRef}}
    end;
creating({error, Ref, Error}, #mstate{job_id = JobId} = MState) ->
    ?LOG_DEBUG("Partition creation failed: ~p", [Error]),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_QUEUED}], JobId),
    handle_remote_failure(MState).

uploading({Ref, ok}, #mstate{upload_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Uploading has finished (~p)", [Ref]),
    ?LOG_DEBUG("Let the job be scheduled again with " "preset node ids (~p)", [JobId]),
    wm_virtres_handler:update_job([{state, ?JOB_STATE_QUEUED}], MState#mstate.job_id),
    {next_state, running, MState#mstate{upload_ref = finished}};
uploading({Ref, {error, Node, Reason}}, #mstate{upload_ref = Ref} = MState) ->
    ?LOG_DEBUG("Uploading to ~p has failed: ~s", [Node, Reason]),
    handle_remote_failure(MState);
uploading({Ref, 'EXIT', Reason}, #mstate{upload_ref = Ref} = MState) ->
    ?LOG_DEBUG("Uploading has unexpectedly exited: ~p", [Reason]),
    handle_remote_failure(MState).

running({Ref, Status}, #mstate{} = MState) ->
    ?LOG_INFO("Got orphaned message with reference ~p [running, ~p]", [Ref, Status]),
    {next_state, running, MState}.

downloading({Ref, ok}, #mstate{download_ref = Ref, job_id = JobId} = MState) ->
    ?LOG_INFO("Downloading has finished => delete entities [~p, ~p]", [Ref, JobId]),
    ok = wm_virtres_handler:remove_relocation_entities(JobId),
    gen_fsm:send_event(self(), start_destroying),
    {next_state, destroying, MState#mstate{download_ref = finished}};
downloading({Ref, {error, Node, Reason}}, #mstate{download_ref = Ref} = MState) ->
    ?LOG_DEBUG("Downloading from ~p has failed: ~p", [Node, Reason]),
    handle_remote_failure(MState);
downloading({Ref, 'EXIT', Reason}, #mstate{download_ref = Ref} = MState) ->
    ?LOG_DEBUG("Downloading has unexpectedly exited: ~p", [Reason]),
    handle_remote_failure(MState);
downloading({Ref, Status}, MState) ->
    ?LOG_ERROR("Got orphaned message with reference ~p [downloading, ~p]", [Ref, Status]),
    {next_state, downloading, MState}.

destroying(start_destroying,
           #mstate{task_id = TaskId,
                   job_id = JobId,
                   part_id = PartId,
                   remote = Remote} =
               MState) ->
    ?LOG_DEBUG("Destroy remote partition for job ~p (task_id: ~p)", [JobId, TaskId]),
    {ok, WaitRef} = wm_virtres_handler:delete_partition(PartId, Remote),
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

handle_remote_failure(#mstate{job_id = JobId, task_id = TaskId} = MState) ->
    ?LOG_INFO("Force state ~p for job ~p [~p]", [?JOB_STATE_QUEUED, JobId, TaskId]),
    wm_virtres_handler:update_job({state, ?JOB_STATE_QUEUED}, MState#mstate.job_id),
    %TODO Try to delete resource several, but limited number of times
    {stop, normal, MState}.

parse_args([], MState) ->
    MState;
parse_args([{extra, {Action, JobId, Node}} | T], MState) ->
    parse_args(T,
               MState#mstate{action = Action,
                             job_id = JobId,
                             template_node = Node});
parse_args([{task_id, ID} | T], MState) ->
    parse_args(T, MState#mstate{task_id = ID});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).
