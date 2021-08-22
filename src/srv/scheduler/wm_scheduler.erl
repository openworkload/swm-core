-module(wm_scheduler).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../../include/wm_scheduler.hrl").
-include("../../lib/wm_log.hrl").

-record(mstate, {start_times = [], forwardings = maps:new(), root, spool, sched_wm_port}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% ============================================================================
%% Callbacks
%% ============================================================================

handle_call(start_scheduling, _, #mstate{} = MState) ->
    case get_scheduler() of
        {error, Error} ->
            ?LOG_ERROR("Cannot get scheduler: ~w", [Error]),
            {reply, error, MState};
        {SubDivType, Scheduler} ->
            ?LOG_DEBUG("Start scheduler using record (subdiv=~p): ~w", [SubDivType, Scheduler]),
            case start_scheduler(Scheduler, MState) of
                {ok, NewMState} ->
                    {reply, erlang:send(self(), schedule), NewMState};
                {error, _} ->
                    {reply, error, MState}
            end
    end.

handle_cast({event, EventType, EventData}, #mstate{} = MState) ->
    {noreply, handle_event(EventType, EventData, MState)}.

handle_info({exit_status, ExitCode, _}, #mstate{} = MState) ->
    ?LOG_INFO("Scheduler exit status: ~p", [ExitCode]),
    {noreply, MState};
handle_info({output, BinOut, _}, #mstate{} = MState) ->
    ?LOG_DEBUG("Received new scheduling result (size=~p)", [byte_size(BinOut)]),
    Term = erlang:binary_to_term(BinOut),
    ?LOG_DEBUG("New scheduling result: ~w", [Term]),
    MState2 = handle_new_timetable(Term, MState),
    {noreply, MState2};
handle_info(job_start_time, #mstate{} = MState) ->
    MState2 = del_old_start_times(MState),
    case MState2#mstate.start_times of
        [] ->
            ?LOG_DEBUG("No more jobs to start");
        _ ->
            ?LOG_DEBUG("Start times: ~p", [MState2#mstate.start_times]),
            NewMinStartTime = hd(MState2#mstate.start_times),
            wm_utils:wake_up_after(NewMinStartTime, job_start_time)
    end,
    wm_event:announce(job_start_time, 0),
    {noreply, MState2};
handle_info(schedule, #mstate{} = MState) ->
    case get_scheduler() of
        {error, Error} ->
            ?LOG_ERROR("Cannot get scheduler: ~p", [Error]),
            {noreply, MState};
        {SubDivType, Scheduler} ->
            RunInterval = wm_entity:get_attr(run_interval, Scheduler),
            wm_utils:wake_up_after(RunInterval, schedule),
            {noreply, start_timetable_creation(SubDivType, Scheduler, MState)}
    end;
handle_info({'EXIT', Process, normal}, #mstate{} = MState) ->
    ?LOG_DEBUG("Process exited normally: ~p", [Process]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, #mstate{} = MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @hidden
init(Args) ->
    wm_event:subscribe(wm_commit_done, node(), ?MODULE),
    case wm_db:ensure_running() of
        ok ->
            wm_db:ensure_table_exists(timetable, [], local_bag),
            MState = parse_args(Args, #mstate{}),
            ok = wm_works:call_asap(?MODULE, start_scheduling),
            {ok, MState};
        {error, Error} ->
            ?LOG_ERROR("Could not start ~p: ~p", [?MODULE, Error]),
            {error, Error}
    end.

parse_args([], MState) ->
    MState;
parse_args([{spool, SpoolDir} | T], MState) ->
    parse_args(T, MState#mstate{spool = SpoolDir});
parse_args([{root, Root} | T], MState) ->
    parse_args(T, MState#mstate{root = Root});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

handle_event(wm_commit_done, {COMMIT_ID, _}, #mstate{} = MState) ->
    case maps:get(COMMIT_ID, MState#mstate.forwardings, not_found) of
        {Jobs, Node} ->
            ?LOG_DEBUG("Finished commit to ~p spotted: ~p", [Node, COMMIT_ID]),
            ForwJobs = [wm_entity:set_attr({state, forwarded}, Job) || Job <- Jobs],
            wm_conf:update(ForwJobs),
            Map = maps:remove(COMMIT_ID, MState#mstate.forwardings),
            MState#mstate{forwardings = Map};
        not_found ->
            MState
    end.

save_timetable([]) ->
    ok;
save_timetable([R | RestTimeTable]) ->
    ?LOG_DEBUG("Insert new timetable record: ~p", [R]),
    wm_conf:update(R),
    save_timetable(RestTimeTable).

sort_start_times([], StartTimeList) ->
    lists:sort(fun(X, Y) -> X < Y end, StartTimeList);
sort_start_times([X | T], StartTimeList) ->
    sort_start_times(T, [wm_entity:get_attr(start_time, X) | StartTimeList]).

del_old_start_times(#mstate{} = MState) ->
    StartTimes = MState#mstate.start_times,
    NewStartTimes = lists:filter(fun(X) -> X =/= hd(StartTimes) end, StartTimes),
    MState#mstate{start_times = NewStartTimes}.

get_scheduler() ->
    case wm_topology:get_subdiv() of
        not_found ->
            ?LOG_DEBUG("Subdivision not found, lets try later"),
            {error, not_found};
        [] ->
            ?LOG_ERROR("Subdivision not found"),
            {error, not_found};
        SubDiv ->
            SchedID = wm_entity:get_attr(scheduler, SubDiv),
            case wm_conf:select(scheduler, {id, SchedID}) of
                {ok, Scheduler} ->
                    SubDivType = element(1, SubDiv),
                    {SubDivType, Scheduler};
                _ ->
                    {error, not_found}
            end
    end.

run_mock_scheduler(grid, #mstate{} = MState) ->
    ClusterIds = [ID || {cluster, ID} <- wm_topology:get_children(nosort)],
    Clusters = wm_conf:select(cluster, ClusterIds),
    Up = lists:filter(fun(X) -> wm_entity:get_attr(state, X) == up end, Clusters),
    ?LOG_DEBUG("Up clusters: ~p", [Up]),
    case Up of
        [] ->
            ?LOG_DEBUG("No clusters in state UP were found");
        List ->
            Cluster = hd(List),
            NodeName = wm_entity:get_attr(manager, Cluster),
            case wm_conf:select_node(NodeName) of
                {ok, Node} ->
                    case wm_entity:get_attr(state_power, Node) of
                        up ->
                            send_jobs([?JOB_STATE_QUEUED], Node, MState);
                        down ->
                            ?LOG_DEBUG("Cluster manager ~p not UP (jobs won't be sent)", [Node])
                    end;
                _ ->
                    ?LOG_DEBUG("Scheduler is not ready for running (my node not found)")
            end
    end,
    MState.

send_jobs(JobStates, Node, #mstate{} = MState) ->
    case wm_db:get_many(job, state, JobStates) of
        [] ->
            ?LOG_DEBUG("No queued jobs found"),
            MState;
        Jobs ->
            ?LOG_DEBUG("Found ~p queued jobs to send to ~p", [length(Jobs), Node]),
            {ok, COMMIT_ID} = wm_factory:new(commit, Jobs, [Node]),
            ?LOG_DEBUG("New commit id of jobs sending is ~p", [COMMIT_ID]),
            ForwMap = maps:put(COMMIT_ID, {Jobs, Node}, MState#mstate.forwardings),
            MState#mstate{forwardings = ForwMap}
    end.

start_scheduler(Scheduler, #mstate{} = MState) ->
    DefaultSched = wm_entity:get_attr(path, Scheduler),
    LogDir = filename:join([MState#mstate.spool, atom_to_list(node()), "log"]),
    LogFile = filename:join([LogDir, "scheduler.log"]),
    DefaultPluginsDir = filename:join([MState#mstate.root, "current", "lib64"]),
    PluginsDir = os:getenv("SWM_SCHED_LIB", DefaultPluginsDir),
    SchedExec = os:getenv("SWM_SCHED_EXEC", DefaultSched),
    SchedCommand = filename:absname(SchedExec) ++ " -d" ++ " -p " ++ PluginsDir ++ " 2>>" ++ LogFile,
    WmPortArgs = [{exec, SchedCommand}],
    case wm_port:start_link(WmPortArgs) of
        {ok, WmPortPid} ->
            PortOpts = [{parallelism, true}, use_stdio, exit_status, stream, binary],
            Envs = [],
            Args = [],
            Reply = wm_port:run(WmPortPid, Args, Envs, PortOpts, ?SCHEDULE_START_TIMEOUT),
            wm_port:subscribe(WmPortPid),
            ?LOG_DEBUG("Scheduler started (reply: ~p)", [Reply]),
            {ok, MState#mstate{sched_wm_port = WmPortPid}};
        {error, Error} ->
            ?LOG_ERROR("Cannot start wm_port with args ~p", [Error]),
            {error, MState}
    end.

start_timetable_creation(grid, Scheduler, #mstate{} = MState) ->
    ?LOG_DEBUG("Start new grid scheduling iteration"),
    %TODO Call a real grid scheduler instead of this mock-scheduler
    TT = run_mock_scheduler(grid, MState),
    handle_new_timetable(TT, #mstate{} = MState);
start_timetable_creation(cluster, Scheduler, #mstate{} = MState) ->
    ?LOG_DEBUG("Start new cluster scheduling iteration"),
    request_new_schedule(Scheduler, MState).

request_new_schedule(Scheduler, #mstate{sched_wm_port = WmPortPid} = MState) ->
    BinIn = get_binary_for_scheduler(Scheduler),
    ?LOG_DEBUG("Generated scheduler input size: ~p bytes", [byte_size(BinIn)]),
    wm_port:cast(WmPortPid, BinIn),
    MState.

get_binary_for_scheduler(Scheduler) ->
    Bin0 = wm_sched_utils:add_input(?TOTAL_DATA_TYPES, <<>>, <<>>),
    SchedsBin = erlang:term_to_binary([Scheduler]),
    Bin1 = wm_sched_utils:add_input(?DATA_TYPE_SCHEDULERS, SchedsBin, Bin0),
    RH = wm_topology:get_tree(static),
    RhBin =
        erlang:term_to_binary(
            wm_utils:map_to_list(RH)),
    Bin2 = wm_sched_utils:add_input(?DATA_TYPE_RH, RhBin, Bin1),
    Jobs1 = wm_db:get_many(job, state, [?JOB_STATE_QUEUED]),
    Jobs2 = [wm_entity:set_attr({revision, wm_entity:get_attr(revision, X) + 1}, X) || X <- Jobs1],
    wm_conf:update(Jobs2), %% TODO: mark that the job has been scheduled at least once differently
    Jobs3 = wm_utils:make_jobs_c_decodable(Jobs2),
    ?LOG_DEBUG("Jobs for scheduler: ~p", [length(Jobs3)]),
    JobsBin = erlang:term_to_binary(Jobs3),
    Bin3 = wm_sched_utils:add_input(?DATA_TYPE_JOBS, JobsBin, Bin2),
    Bin4 = get_grid_bin_entity(Bin3),
    Clusters = wm_conf:select(cluster, all),
    ClustersBin = erlang:term_to_binary(Clusters),
    Bin5 = wm_sched_utils:add_input(?DATA_TYPE_CLUSTERS, ClustersBin, Bin4),
    Parts1 = wm_conf:select(partition, all),
    Parts2 = wm_utils:make_partitions_c_decodable(Parts1),
    PartsBin = erlang:term_to_binary(Parts2),
    Bin6 = wm_sched_utils:add_input(?DATA_TYPE_PARTITIONS, PartsBin, Bin5),
    Nodes1 = wm_topology:get_tree_nodes(),
    Nodes2 = wm_utils:make_nodes_c_decodable(Nodes1),
    NodesBin = erlang:term_to_binary(Nodes2),
    wm_sched_utils:add_input(?DATA_TYPE_NODES, NodesBin, Bin6).

-spec get_grid_bin_entity(binary()) -> binary().
get_grid_bin_entity(OldBin) ->
    case wm_conf:select(grid, all) of
        [Grid] ->
            GridBin = erlang:term_to_binary(Grid),
            wm_sched_utils:add_input(?DATA_TYPE_GRID, GridBin, OldBin);
        _ ->
            wm_sched_utils:add_input(?DATA_TYPE_GRID, <<>>, OldBin)
    end.

handle_new_timetable(SchedulerResult, #mstate{} = MState) when is_tuple(SchedulerResult) ->
    ?LOG_DEBUG("Received scheduling result: ~w", [SchedulerResult]),
    case erlang:element(1, SchedulerResult) =:= scheduler_result of
        true ->
            case wm_entity:get_attr(timetable, SchedulerResult) of
                TT when is_list(TT) ->
                    wm_db:clear_table(timetable),
                    save_timetable(TT),
                    update_scheduled_jobs(TT),
                    wake_me_for_job_start(TT, MState);
                TT ->
                    ?LOG_ERROR("Generated timetable format is incorrect "
                               "(not a list): ~p",
                               [TT]),
                    MState
            end;
        _ ->
            ?LOG_ERROR("Scheduler result format is incorrect"),
            MState
    end;
handle_new_timetable(WrongTimeTable, #mstate{} = MState) ->
    ?LOG_ERROR("Received timetable in wrong format: ~p", [WrongTimeTable]),
    MState.

wake_me_for_job_start(TT, #mstate{} = MState) ->
    case sort_start_times(TT, []) of
        [] ->
            ?LOG_DEBUG("Timetable is empty (no jobs were scheduled)"),
            MState;
        StartTimes ->
            Now = wm_utils:timestamp(second),
            ?LOG_DEBUG("Now epoch time: ~p", [Now]),
            MinStartTime = hd(StartTimes),
            ?LOG_DEBUG("Min start time: ~p (all: ~p)", [MinStartTime, StartTimes]),
            wm_utils:wake_up_after(MinStartTime, job_start_time),
            MState#mstate{start_times = StartTimes}
    end.

update_scheduled_jobs([]) ->
    ok;
update_scheduled_jobs([TimetableRow | T]) ->
    JobID = wm_entity:get_attr(job_id, TimetableRow),
    {ok, Job1} = wm_conf:select(job, {id, JobID}),
    Job2 =
        case wm_entity:get_attr(start_time, TimetableRow) of
            0 ->
                wm_entity:set_attr({state, ?JOB_STATE_WAITING}, Job1);
            _ ->
                Job1
        end,
    wm_conf:update([Job2]),
    update_scheduled_jobs(T).
