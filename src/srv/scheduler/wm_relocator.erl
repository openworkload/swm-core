-module(wm_relocator).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([get_suited_template_nodes/1, get_suited_template_nodes/2]).
-export([select_remote_site/1]).
-export([cancel_relocation/1, remove_relocation_entities/1]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_general.hrl").
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

-spec get_suited_template_nodes(#job{}) -> [#node{}].
get_suited_template_nodes(Job) ->
    GetTemplates = fun(X) -> wm_entity:get_attr(is_template, X) == true end,
    case wm_conf:select(node, GetTemplates) of
        {error, not_found} ->
            [];
        {ok, Nodes} ->
            get_suited_template_nodes(Job, Nodes)
    end.

-spec get_suited_template_nodes(#job{}, [#node{}]) -> [#node{}].
get_suited_template_nodes(Job, Nodes) ->
    lists:filter(fun(Node) -> job_suited_node(Job, Node) end, Nodes).

-spec select_remote_site(#job{}) -> {ok, #node{}} | {error, not_found}.
select_remote_site(Job) ->
    Nodes = get_suited_template_nodes(Job),
    ?LOG_DEBUG("Suited template nodes number for job ~p: ~p", [wm_entity:get_attr(id, Job), length(Nodes)]),
    select_remote_site(Job, Nodes).

-spec cancel_relocation(#job{}) -> pos_integer().
cancel_relocation(Job) ->
    gen_server:call(?MODULE, {cancel_relocation, Job}).

-spec remove_relocation_entities(#job{}) -> ok.
remove_relocation_entities(Job) ->
    JobRss = wm_entity:get_attr(resources, Job),
    Count = delete_resources(JobRss, Job, 0),
    wm_topology:reload(),
    ?LOG_DEBUG("Deleted ~p entities for job ~p", [Count, wm_entity:get_attr(id, Job)]).

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
    schedule_new_relocations(),
    {ok, MState}.

handle_call({cancel_relocation, Job}, _, MState = #mstate{}) ->
    {reply, do_cancel_relocation(Job), MState}.

handle_cast({event, job_finished, {JobId, _, _, _}}, #mstate{} = MState) ->
    ?LOG_DEBUG("Job finished event received for job ~p", [JobId]),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {ok, Relocation} ->
            RelocationId = wm_entity:get_attr(id, Relocation),
            ?LOG_DEBUG("Received job_finished => remove relocation info ~p", [RelocationId]),
            wm_conf:delete(Relocation),
            wm_compute:set_nodes_alloc_state(remote, drained, JobId),
            ok = wm_factory:send_event_locally(job_finished, virtres, RelocationId);
        _ ->  % no relocation was created for the job
            ok
    end,
    {noreply, MState};
handle_cast(_, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(relocate_jobs, #mstate{} = MState) ->
    start_relocations(),
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

-spec job_suited_node(#job{}, #node{}) -> boolean().
job_suited_node(Job, Node) ->
    JobResources = wm_entity:get_attr(resources, Job),
    NodeResources = wm_entity:get_attr(resources, Node),
    F = fun(JobResource) -> match_resource(JobResource, NodeResources) end,
    lists:all(fun(X) -> X end, lists:map(F, JobResources)).

-spec match_resource(#resource{}, [#resource{}]) -> boolean().
match_resource(_, []) ->
    false;
match_resource(#resource{name = Name} = JobResource, [#resource{name = Name} = NodeResource | NodeResources]) ->
    DesiredCount = wm_entity:get_attr(count, JobResource),
    AvailableCount = wm_entity:get_attr(count, NodeResource),
    case DesiredCount =< AvailableCount of
        true ->
            true;
        false ->
            match_resource(JobResource, NodeResources)
    end;
match_resource(JobResource, [_NodeResource | NodeResources]) ->
    match_resource(JobResource, NodeResources).

-spec select_remote_site(#job{}, [#node{}]) -> {ok, #node{}} | {error, not_found}.
select_remote_site(_, []) ->
    {error, not_found};
select_remote_site(Job, Nodes) ->
    case wm_entity:get_attr(nodes, Job) of
        [SomeNode] ->
            case wm_entity:get_attr(is_template, SomeNode) of
              true ->
                {ok, SomeNode};
              false ->
                {error, "Job requests non-template node"}
            end;
        _ ->
           AccountId = wm_entity:get_attr(account_id, Job),
           Files = wm_entity:get_attr(input_files, Job),
           Data = cumulative_files_size(Files),
           PricesNorm =
               norming(lists:map(fun(Node) ->
                                   case wm_accounting:node_prices(Node) of
                                       #{AccountId := Price} ->
                                           Price;
                                       #{} ->
                                           0
                                   end
                                 end,
                                 Nodes)),
           NetworkLatenciesNorm = norming(lists:map(fun(Node) -> network_latency(Node) end, Nodes)),
           Xs = lists:zip3(Nodes, PricesNorm, NetworkLatenciesNorm),
           {_, Node} =
               lists:max(
                   lists:map(fun({Node, Price, NetworkLatency}) -> {node_weight(Price, NetworkLatency, Data), Node} end, Xs)),
           {ok, Node}
    end.

-spec cumulative_files_size([nonempty_string()]) -> number().
cumulative_files_size([]) ->
    1;
cumulative_files_size(Files) when is_list(Files) ->
    lists:sum(
        lists:map(fun(File) ->
                     case wm_file_utils:get_size(File) of
                         {ok, Bytes} ->
                             Bytes;
                         Reason ->
                             ?LOG_ERROR("Can not obtain file ~p size due ~p", [File, Reason]),
                             1
                     end
                  end,
                  Files)).

-spec network_latency(#node{}) -> number().
network_latency(Node) ->
    Resources = wm_entity:get_attr(resources, Node),
    lists:foldl(fun (Resource = #resource{name = "network_latency"}, _Acc) ->
                        wm_entity:get_attr(count, Resource);
                    (_Resource, Acc) ->
                        Acc
                end,
                ?NETWORK_LATENCY_MCS,
                Resources).

-spec norming([number()]) -> [number()].
norming(Xs) ->
    case lists:max(Xs) of
        0 ->
            Xs;
        Max ->
            lists:map(fun(X) -> X / Max end, Xs)
    end.

-spec koef(number()) -> number().
koef(X) ->
    Y = math:log10(X + 1) / 3.0103,
    0.5 - 1 / math:pi() * math:atan(Y - 2).

-spec node_weight(number(), number(), pos_integer()) -> number().
node_weight(Price, NetworkLatency, Data) ->
    K = koef(Data),
    1 / (K * Price + (1 - K) * NetworkLatency).

-spec schedule_new_relocations() -> reference().
schedule_new_relocations() ->
    Ms = wm_conf:g(relocation_interval, {?DEFAULT_RELOCATION_INTERVAL, integer}),
    wm_utils:wake_up_after(Ms, relocate_jobs).

-spec start_relocations() -> ok.
start_relocations() ->
    restart_stopped_virtres_processes(),
    start_new_virtres_processes().

-spec spawn_virtres_if_needed(#job{}, [#relocation{}]) -> [#relocation{}].
spawn_virtres_if_needed(Job, Relocations) ->
    JobId = wm_entity:get_attr(id, Job),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {error, not_found} ->
            case spawn_virtres(Job) of
                {ok, RelocationId, TemplateNodeId} ->
                    ?LOG_DEBUG("Virtres has been spawned for job ~p (~p)", [JobId, RelocationId]),
                    Relocation =
                        wm_entity:set_attr([{id, RelocationId}, {job_id, JobId}, {template_node_id, TemplateNodeId}],
                                           wm_entity:new(relocation)),
                    [Relocation | Relocations];
                _ ->
                    Relocations
            end;
        {ok, FoundRelocation} ->
            FoundRelocationId = wm_entity:get_attr(id, FoundRelocation),
            case wm_factory:is_running(virtres, FoundRelocationId) of
                false ->
                    ?LOG_DEBUG("Virtres is not running got job ~p (~p) => respawn", [FoundRelocationId, JobId]),
                    {ok, NewRelocationId} = respawn_virtres(Job, FoundRelocation),
                    ?LOG_DEBUG("Relocation ID is updated for job ~p: ~p", [JobId, NewRelocationId]),
                    wm_conf:delete(FoundRelocation),
                    1 =
                        wm_conf:update(
                            wm_entity:set_attr({id, NewRelocationId}, FoundRelocation));
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

-spec start_new_virtres_processes() -> ok.
start_new_virtres_processes() ->
    Filter =
        fun (#job{state = ?JOB_STATE_QUEUED,
                  nodes = [],
                  relocatable = true,
                  revision = R})
                when R > 0 ->
                true;
            (_) ->
                false
        end,
    case wm_conf:select(job, Filter) of
        {ok, Jobs} ->
            RelocationsNum = wm_conf:get_size(relocation),
            Max = wm_conf:g(max_relocations, {?MAX_RELOCATIONS, integer}),
            case RelocationsNum < Max of
                true ->
                    JobsNum = length(Jobs),
                    AllowToRelocate = Max - RelocationsNum,
                    JobsToRelocate =
                        case JobsNum > AllowToRelocate of
                            true ->
                                {List, _} = lists:split(AllowToRelocate, Jobs),
                                List;
                            false ->
                                Jobs
                        end,
                    ?LOG_INFO("Try to relocate ~p jobs (out of queued ~p jobs)", [JobsToRelocate, JobsNum]),
                    Relocations = lists:foldl(fun spawn_virtres_if_needed/2, [], JobsToRelocate),
                    wm_conf:update(Relocations);
                false ->
                    ?LOG_DEBUG("Too many relocations (~p) when max=~p", [RelocationsNum, Max])
            end;
        {error, not_found} ->
            ok
    end,
    ok.

% @doc Restart job relocation process that was started in the past but stopped by some reason
-spec respawn_virtres(#job{}, #relocation{}) -> integer() | {error, not_found}.
respawn_virtres(Job, Relocation) ->
    JobId = wm_entity:get_attr(id, Job),
    TemplateNodeId = wm_entity:get_attr(template_node_id, Relocation),
    {ok, TemplateNode} = wm_conf:select(node, {id, TemplateNodeId}),
    1 =
        wm_conf:update(
            wm_entity:set_attr({state, ?JOB_STATE_WAITING}, Job)),
    wm_factory:new(virtres, {create, JobId, TemplateNode}, predict_job_node_names(Job)).

% @doc Start relocation returning relocation ID that is a hash of the nodes involved into the relocation
-spec spawn_virtres(#job{}) -> {ok, integer(), node_id()} | {error, not_found}.
spawn_virtres(Job) ->
    JobId = wm_entity:get_attr(id, Job),
    case select_remote_site(Job) of
        {ok, TemplateNode} ->
            TemplateName = wm_entity:get_attr(name, TemplateNode),
            ?LOG_INFO("Found suited remote site for job ~p (~p)", [JobId, TemplateName]),
            1 =
                wm_conf:update(
                    wm_entity:set_attr({state, ?JOB_STATE_WAITING}, Job)),
            {ok, TaskId} = wm_factory:new(virtres, {create, JobId, TemplateNode}, predict_job_node_names(Job)),
            {ok, TaskId, wm_entity:get_attr(id, TemplateNode)};
        {error, not_found} ->
            ?LOG_DEBUG("No suited remote site found for job ~p", [JobId]),
            {error, not_found}
    end.

-spec predict_job_node_names(#job{}) -> [string()].
predict_job_node_names(Job) ->
    Seq = lists:seq(0, wm_utils:get_requested_nodes_number(Job) - 1),
    JobId = wm_entity:get_attr(id, Job),
    [wm_utils:get_cloud_node_name(JobId, SeqNum) || SeqNum <- Seq].

-spec do_cancel_relocation(#job{}) -> atom().
do_cancel_relocation(Job) ->
    JobId = wm_entity:get_attr(id, Job),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {error, not_found} ->
            ?LOG_DEBUG("No relocation is running => destroy related resources: ~p", [JobId]),
            {ok, TaskId} = wm_factory:new(virtres, {destroy, JobId, undefined}, []),
            RelocationDestraction =
                wm_entity:set_attr([{id, TaskId}, {job_id, JobId}, {canceled, true}], wm_entity:new(relocation)),
            remove_relocation_entities(Job),
            wm_conf:update(RelocationDestraction);
        {ok, Relocation} ->
            ?LOG_DEBUG("Relocation is running => destroy its resources (job: ~p)", [JobId]),
            RelocationId = wm_entity:get_attr(id, Relocation),
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
    JobId = wm_entity:get_attr(id, Job),
    case lists:keyfind(id, 1, Props) of
        false ->
            ?LOG_DEBUG("Partition resource does not have id property: ~p [job=~p]", [Props, JobId]),
            Cnt;
        {id, PartID} ->
            ?LOG_DEBUG("Delete partition entity ~p [job=~p]", [PartID, JobId]),
            ok = wm_conf:delete(partition, PartID),
            RssCnt = delete_resources(Rss, Job, 0),
            delete_part_id_from_cluster(Job, PartID),
            delete_resources(T, Job, Cnt + RssCnt + 1)
    end;
delete_resources([#resource{name = "node", properties = Props} | T], Job, Cnt) ->
    JobId = wm_entity:get_attr(id, Job),
    case lists:keyfind(id, 1, Props) of
        false ->
            ?LOG_DEBUG("Node resource does not have id property: ~p [job=~p]", [Props, JobId]),
            Cnt;
        {id, NodeID} ->
            ?LOG_DEBUG("Delete node entity ~p [job=~p]", [NodeID, JobId]),
            ok = wm_conf:delete(node, NodeID),
            delete_resources(T, Job, Cnt + 1)
    end.

-spec delete_part_id_from_cluster(#job{}, partition_id()) -> pos_integer().
delete_part_id_from_cluster(Job, PartID) ->
    ClusterID = wm_entity:get_attr(cluster_id, Job),
    {ok, Cluster1} = wm_conf:select(cluster, {id, ClusterID}),
    Parts1 = wm_entity:get_attr(partitions, Cluster1),
    Parts2 = lists:delete(PartID, Parts1),
    Cluster2 = wm_entity:set_attr([{partitions, Parts2}], Cluster1),
    1 = wm_conf:update(Cluster2).

%% ============================================================================
%% Tests
%% ============================================================================

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

match_resource_test() ->
    Resource0 = wm_entity:set_attr([{name, "a"}, {count, 100}], wm_entity:new(resource)),
    Resource1 = wm_entity:set_attr([{name, "b"}, {count, 10}], wm_entity:new(resource)),
    Resource2 = wm_entity:set_attr([{name, "a"}, {count, 150}], wm_entity:new(resource)),
    Resource3 = wm_entity:set_attr([{name, "c"}, {count, 100}], wm_entity:new(resource)),
    Resource4 = wm_entity:set_attr([{name, "d"}, {count, 100}], wm_entity:new(resource)),
    ?assertEqual(false, match_resource(Resource0, [Resource1, Resource3, Resource4])),
    ?assertEqual(true, match_resource(Resource0, [Resource1, Resource2, Resource3, Resource4])),
    ?assertEqual(true, match_resource(Resource0, [Resource0, Resource1, Resource2, Resource3, Resource4])),
    ok.

job_suited_node_test() ->
    Job = wm_entity:set_attr([{resources,
                               [wm_entity:set_attr([{name, "a"}, {count, 5}], wm_entity:new(resource)),
                                wm_entity:set_attr([{name, "b"}, {count, 15}], wm_entity:new(resource)),
                                wm_entity:set_attr([{name, "c"}, {count, 20}], wm_entity:new(resource))]}],
                             wm_entity:new(job)),
    Node0 =
        wm_entity:set_attr([{resources,
                             [wm_entity:set_attr([{name, "a"}, {count, 1}], wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "b"}, {count, 5}], wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "c"}, {count, 10}], wm_entity:new(resource))]}],
                           wm_entity:new(node)),
    Node1 =
        wm_entity:set_attr([{resources,
                             [wm_entity:set_attr([{name, "a"}, {count, 10}], wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "b"}, {count, 20}], wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "c"}, {count, 30}], wm_entity:new(resource))]}],
                           wm_entity:new(node)),
    Node2 =
        wm_entity:set_attr([{resources,
                             [wm_entity:set_attr([{name, "x"}, {count, 10}], wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "y"}, {count, 20}], wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "z"}, {count, 30}], wm_entity:new(resource))]}],
                           wm_entity:new(node)),
    ?assertEqual(false, job_suited_node(Job, Node2)),
    ?assertEqual(false, job_suited_node(Job, Node0)),
    ?assertEqual(true, job_suited_node(Job, Node1)),
    ok.

node_weight_common_test() ->
    Prices = [25.0, 30.0, 15.0],
    NetworkLatencies = [1000, 10 * 1000, 50 * 1000],
    [PN1, PN2, PN3] = norming(Prices),
    [NLN1, NLN2, NLN3] = norming(NetworkLatencies),
    ?assert(wm_utils:match_floats(1.4126172213833292, node_weight(PN1, NLN1, 1), 5)),
    ?assert(wm_utils:match_floats(1.1407338024430969, node_weight(PN2, NLN2, 1), 5)),
    ?assert(wm_utils:match_floats(1.7327807511042153, node_weight(PN3, NLN3, 1), 5)),
    ?assert(wm_utils:match_floats(1.5873475143912377, node_weight(PN1, NLN1, 1024), 5)),
    ?assert(wm_utils:match_floats(1.2500280148714087, node_weight(PN2, NLN2, 1024), 5)),
    ?assert(wm_utils:match_floats(1.5999713139289142, node_weight(PN3, NLN3, 1024), 5)),
    ?assert(wm_utils:match_floats(5.3560809346836940, node_weight(PN1, NLN1, 10 * 1024 * 1024 * 1024), 5)),
    ?assert(wm_utils:match_floats(2.7474729303989958, node_weight(PN2, NLN2, 10 * 1024 * 1024 * 1024), 5)),
    ?assert(wm_utils:match_floats(1.1141834944983267, node_weight(PN3, NLN3, 10 * 1024 * 1024 * 1024), 5)),
    ok.

select_remote_site_test() ->
    Job0 = wm_entity:set_attr([{account_id, JobAccoundId = 1}, {input_files, []}], wm_entity:new(job)),
    Job1 = wm_entity:set_attr([{account_id, JobAccoundId = 1}, {input_files, ["1.tar.gz"]}], wm_entity:new(job)),
    Job2 = wm_entity:set_attr([{account_id, JobAccoundId = 1}, {input_files, ["2.tar.gz"]}], wm_entity:new(job)),
    Node0 =
        wm_entity:set_attr([{resources,
                             [wm_entity:set_attr([{name, "a"}, {count, 1}, {prices, #{JobAccoundId => 25.0, 2 => 2.5}}],
                                                 wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "network_latency"}, {count, 1 * 1000}],
                                                 wm_entity:new(resource))]}],
                           wm_entity:new(node)),
    Node1 =
        wm_entity:set_attr([{resources,
                             [wm_entity:set_attr([{name, "a"}, {count, 1}, {prices, #{JobAccoundId => 30.0, 2 => 2.5}}],
                                                 wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "network_latency"}, {count, 10 * 1000}],
                                                 wm_entity:new(resource))]}],
                           wm_entity:new(node)),
    Node2 =
        wm_entity:set_attr([{resources,
                             [wm_entity:set_attr([{name, "a"}, {count, 1}, {prices, #{JobAccoundId => 15.0, 2 => 2.5}}],
                                                 wm_entity:new(resource)),
                              wm_entity:set_attr([{name, "network_latency"}, {count, 50 * 1000}],
                                                 wm_entity:new(resource))]}],
                           wm_entity:new(node)),
    meck:new(wm_file_utils, [unstick, passthrough]),
    meck:expect(wm_file_utils,
                get_size,
                fun ("1.tar.gz") ->
                        {ok, 1024};
                    ("2.tar.gz") ->
                        {ok, 1024 * 1024 * 1024}
                end),
    ?assertEqual({error, not_found}, select_remote_site(Job0, [])),
    ?assertEqual({ok, Node2}, select_remote_site(Job0, [Node0, Node1, Node2])),
    ?assertEqual({ok, Node2}, select_remote_site(Job1, [Node0, Node1, Node2])),
    ?assertEqual({ok, Node0}, select_remote_site(Job2, [Node0, Node1, Node2])),
    meck:unload(wm_file_utils),
    ok.

-endif.
