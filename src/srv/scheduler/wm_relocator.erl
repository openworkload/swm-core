-module(wm_relocator).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([cancel_relocation/1, remove_relocation_entities/1]).
-export([get_base_partition/1]).
-export([relocate_job/1]).

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

-spec cancel_relocation(#job{}) -> pos_integer().
cancel_relocation(Job) ->
    gen_server:call(?MODULE, {cancel_relocation, Job}).

-spec remove_relocation_entities(#job{}) -> ok.
remove_relocation_entities(Job) ->
    JobRss = wm_entity:get(resources, Job),
    Count = delete_resources(JobRss, Job, 0),
    wm_topology:reload(),
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
    restart_stopped_virtres_processes(),
    {ok, MState}.

handle_call({relocate, JobId}, _, #mstate{} = MState) ->
    {reply, start_new_virtres_processes(JobId), MState};
handle_call({cancel_relocation, Job}, _, MState = #mstate{}) ->
    {reply, do_cancel_relocation(Job), MState}.

handle_cast({event, job_finished, {JobId, _, _, _}}, #mstate{} = MState) ->
    ?LOG_DEBUG("Job finished event received for job ~p", [JobId]),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {ok, Relocation} ->
            RelocationId = wm_entity:get(id, Relocation),
            ?LOG_DEBUG("Received job_finished => remove relocation info ~p", [RelocationId]),
            wm_conf:delete(Relocation),
            wm_compute:set_nodes_alloc_state(remote, offline, JobId),
            ok = wm_factory:send_event_locally(job_finished, virtres, RelocationId);
        _ ->  % no relocation was created for the job
            ok
    end,
    {noreply, MState};
handle_cast(_, #mstate{} = MState) ->
    {noreply, MState}.

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
                    {ok, NewRelocationId} = respawn_virtres(Job, FoundRelocation),
                    ?LOG_DEBUG("Relocation ID is updated for job ~p: ~p", [JobId, NewRelocationId]),
                    wm_conf:delete(FoundRelocation),
                    1 =
                        wm_conf:update(
                            wm_entity:set({id, NewRelocationId}, FoundRelocation));
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

-spec start_new_virtres_processes(job_id()) -> ok | {error, term()}.
start_new_virtres_processes(JobId) ->
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            ?LOG_DEBUG("Start relocation for job ~p", [JobId]),
            RelocationsNum = wm_conf:get_size(relocation),
            Max = wm_conf:g(max_relocations, {?MAX_RELOCATIONS, integer}),
            case RelocationsNum < Max of
                true ->
                    [NewRelocation] = spawn_virtres_if_needed(Job, []),
                    wm_conf:update(NewRelocation),
                    ok;
                false ->
                    %TODO: restart job relocation eventually
                    ?LOG_DEBUG("Too many relocations (~p), job will wait: ~p", [RelocationsNum, JobId])
            end;
        {error, not_found} ->
            ?LOG_ERROR("Relocatable job not found: ~p", [JobId]),
            {error, "Relocatable job not found"}
    end.

% @doc Restart job relocation process that was started in the past but stopped by some reason
-spec respawn_virtres(#job{}, #relocation{}) -> integer() | {error, not_found}.
respawn_virtres(Job, Relocation) ->
    JobId = wm_entity:get(id, Job),
    TemplateNodeId = wm_entity:get(template_node_id, Relocation),
    {ok, TemplateNode} = wm_conf:select(node, {id, TemplateNodeId}),
    1 =
        wm_conf:update(
            wm_entity:set({state, ?JOB_STATE_WAITING}, Job)),
    wm_factory:new(virtres, {create, JobId, TemplateNode}, predict_job_node_names(Job)).

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

-spec do_cancel_relocation(#job{}) -> atom().
do_cancel_relocation(Job) ->
    JobId = wm_entity:get(id, Job),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {error, not_found} ->
            ?LOG_DEBUG("No relocation is running => destroy related resources: ~p", [JobId]),
            {ok, TaskId} = wm_factory:new(virtres, {destroy, JobId, undefined}, []),
            RelocationDestraction =
                wm_entity:set([{id, TaskId}, {job_id, JobId}, {canceled, true}], wm_entity:new(relocation)),
            remove_relocation_entities(Job),
            wm_conf:update(RelocationDestraction);
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
            Cnt;
        {id, NodeID} ->
            ?LOG_DEBUG("Delete node entity ~p [job=~p]", [NodeID, JobId]),
            ok = wm_conf:delete(node, NodeID),
            delete_resources(T, Job, Cnt + 1)
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
