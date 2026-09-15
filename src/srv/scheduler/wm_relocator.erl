-module(wm_relocator).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([cancel_relocation/1, remove_relocation_entities/1, remove_relocation_entities/2]).
-export([get_base_partition/1]).
-export([relocate_job/1]).

-ifdef(EUNIT).

-export([select_jobs_waiting_for_relocation/1]).

-endif.

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_scheduler.hrl").

-define(DEFAULT_RELOCATION_INTERVAL, 20000).
-define(MAX_RELOCATIONS, 1).

-record(mstate, {}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec cancel_relocation(#job{}) -> ok.
cancel_relocation(Job) ->
    gen_server:call(?MODULE, {cancel_relocation, Job}).

-spec remove_relocation_entities(#job{}) -> ok.
remove_relocation_entities(Job) ->
    remove_relocation_entities(Job, true).

-spec remove_relocation_entities(#job{}, boolean()) -> ok.
remove_relocation_entities(Job, ReloadTopology) ->
    JobRss = wm_entity:get(resources, Job),
    Count = delete_resources(JobRss, Job, 0),
    case ReloadTopology of
        true ->
            wm_topology:reload();
        false ->
            ok
    end,
    ?LOG_DEBUG("Deleted ~p entities for job ~p", [Count, wm_entity:get(id, Job)]).

-spec relocate_job(job_id()) -> ok | {error, term()}.
relocate_job(JobId) ->
    gen_server:call(?MODULE, {relocate, JobId}).

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
init(_) ->
    process_flag(trap_exit, true),
    ?LOG_INFO("Relocator module has been started"),
    MState = #mstate{},
    wm_event:subscribe(job_finished, node(), ?MODULE),
    wm_event:subscribe(job_canceled, node(), ?MODULE),
    restart_stopped_virtres_processes(),
    schedule_new_relocations(),
    {ok, MState}.

handle_call({relocate, JobId}, _, #mstate{} = MState) ->
    {reply, start_new_virtres_processes(JobId), MState};
handle_call({cancel_relocation, Job}, _, MState = #mstate{}) ->
    Reply = do_cancel_relocation(Job),
    start_waiting_relocations(),
    {reply, Reply, MState}.

handle_cast({event, job_canceled, {JobId, _, _, _}}, #mstate{} = MState) ->
    ?LOG_DEBUG("Job canceled => cancel relocation / drop pinger addresses: ~p", [JobId]),
    case wm_conf:select(job, {id, JobId}) of
        {ok, #job{relocatable = true} = Job} ->
            do_cancel_relocation(Job);
        {ok, Job} ->
            %% Local/non-cloud jobs may still have node addrs in the pinger.
            remove_relocation_entities(Job);
        _ ->
            ok
    end,
    start_waiting_relocations(),
    {noreply, MState};
handle_cast({event, job_finished, {JobId, _, _, _}}, #mstate{} = MState) ->
    ?LOG_DEBUG("Job finished: ~p", [JobId]),
    case wm_conf:select(job, {id, JobId}) of
        {ok, #job{state = ?JOB_STATE_CANCELED}} ->
            %% Cancel already destroyed remote resources and stopped virtres;
            %% do not start the normal finish/download path, but still drop any
            %% leftover #relocation row so it cannot block MAX_RELOCATIONS.
            case wm_conf:select(relocation, {job_id, JobId}) of
                {ok, Leftover} ->
                    ?LOG_DEBUG("Remove leftover relocation for canceled job: ~p", [JobId]),
                    wm_conf:delete(Leftover);
                _ ->
                    ok
            end;
        _ ->
            case wm_conf:select(relocation, {job_id, JobId}) of
                {ok, Relocation} ->
                    RelocationId = wm_entity:get(id, Relocation),
                    ?LOG_DEBUG("Remove relocation information (id: ~p)", [RelocationId]),
                    wm_conf:delete(Relocation),
                    wm_compute:set_nodes_alloc_state(remote, offline, JobId),
                    ok = wm_factory:send_event_locally(job_finished, virtres, RelocationId);
                _ ->  % no relocation was created for the job
                    ok
            end
    end,
    start_waiting_relocations(),
    {noreply, MState};
handle_cast(_, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(relocate_jobs, #mstate{} = MState) ->
    start_waiting_relocations(),
    schedule_new_relocations(),
    {noreply, MState};
handle_info(_, #mstate{} = MState) ->
    {noreply, MState}.

terminate(Reason, #mstate{}) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_, #mstate{} = MState, _) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec spawn_virtres_if_needed(#job{}, [#relocation{}]) -> [#relocation{}].
spawn_virtres_if_needed(Job, Relocations) ->
    JobId = wm_entity:get(id, Job),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {error, not_found} ->
            case spawn_virtres(Job) of
                {ok, RelocationId, TemplateNodeId} ->
                    ?LOG_DEBUG("Virtres has been spawned for job ~p (~p)", [JobId, RelocationId]),
                    Relocation =
                        wm_entity:set([{id, RelocationId}, {job_id, JobId}, {template_node_id, TemplateNodeId}],
                                      wm_entity:new(relocation)),
                    [Relocation | Relocations];
                _ ->
                    Relocations
            end;
        {ok, FoundRelocation} ->
            FoundRelocationId = wm_entity:get(id, FoundRelocation),
            case wm_factory:is_running(virtres, FoundRelocationId) of
                false ->
                    ?LOG_DEBUG("Virtres is not running got job ~p (~p) => respawn", [FoundRelocationId, JobId]),
                    case respawn_virtres(Job, FoundRelocation) of
                        {ok, NewRelocationId} ->
                            ?LOG_DEBUG("Relocation ID is updated for job ~p: ~p", [JobId, NewRelocationId]),
                            wm_conf:delete(FoundRelocation),
                            1 =
                                wm_conf:update(
                                    wm_entity:set({id, NewRelocationId}, FoundRelocation));
                        {error, Error} ->
                            ?LOG_DEBUG("Can't respawn virtres: ~p", [Error])
                    end;
                _ ->
                    ok
            end,
            ?LOG_DEBUG("Job ~p has already been relocating (~p)", [JobId, FoundRelocationId]),
            Relocations
    end.

-spec restart_stopped_virtres_processes() -> ok.
restart_stopped_virtres_processes() ->
    Filter =
        fun (#job{state = S,
                  relocatable = true,
                  revision = R})
                when R > 0 ->
                lists:member(S, [?JOB_STATE_QUEUED, ?JOB_STATE_WAITING, ?JOB_STATE_RUNNING, ?JOB_STATE_TRANSFERRING]);
            (_) ->
                false
        end,
    case wm_conf:select(job, Filter) of
        {error, not_found} ->
            ok;
        {ok, Jobs} when is_list(Jobs) ->
            case lists:foldl(fun spawn_virtres_if_needed/2, [], Jobs) of
                [] ->
                    ?LOG_DEBUG("No relocation requires virtres spawning");
                Relocations ->
                    N = wm_conf:update(Relocations),
                    ?LOG_DEBUG("Restarted ~p virtres processes", [N])
            end
    end.

-spec schedule_new_relocations() -> reference().
schedule_new_relocations() ->
    Ms = wm_conf:g(relocation_interval, {?DEFAULT_RELOCATION_INTERVAL, integer}),
    wm_utils:wake_up_after(Ms, relocate_jobs).

-spec start_new_virtres_processes(job_id()) -> ok | {error, term()}.
start_new_virtres_processes(JobId) ->
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            ?LOG_DEBUG("Start relocation for job ~p", [JobId]),
            RelocationsNum = wm_conf:get_size(relocation),
            Max = wm_conf:g(max_relocations, {?MAX_RELOCATIONS, integer}),
            case RelocationsNum < Max of
                true ->
                    case spawn_virtres_if_needed(Job, []) of
                        [NewRelocation] ->
                            wm_conf:update(NewRelocation),
                            ok;
                        [] ->
                            ?LOG_ERROR("Failed to spawn virtres for job ~p", [JobId]),
                            {error, "Failed to spawn virtres"}
                    end;
                false ->
                    %% Job already has a template node from the scheduler; it will
                    %% be picked up by start_waiting_relocations/0 when a slot frees
                    %% or on the next relocation_interval tick.
                    ?LOG_DEBUG("Too many relocations (~p), job will wait: ~p", [RelocationsNum, JobId]),
                    ok
            end;
        {error, not_found} ->
            ?LOG_ERROR("Relocatable job not found: ~p", [JobId]),
            {error, "Relocatable job not found"}
    end.

%% @doc Start relocations for jobs that were deferred because MAX_RELOCATIONS was reached.
-spec start_waiting_relocations() -> ok.
start_waiting_relocations() ->
    RelocationsNum = wm_conf:get_size(relocation),
    Max = wm_conf:g(max_relocations, {?MAX_RELOCATIONS, integer}),
    case RelocationsNum < Max of
        false ->
            ?LOG_DEBUG("Too many relocations (~p) when max=~p", [RelocationsNum, Max]),
            ok;
        true ->
            AllowToRelocate = Max - RelocationsNum,
            case select_jobs_waiting_for_relocation(AllowToRelocate) of
                [] ->
                    ok;
                Jobs ->
                    ?LOG_INFO("Start waiting relocation(s) for ~p job(s) (slots=~p)", [length(Jobs), AllowToRelocate]),
                    lists:foreach(fun(Job) ->
                                     JobId = wm_entity:get(id, Job),
                                     case spawn_virtres_if_needed(Job, []) of
                                         [NewRelocation] ->
                                             wm_conf:update(NewRelocation);
                                         [] ->
                                             ?LOG_DEBUG("Could not start waiting relocation for job ~p", [JobId])
                                     end
                                  end,
                                  Jobs)
            end
    end.

-spec select_jobs_waiting_for_relocation(non_neg_integer()) -> [#job{}].
select_jobs_waiting_for_relocation(Limit) when Limit =< 0 ->
    [];
select_jobs_waiting_for_relocation(Limit) ->
    Filter =
        fun (#job{state = S,
                  relocatable = true,
                  revision = R,
                  nodes = Nodes})
                when R > 0, Nodes =/= [] ->
                lists:member(S, [?JOB_STATE_QUEUED, ?JOB_STATE_WAITING]);
            (_) ->
                false
        end,
    case wm_conf:select(job, Filter) of
        {error, not_found} ->
            [];
        {ok, Jobs} when is_list(Jobs) ->
            Waiting =
                lists:filter(fun(Job) ->
                                JobId = wm_entity:get(id, Job),
                                case wm_conf:select(relocation, {job_id, JobId}) of
                                    {error, not_found} ->
                                        true;
                                    {ok, _} ->
                                        false
                                end
                             end,
                             Jobs),
            Sorted =
                lists:sort(fun(A, B) -> wm_entity:get(submit_time, A) =< wm_entity:get(submit_time, B) end, Waiting),
            case length(Sorted) > Limit of
                true ->
                    {Selected, _} = lists:split(Limit, Sorted),
                    Selected;
                false ->
                    Sorted
            end
    end.

% @doc Restart job relocation process that was started in the past but stopped by some reason
-spec respawn_virtres(#job{}, #relocation{}) -> integer() | {error, string()}.
respawn_virtres(Job, Relocation) ->
    JobId = wm_entity:get(id, Job),
    TemplateNodeId = wm_entity:get(template_node_id, Relocation),
    case wm_conf:select(node, {id, TemplateNodeId}) of
        {ok, TemplateNode} ->
            1 =
                wm_conf:update(
                    wm_entity:set({state, ?JOB_STATE_WAITING}, Job)),
            wm_factory:new(virtres, {create, JobId, TemplateNode}, predict_job_node_names(Job));
        {error, not_found} ->
            ?LOG_ERROR("Template node not found with id=~p, relocation: ~p", [TemplateNodeId, Relocation]),
            {error, "Template node not found"}
    end.

% @doc Start relocation returning relocation ID that is a hash of the nodes involved into the relocation
-spec spawn_virtres(#job{}) -> {ok, integer(), node_id()} | {error, not_found}.
spawn_virtres(Job) ->
    JobId = wm_entity:get(id, Job),
    case wm_entity:get(nodes, Job) of
        [TemplateNodeId] ->
            case wm_conf:select(node, {id, TemplateNodeId}) of
                {error, not_found} ->
                    ?LOG_WARN("Job provided unknown template node id ~p (job id: ~p}", [TemplateNodeId, JobId]),
                    {error, not_found};
                {ok, TemplateNode} ->
                    TemplateName = wm_entity:get(name, TemplateNode),
                    ?LOG_INFO("Spawn virtres for job ~p and template node ~p", [JobId, TemplateName]),
                    1 =
                        wm_conf:update(
                            wm_entity:set({state, ?JOB_STATE_WAITING}, Job)),
                    {ok, TaskId} = wm_factory:new(virtres, {create, JobId, TemplateNode}, predict_job_node_names(Job)),
                    {ok, TaskId, TemplateNodeId}
            end;
        [] ->
            ?LOG_WARN("No template node is defined for job ~p", [JobId]),
            {error, not_found}
    end.

-spec predict_job_node_names(#job{}) -> [string()].
predict_job_node_names(Job) ->
    Seq = lists:seq(0, wm_utils:get_requested_nodes_number(Job) - 1),
    JobId = wm_entity:get(id, Job),
    [wm_utils:get_cloud_node_name(JobId, SeqNum) || SeqNum <- Seq].

-spec do_cancel_relocation(#job{}) -> ok.
do_cancel_relocation(Job) ->
    JobId = wm_entity:get(id, Job),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {error, not_found} ->
            ?LOG_DEBUG("No relocation is running => destroy related resources: ~p", [JobId]),
            {ok, _TaskId} = wm_factory:new(virtres, {destroy, JobId, undefined}, []),
            remove_relocation_entities(Job);
        {ok, Relocation} ->
            ?LOG_DEBUG("Relocation is running => destroy its resources (job: ~p)", [JobId]),
            RelocationId = wm_entity:get(id, Relocation),
            ok = wm_factory:send_event_locally(destroy, virtres, RelocationId),
            remove_relocation_entities(Job),
            wm_conf:delete(Relocation)
    end.

-spec delete_resources([#resource{}], #job{}, pos_integer()) -> pos_integer().
delete_resources([], _, Cnt) ->
    Cnt;
delete_resources([#resource{name = "partition",
                            properties = Props,
                            resources = Rss}
                  | T],
                 Job,
                 Cnt) ->
    JobId = wm_entity:get(id, Job),
    case lists:keyfind(id, 1, Props) of
        false ->
            ?LOG_DEBUG("Partition resource does not have id property: ~p [job=~p]", [Props, JobId]),
            Cnt;
        {id, PartID} ->
            ?LOG_DEBUG("Delete partition entity ~p [job=~p]", [PartID, JobId]),
            ok = wm_conf:delete(partition, PartID),
            RssCnt = delete_resources(Rss, Job, 0),
            delete_partition_entity(Job, PartID),
            delete_resources(T, Job, Cnt + RssCnt + 1)
    end;
delete_resources([#resource{name = "node", properties = Props} | T], Job, Cnt) ->
    JobId = wm_entity:get(id, Job),
    case lists:keyfind(id, 1, Props) of
        false ->
            ?LOG_DEBUG("Node resource does not have id property: ~p [job=~p]", [Props, JobId]),
            delete_resources(T, Job, Cnt);
        {id, NodeId} ->
            case {wm_self:get_node(), wm_conf:select(node, {id, NodeId})} of
                {{ok, SelfNode}, {ok, JobNode}} ->
                    JobNodeAddress = wm_conf:get_relative_address(JobNode, SelfNode),
                    ?LOG_DEBUG("Delete node entity from config and address from pinger: ~p, ~p [job=~p]",
                               [NodeId, JobNodeAddress, JobId]),
                    ok = wm_pinger:delete(JobNodeAddress),
                    ok = wm_conf:delete(node, NodeId),
                    delete_resources(T, Job, Cnt + 1);
                {_, _} ->
                    ?LOG_DEBUG("Node entity already absent, still drop from pinger if known: ~p [job=~p]",
                               [NodeId, JobId]),
                    ok = wm_conf:delete(node, NodeId),
                    delete_resources(T, Job, Cnt)
            end
    end.

-spec get_base_partition(#job{}) -> {ok, #partition{}} | {error, term()}.
get_base_partition(Job) ->
    AccountID = wm_entity:get(account_id, Job),
    {ok, Remote} = wm_conf:select(remote, {account_id, AccountID}),
    RemoteName = wm_entity:get(name, Remote),
    ClusterID = wm_entity:get(cluster_id, Job),
    {ok, Cluster} = wm_conf:select(cluster, {id, ClusterID}),
    ClusterPartIds = wm_entity:get(partitions, Cluster),
    ClusterPartitions = wm_conf:select(partition, ClusterPartIds),
    case lists:search(fun(P) -> wm_entity:get(name, P) == RemoteName end, ClusterPartitions) of
        {value, Partition} ->
            {ok, Partition};
        _ ->
            {error, not_found}
    end.

-spec delete_partition_entity(#job{}, partition_id()) -> pos_integer().
delete_partition_entity(Job, PartID) ->
    case get_base_partition(Job) of
        {ok, BasePartition1} ->
            Parts1 = wm_entity:get(partitions, BasePartition1),
            Parts2 = lists:delete(PartID, Parts1),
            BasePartition2 = wm_entity:set([{partitions, Parts2}], BasePartition1),
            1 = wm_conf:update(BasePartition2);
        {error, not_found} ->
            {error, not_found}
    end.

-ifdef(EUNIT).

-include_lib("eunit/include/eunit.hrl").

% ./rebar3 eunit --module=wm_relocator

-spec make_job(string(), string(), [node_id()], string()) -> #job{}.
make_job(Id, State, Nodes, SubmitTime) ->
    wm_entity:set([{id, Id},
                   {state, State},
                   {nodes, Nodes},
                   {submit_time, SubmitTime},
                   {relocatable, true},
                   {revision, 1}],
                  wm_entity:new(job)).

-spec select_jobs_waiting_for_relocation_test_() -> term().
select_jobs_waiting_for_relocation_test_() ->
    {setup,
     fun() ->
        meck:new(wm_conf, [passthrough]),
        JobActive = make_job("active", ?JOB_STATE_WAITING, ["tpl1"], "2020-01-01T00:00:00"),
        JobWait1 = make_job("wait-1", ?JOB_STATE_QUEUED, ["tpl1"], "2020-01-01T00:00:02"),
        JobWait2 = make_job("wait-2", ?JOB_STATE_WAITING, ["tpl1"], "2020-01-01T00:00:01"),
        JobNoNodes = make_job("no-nodes", ?JOB_STATE_QUEUED, [], "2020-01-01T00:00:00"),
        JobRunning = make_job("running", ?JOB_STATE_RUNNING, ["tpl1"], "2020-01-01T00:00:00"),
        AllJobs = [JobActive, JobWait1, JobWait2, JobNoNodes, JobRunning],
        meck:expect(wm_conf,
                    select,
                    fun (job, Filter) when is_function(Filter) ->
                            {ok, lists:filter(Filter, AllJobs)};
                        (relocation, {job_id, "active"}) ->
                            {ok, wm_entity:set([{id, 1}, {job_id, "active"}], wm_entity:new(relocation))};
                        (relocation, {job_id, _}) ->
                            {error, not_found};
                        (Tab, Key) ->
                            meck:passthrough([Tab, Key])
                    end),
        ok
     end,
     fun(_) -> meck:unload(wm_conf) end,
     fun(_) ->
        [{"empty limit", ?_assertEqual([], select_jobs_waiting_for_relocation(0))},
         {"oldest waiting job first",
          fun() ->
             Selected = select_jobs_waiting_for_relocation(1),
             ?assertEqual(["wait-2"], [wm_entity:get(id, J) || J <- Selected])
          end},
         {"respects limit and skips active relocation",
          fun() ->
             Selected = select_jobs_waiting_for_relocation(10),
             ?assertEqual(["wait-2", "wait-1"], [wm_entity:get(id, J) || J <- Selected])
          end}]
     end}.

-endif.
