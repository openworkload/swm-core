-module(wm_compute).

-behaviour(gen_server).

-export([set_nodes_alloc_state/3]).
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../../include/wm_scheduler.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-record(mstate, {processes = maps:new() :: map(), transfers = maps:new() :: map()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec set_nodes_alloc_state(onprem | remote | all, atom(), string()) -> ok.
set_nodes_alloc_state(Kind, Status, JobID) ->
    ?LOG_DEBUG("Set nodes alloc state: ~p ~p ~p", [Kind, Status, JobID]),
    case wm_conf:select(job, {id, JobID}) of
        {ok, Job} ->
            NodeIds = wm_entity:get_attr(nodes, Job),
            Nodes = wm_conf:select_many(node, id, NodeIds),
            Filtered =
                case Kind of
                    remote ->
                        lists:filter(fun(X) -> wm_entity:get_attr(remote_id, X) =/= [] end, Nodes);
                    onprem ->
                        lists:filter(fun(X) -> wm_entity:get_attr(remote_id, X) == [] end, Nodes);
                    all ->
                        Nodes
                end,
            wm_conf:set_nodes_state(state_alloc, Status, Filtered);
        {error, not_found} ->
            ?LOG_DEBUG("Job ~p job found => don't change nodes state", [JobID])
    end.

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init(term()) -> {ok, term()} | {ok, term(), hibernate | infinity | non_neg_integer()} | {stop, term()} | ignore.
-spec handle_call(term(), term(), term()) ->
                     {reply, term(), term()} |
                     {reply, term(), term(), hibernate | infinity | non_neg_integer()} |
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()} |
                     {stop, term(), term(), term()}.
-spec handle_cast(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec handle_info(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec terminate(term(), term()) -> ok.
-spec code_change(term(), term(), term()) -> {ok, term()}.
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("Compute node management service has been started"),
    wm_event:subscribe(job_start_time, node(), ?MODULE),
    wm_event:subscribe(job_arrived, node(), ?MODULE),
    wm_event:subscribe(job_cancelled, node(), ?MODULE),
    wm_event:subscribe(wm_proc_done, node(), ?MODULE),
    wm_event:subscribe(wm_commit_done, node(), ?MODULE),
    wm_event:subscribe(wm_commit_failed, node(), ?MODULE),
    wm_event:subscribe(proc_started, node(), ?MODULE),
    {ok, MState}.

handle_call(_Msg, _From, MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast({job_arrived, JobNodes, JobID}, MState) ->
    ?LOG_DEBUG("Received event that job ~p has been propagated", [JobID]),
    {noreply, start_job_processes(JobNodes, JobID, MState)};
handle_cast({event, EventType, EventData}, MState) ->
    {noreply, handle_event(EventType, EventData, MState)}.

handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], MState) ->
    MState;
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

handle_event(job_start_time, Time, MState) ->
    ?LOG_DEBUG("Received request to start jobs from local timetable (~p)", [Time]),
    TT = wm_db:get_less_equal(timetable, start_time, Time),
    ?LOG_DEBUG("Handle ~p timetable entities", [length(TT)]),
    handle_timetable(TT, MState);
handle_event(wm_proc_done, {ProcID, {JobID, Process, EndTime, Node}}, MState) ->
    ?LOG_DEBUG("System process ~p finished on ~p", [ProcID, Node]),
    update_job(JobID, process, Process),
    update_job(JobID, end_time, EndTime),
    event_to_parent({event, job_finished, {JobID, Process, EndTime, Node}}),
    wm_event:announce(job_finished, {JobID, Process, EndTime, Node}),
    PsMap = maps:remove(JobID, MState#mstate.processes),
    MState#mstate{processes = PsMap};
handle_event(job_cancelled, {JobID, Process, EndTime, Node}, MState) ->
    ?LOG_DEBUG("Job cancelled: ~p, process: ~p", [JobID, Process]),
    update_job(JobID, process, Process),
    update_job(JobID, end_time, EndTime),
    set_nodes_alloc_state(onprem, idle, JobID),
    event_to_parent({event, job_finished, {JobID, Process, EndTime, Node}}),
    wm_event:announce(job_finished, {JobID, Process, EndTime, Node}),
    JobProcesses = maps:get(JobID, MState#mstate.processes, maps:new()),
    maps:map(fun(ProcId, _) -> ok = wm_factory:send_event_locally({job_finished, Process}, proc, ProcId) end, JobProcesses),
    MState;
handle_event(job_finished, {JobID, Process, EndTime, Node}, MState) ->
    ?LOG_DEBUG("Job finished: ~p, process: ~p", [JobID, Process]),
    update_job(JobID, process, Process),
    update_job(JobID, end_time, EndTime),
    set_nodes_alloc_state(onprem, idle, JobID),
    event_to_parent({event, job_finished, {JobID, Process, EndTime, Node}}),
    wm_event:announce(job_finished, {JobID, Process, EndTime, Node}),
    MState;
handle_event(wm_commit_failed, {COMMIT_ID, _}, MState) ->
    case maps:get(COMMIT_ID, MState#mstate.transfers, not_found) of
        {_Nodes, JobID} ->
            %TODO restart the commit
            ?LOG_DEBUG("Failed commit spotted: ~p (jobid=~p)", [COMMIT_ID, JobID]),
            Map = maps:remove(COMMIT_ID, MState#mstate.transfers),
            MState#mstate{transfers = Map};
        not_found ->
            MState
    end;
handle_event(wm_commit_done, {COMMIT_ID, _}, MState) ->
    case maps:get(COMMIT_ID, MState#mstate.transfers, not_found) of
        {Nodes, JobID} ->
            ?LOG_DEBUG("Finished commit spotted: ~p (jobid=~p)", [COMMIT_ID, JobID]),
            wm_api:cast_self_confirm({job_arrived, Nodes, JobID}, Nodes),
            Map = maps:remove(COMMIT_ID, MState#mstate.transfers),
            MState#mstate{transfers = Map};
        not_found ->
            MState
    end;
handle_event(proc_started, {JobID, Node}, MState) ->
    update_job(JobID, state, ?JOB_STATE_RUNNING),
    update_job(JobID, start_time, wm_utils:now_iso8601(without_ms)),
    event_to_parent({event, proc_started, {JobID, Node}}),
    MState.

-spec handle_timetable([#timetable{}], #mstate{}) -> #mstate{}.
handle_timetable([], MState) ->
    MState;
handle_timetable([X | T], MState) ->
    JobID = wm_entity:get_attr(job_id, X),
    JobNodeIds = wm_entity:get_attr(job_nodes, X),
    ?LOG_DEBUG("Handle job ~p, node IDs: ~p", [JobID, JobNodeIds]),
    SelfNodeId = wm_self:get_node_id(),
    case JobNodeIds of
        [] ->
            ?LOG_DEBUG("No appropriate nodes found for job ~p", [JobID]),
            handle_timetable(T, MState);
        [FirstNodeId | _] when FirstNodeId == SelfNodeId ->
            Nodes = wm_conf:select_many(node, id, JobNodeIds),
            ?LOG_DEBUG("Job will be started locally (on ~p)", [wm_entity:get_attr(name, hd(Nodes))]),
            wm_conf:set_nodes_state(state_alloc, busy, Nodes),
            update_job(JobID, nodes, JobNodeIds),
            MState2 = start_job_processes(Nodes, JobID, MState),
            handle_timetable(T, MState2);
        _ ->
            ?LOG_DEBUG("Job will be sent to its compute nodes, job id: ~p", [JobID]),
            Records = wm_db:get_one(job, id, JobID),
            {ok, MyNode} = wm_self:get_node(),
            F = fun(Z) -> wm_conf:get_relative_address(Z, MyNode) end,
            Nodes = wm_conf:select_many(node, id, JobNodeIds),
            wm_conf:set_nodes_state(state_alloc, busy, Nodes),
            update_job(JobID, nodes, JobNodeIds),
            NodeAddrs = [F(Z) || Z <- Nodes],
            case NodeAddrs of
                [] ->
                    ?LOG_ERROR("No job nodes found in configuration: ~p", [JobNodeIds]),
                    handle_timetable(T, MState);
                _ ->
                    ?LOG_DEBUG("Propagate job ~p to nodes: ~p", [JobID, NodeAddrs]),
                    {ok, COMMIT_ID} = wm_factory:new(commit, Records, NodeAddrs),
                    Map = maps:put(COMMIT_ID, {NodeAddrs, JobID}, MState#mstate.transfers),
                    handle_timetable(T, MState#mstate{transfers = Map})
            end
    end.

-spec start_job_processes([#node{}], job_id(), #mstate{}) -> #mstate{}.
start_job_processes(JobNodes, JobID, MState) ->
    ?LOG_DEBUG("Start process for job ~p", [JobID]),
    %TODO Calculate number of processes for this node and start/follow all of them with separate wm_procs
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    {ok, ProcID} = wm_factory:new(proc, Job, JobNodes),
    add_proc(JobID, ProcID, JobNodes, MState).

-spec add_proc(job_id(), string(), [#node{}], #mstate{}) -> #mstate{}.
add_proc(JobID, ProcID, JobNodes, MState) ->
    JobPsMap1 = maps:get(JobID, MState#mstate.processes, maps:new()),
    JobPsMap2 = maps:put(ProcID, JobNodes, JobPsMap1),
    PsMap = maps:put(JobID, JobPsMap2, MState#mstate.processes),
    MState#mstate{processes = PsMap}.

update_job(JobID, process, Process) ->
    update_job(JobID, state, wm_entity:get_attr(state, Process)),
    update_job(JobID, exitcode, wm_entity:get_attr(exitcode, Process)),
    update_job(JobID, signal, wm_entity:get_attr(signal, Process));
update_job(JobID, Attr, NewState) ->
    case wm_conf:select(job, {id, JobID}) of
        {ok, Job1} ->
            case wm_entity:get_attr(state, Job1) of
                ?JOB_STATE_FINISHED ->
                    ?LOG_DEBUG("Job ~p is finished: ~p won't be changed", [JobID, Attr]);
                OldState ->
                    ?LOG_DEBUG("Job update: id=~p, ~p: ~p -> ~p", [JobID, Attr, OldState, NewState]),
                    Job2 = wm_entity:set_attr({Attr, NewState}, Job1),
                    1 = wm_conf:update([Job2])
            end;
        _ ->
            ok
    end.

event_to_parent(Event) ->
    Parent = wm_core:get_parent(),
    wm_api:cast_self(Event, [Parent]).
