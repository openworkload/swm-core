-module(wm_accounting).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([job_cost/1, node_prices/1]).
-export([update_node_prices/0]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_general.hrl").

-record(mstate, {}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec job_cost(#job{}) -> {ok, {#node{}, number()}} | {error, not_found}.
job_cost(Job) ->
    %TODO allow to estimate job cast via API
    Nodes = wm_relocator:get_suited_template_nodes(Job),
    %FIXME estimate costs per template nodes separatly (if we need this function at all)
    job_cost(Job, Nodes).

-spec node_prices(#node{}) -> #{}.
node_prices(Node) ->
    Resources = wm_entity:get(resources, Node),
    lists:foldl(fun(Resource, Acc) ->
                   Count = wm_entity:get(count, Resource),
                   Prices = wm_entity:get(prices, Resource),
                   maps:fold(fun(AccountId, Price, Acc2) ->
                                Acc2#{AccountId => maps:get(AccountId, Acc2, 0) + Count * Price}
                             end,
                             Acc,
                             Prices)
                end,
                #{},
                Resources).

-spec update_node_prices() -> ok.
update_node_prices() ->
    wm_utils:protected_call(?MODULE, update_node_prices).

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
    wm_works:call_asap(?MODULE, update_node_prices),
    ?LOG_INFO("Jobs accounting service has been started"),
    {ok, MState}.

handle_call(update_node_prices, _From, MState) ->
    Pred = fun(X) -> wm_entity:get(is_template, X) =:= false end,
    OldNodes =
        case wm_conf:select(node, Pred) of
            {ok, Xs} ->
                Xs;
            {error, not_found} ->
                []
        end,
    Accounts = wm_conf:select(account, all),
    NewNodes = apply_price_map_to_nodes(OldNodes, Accounts),
    true = wm_conf:update(NewNodes) == length(NewNodes),
    {reply, ok, MState};
handle_call(Msg, From, MState) ->
    ?LOG_INFO("Got not handled call message ~p from ~p", [Msg, From]),
    {reply, {error, not_handled}, MState}.

handle_cast(Msg, MState) ->
    ?LOG_INFO("Got not handled cast message ~p", [Msg]),
    {noreply, MState}.

handle_info(Info, MState) ->
    ?LOG_INFO("Got not handled message ~p", [Info]),
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

-spec get_suited_template_nodes(#job{}) -> [#node{}].
get_suited_template_nodes(Job) ->
    GetTemplates = fun(X) -> wm_entity:get(is_template, X) == true end,
    case wm_conf:select(node, GetTemplates) of
        {error, not_found} ->
            [];
        {ok, Nodes} ->
            get_suited_template_nodes(Job, Nodes)
    end.

-spec get_suited_template_nodes(#job{}, [#node{}]) -> [#node{}].
get_suited_template_nodes(Job, Nodes) ->
    lists:filter(fun(Node) -> job_suited_node(Job, Node) end, Nodes).

-spec job_suited_node(#job{}, #node{}) -> boolean().
job_suited_node(Job, Node) ->
    JobResources = wm_entity:get(resources, Job),
    NodeResources = wm_entity:get(resources, Node),
    F = fun(JobResource) -> match_resource(JobResource, NodeResources) end,
    lists:all(fun(X) -> X end, lists:map(F, JobResources)).

-spec match_resource(#resource{}, [#resource{}]) -> boolean().
match_resource(_, []) ->
    false;
match_resource(#resource{name = Name} = JobResource, [#resource{name = Name} = NodeResource | NodeResources]) ->
    DesiredCount = wm_entity:get(count, JobResource),
    AvailableCount = wm_entity:get(count, NodeResource),
    case DesiredCount =< AvailableCount of
        true ->
            true;
        false ->
            match_resource(JobResource, NodeResources)
    end;

match_resource(JobResource, [_NodeResource | NodeResources]) ->
    match_resource(JobResource, NodeResources).

-spec job_cost(#job{}, [#node{}]) -> {ok, {#node{}, number()}} | {error, not_found}.
job_cost(_, []) ->
    {error, not_found};
job_cost(Job, Nodes) ->
    AccountId = wm_entity:get(account_id, Job),
    Duration = wm_entity:get(duration, Job),
    [X | Xs] =
        lists:map(fun(Node) ->
                     Prices = node_prices(Node),
                     Price = maps:get(AccountId, Prices, 0),
                     Hour = 3600,
                     {Node, Price * (Duration / Hour)}
                  end,
                  Nodes),
    Result =
        lists:foldl(fun ({_CurrNode, CurrPrice} = Current, {_Node, Price}) when CurrPrice < Price ->
                            Current;
                        (_Current, Acc) ->
                            Acc
                    end,
                    X,
                    Xs),
    {ok, Result}.

apply_price_map_to_nodes(OldNodes, Accounts) ->
    F = fun(Account, Nodes) ->
           PriceList = wm_entity:get(price_list, Account),
           PriceMap = convert_price_list_to_map(PriceList, maps:new()),
           Apply =
               fun(Node) ->
                  case wm_entity:get(subdivision, Node) of
                      partition ->
                          PartId = wm_entity:get(subdivision_id, Node),
                          Part = wm_conf:select(partition, [PartId]),
                          apply_price_map(Node, Part, Account, PriceMap);
                      _ ->
                          NodeName = wm_entity:get(name, Node),
                          ?LOG_DEBUG("Node ~p is not in a partition!", [NodeName]),
                          Node
                  end
               end,
           [Apply(Node) || Node <- Nodes]
        end,
    lists:foldl(F, OldNodes, Accounts).

scan_price_line(Line) ->
    {ok, Scanned, _} = erl_scan:string(Line),
    case Scanned of
        %% example: "resource=mem price=0.4 when partition=*"
        [{_, _, resource},
         {'=', _},
         {_, _, Res},
         {_, _, price},
         {'=', _},
         {_, _, Price},
         {'when', _},
         {_, _, Cond},
         {'=', _},
         ScannedCondVal] ->
            CondVal =
                case ScannedCondVal of
                    {_, _, X} ->
                        X;
                    {X, 1} ->
                        X
                end,
            {atom_to_list(Res), Price, atom_to_list(Cond), atom_to_list(CondVal)};
        %% example: "resource=mem price=0.4"
        [{_, _, resource}, {'=', _}, {_, _, Res}, {_, _, price}, {'=', _}, {_, _, Price}] ->
            {atom_to_list(Res), Price, "", ""};
        _ ->
            {not_valid, Line}
    end.

convert_price_list_to_map([], Map) ->
    Reverse = fun(_, List) -> lists:reverse(List) end,
    maps:map(Reverse, Map);
convert_price_list_to_map([Line | T], Map) ->
    {Name, Price, CondObj, CondVal} = scan_price_line(Line),
    F = fun(List) -> [{Price, CondObj, CondVal} | List] end,
    Map2 =
        case maps:is_key(Name, Map) of
            true ->
                Map;
            _ ->
                maps:put(Name, [], Map)
        end,
    Map3 = maps:update_with(Name, F, Map2),
    convert_price_list_to_map(T, Map3).

%% @doc Go through each resource price filter and return price from passed ones
filter_node_price(_, _, [], FoundPrice) ->
    FoundPrice;
filter_node_price(Node, Partition, [{NewPrice, [], _} | T], _) ->
    filter_node_price(Node, Partition, T, NewPrice);
filter_node_price(Node, Partition, [{NewPrice, _, "*"} | T], _) ->
    filter_node_price(Node, Partition, T, NewPrice);
filter_node_price(Node, Partition, [{NewPrice, "partition", Name} | T], OldPrice) ->
    case wm_entity:get(name, Partition) of
        Name ->
            filter_node_price(Node, Partition, T, NewPrice);
        _ ->
            filter_node_price(Node, Partition, T, OldPrice)
    end;
filter_node_price(Node, Partition, [{NewPrice, "node", Name} | T], OldPrice) ->
    case wm_entity:get(name, Node) of
        Name ->
            filter_node_price(Node, Partition, T, NewPrice);
        _ ->
            filter_node_price(Node, Partition, T, OldPrice)
    end.

apply_price_map(Node, Partition, Account, PriceMap) ->
    AccId = wm_entity:get(id, Account),
    F = fun(Res) ->
           ResName = wm_entity:get(name, Res),
           PriceList = maps:get(ResName, PriceMap, []),
           ResPrice = filter_node_price(Node, Partition, PriceList, 0),
           OldPriceMap = wm_entity:get(prices, Res),
           NewPriceMap = maps:put(AccId, ResPrice, OldPriceMap),
           wm_entity:set({prices, NewPriceMap}, Res)
        end,
    UpdatedRss = [F(R) || R <- wm_entity:get(resources, Node)],
    wm_entity:set({resources, UpdatedRss}, Node).

-spec select_remote_site(#job{}, [#node{}]) -> {ok, #node{}} | {error, not_found}.
select_remote_site(_, []) ->
    {error, not_found};
select_remote_site(Job, Nodes) ->
    case wm_entity:get(nodes, Job) of
        [SomeNode] ->
            case wm_entity:get(is_template, SomeNode) of
                true ->
                    {ok, SomeNode};
                false ->
                    {error, "Job requests non-template node"}
            end;
        _ ->
            AccountId = wm_entity:get(account_id, Job),
            Files = wm_entity:get(input_files, Job),
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
            NetworkLatenciesNorm = norming(lists:map(fun(Node) -> ?MODULE:network_latency(Node) end, Nodes)),
            Xs = lists:zip3(Nodes, PricesNorm, NetworkLatenciesNorm),
            {_, Node} =
                lists:max(
                    lists:map(fun({Node, Price, NetworkLatency}) -> {node_weight(Price, NetworkLatency, Data), Node}
                              end,
                              Xs)),
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
    Resources = wm_entity:get(resources, Node),
    lists:foldl(fun (Resource = #resource{name = "network_latency"}, _Acc) ->
                        wm_entity:get(count, Resource);
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

%% ============================================================================
%% Tests
%% ============================================================================

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

run_test_() ->
    [{"Test price map creation", fun test_price_map_creation/0},
     {"Test price map applying", fun test_price_map_applying/0}].

get_mock_node(Name, PartitionId, Resources) ->
    N1 = wm_entity:new(<<"node">>),
    N2 = wm_entity:set({name, Name}, N1),
    N3 = wm_entity:set({id, wm_utils:uuid(v4)}, N2),
    N4 = wm_entity:set({subdivision, partition}, N3),
    N5 = wm_entity:set({subdivision_id, PartitionId}, N4),
    wm_entity:set({resources, Resources}, N5).

get_mock_partition(Name, PartitionId, NodeIds) ->
    N1 = wm_entity:new(<<"partition">>),
    N2 = wm_entity:set({name, Name}, N1),
    N3 = wm_entity:set({id, PartitionId}, N2),
    wm_entity:set({nodes, NodeIds}, N3).

get_mock_account(Name, AccId) ->
    A1 = wm_entity:new(<<"account">>),
    A2 = wm_entity:set({name, Name}, A1),
    wm_entity:set({id, AccId}, A2).

get_mock_resource(Name, Count, SubResources) ->
    R1 = wm_entity:new(<<"resource">>),
    R2 = wm_entity:set({name, Name}, R1),
    R3 = wm_entity:set({count, Count}, R2),
    wm_entity:set({resources, SubResources}, R3).

get_mock_price_list() ->
    ["resource=cpus price=0.3 when partition=*",
     "resource=cpus price=0.5 when node=node001",
     "resource=mem price=0.1",
     "resource=gpu price=0.3",
     "resource=gpu price=0.2 when partition=part1"].

test_price_map_creation() ->
    PriceList = get_mock_price_list(),
    PriceMap1 = convert_price_list_to_map(PriceList, maps:new()),
    PriceMap2 =
        #{"cpus" => [{0.3, "partition", "*"}, {0.5, "node", "node001"}],
          "mem" => [{0.1, "", ""}],
          "gpu" => [{0.3, "", ""}, {0.2, "partition", "part1"}]},
    ?assertMatch(PriceMap1, PriceMap2).

get_test_nodes_with_applied_price() ->
    PriceList = get_mock_price_list(),
    PriceMap = convert_price_list_to_map(PriceList, maps:new()),
    Part1Id = 1,
    Part2Id = 2,
    Res1 = get_mock_resource("cpus", 16, []),
    Res2 = get_mock_resource("gpu", 2, []),
    Res3 = get_mock_resource("mem", 64, []),
    Node1 = get_mock_node("node001", Part1Id, [Res1, Res2, Res3]),
    Res4 = get_mock_resource("cpus", 32, []),
    Res5 = get_mock_resource("gpu", 1, []),
    Res6 = get_mock_resource("mem", 32, []),
    Node2 = get_mock_node("node002", Part1Id, [Res4, Res5, Res6]),
    Res7 = get_mock_resource("cpus", 1, []),
    Node3 = get_mock_node("node003", Part2Id, [Res7]),
    Part1NodeIds = [wm_entity:get(id, Node1), wm_entity:get(id, Node2)],
    Part1 = get_mock_partition("part1", Part1Id, Part1NodeIds),
    Part2NodeIds = [wm_entity:get(id, Node3)],
    Part2 = get_mock_partition("part2", Part2Id, Part2NodeIds),
    Acc1Id = 1,
    Account = get_mock_account("acc1", Acc1Id),
    NewNode1 = apply_price_map(Node1, Part1, Account, PriceMap),
    NewNode2 = apply_price_map(Node2, Part1, Account, PriceMap),
    NewNode3 = apply_price_map(Node3, Part2, Account, PriceMap),
    [NewNode1, NewNode2, NewNode3].

test_price_map_applying() ->
    [Node1, Node2, Node3] = get_test_nodes_with_applied_price(),
    ResList1 = wm_entity:get(resources, Node1),
    ResList2 = wm_entity:get(resources, Node2),
    ResList3 = wm_entity:get(resources, Node3),
    ResList1Len = length(ResList1),
    ResList2Len = length(ResList2),
    ResList3Len = length(ResList3),
    ?assertMatch(ResList1Len, 3),
    ?assertMatch(ResList2Len, 3),
    ?assertMatch(ResList3Len, 1),
    Expected =
        #{"node001" =>
              #{"cpus" => 0.5,
                "gpu" => 0.2,
                "mem" => 0.1},
          "node002" =>
              #{"cpus" => 0.3,
                "gpu" => 0.2,
                "mem" => 0.1},
          "node003" => #{"cpus" => 0.3}},
    TestPrice =
        fun DoTestPrice(_, _, []) ->
                ok;
            DoTestPrice(NodeName, AccId, [NodeRes | T]) ->
                NodeResPriceMap = wm_entity:get(prices, NodeRes),
                NodeResPrice = maps:get(AccId, NodeResPriceMap),
                ResName = wm_entity:get(name, NodeRes),
                ResMap = maps:get(NodeName, Expected),
                ExpectedPrice = maps:get(ResName, ResMap),
                ?assertMatch(ExpectedPrice, NodeResPrice),
                DoTestPrice(NodeName, AccId, T)
        end,
    Acc1Id = 1,
    TestPrice("node001", Acc1Id, ResList1),
    TestPrice("node002", Acc1Id, ResList2),
    TestPrice("node003", Acc1Id, ResList3).

job_cost_test() ->
    Node0 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "mem"},
                                        {count, 10 * 1024 * 1024 * 1024},
                                        {prices, #{1 => 2.0, 2 => 6.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "storage"},
                                        {count, 500 * 1024 * 1024 * 1024},
                                        {prices, #{1 => 3.0, 2 => 7.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "cpus"}, {count, 4}, {prices, #{1 => 4.0, 2 => 8.0}}],
                                       wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node1 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "mem"},
                                        {count, 15 * 1024 * 1024 * 1024},
                                        {prices, #{1 => 2.0, 2 => 6.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "storage"},
                                        {count, 100 * 1024 * 1024 * 1024},
                                        {prices, #{1 => 3.0, 2 => 7.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "cpus"}, {count, 4}, {prices, #{1 => 4.0, 2 => 8.0}}],
                                       wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node2 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "mem"},
                                        {count, 20 * 1024 * 1024 * 1024},
                                        {prices, #{1 => 2.0, 2 => 6.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "storage"},
                                        {count, 50 * 1024 * 1024 * 1024},
                                        {prices, #{1 => 3.0, 2 => 7.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "cpus"}, {count, 4}, {prices, #{1 => 4.0, 2 => 8.0}}],
                                       wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Job = wm_entity:set([{account_id, 1},
                         {duration, 7200},
                         {resources,
                          [wm_entity:set([{name, "cpus"}, {count, 2}, {prices, #{}}], wm_entity:new(resource)),
                           wm_entity:set([{name, "mem"}, {count, 10 * 1024 * 1024 * 1024}, {prices, #{}}],
                                         wm_entity:new(resource)),
                           wm_entity:set([{name, "storage"}, {count, 50 * 1024 * 1024 * 1024}, {prices, #{}}],
                                         wm_entity:new(resource))]}],
                        wm_entity:new(job)),
    ?assertEqual({error, not_found}, job_cost(Job, [])),
    ?assertEqual({ok, {Node1, 708669603872.0}}, job_cost(Job, [Node0, Node1])),
    ?assertEqual({ok, {Node2, 408021893152.0}}, job_cost(Job, [Node1, Node2])),
    ok.

node_prices_test() ->
    Node0 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "compute"}, {count, 1}, {prices, #{1 => 1.0, 2 => 5.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "mem"}, {count, 1}, {prices, #{1 => 2.0, 2 => 6.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "storage"}, {count, 4}, {prices, #{1 => 3.0, 2 => 7.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "cpus"}, {count, 4}, {prices, #{1 => 4.0, 2 => 8.0}}],
                                       wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node1 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "compute"}, {count, 1}, {prices, #{1 => 10.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "mem"}, {count, 0.5}, {prices, #{1 => 20.0}}], wm_entity:new(resource)),
                         wm_entity:set([{name, "storage"}, {count, 1}, {prices, #{1 => 30.0}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "cpus"}, {count, 1}, {prices, #{1 => 40.0}}],
                                       wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    ?assertEqual(#{1 => 31.0, 2 => 71.0}, node_prices(Node0)),
    ?assertEqual(#{1 => 90.0}, node_prices(Node1)),
    ok.

job_suited_node_test() ->
    Job = wm_entity:set([{resources,
                          [wm_entity:set([{name, "a"}, {count, 5}], wm_entity:new(resource)),
                           wm_entity:set([{name, "b"}, {count, 15}], wm_entity:new(resource)),
                           wm_entity:set([{name, "c"}, {count, 20}], wm_entity:new(resource))]}],
                        wm_entity:new(job)),
    Node0 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "a"}, {count, 1}], wm_entity:new(resource)),
                         wm_entity:set([{name, "b"}, {count, 5}], wm_entity:new(resource)),
                         wm_entity:set([{name, "c"}, {count, 10}], wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node1 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "a"}, {count, 10}], wm_entity:new(resource)),
                         wm_entity:set([{name, "b"}, {count, 20}], wm_entity:new(resource)),
                         wm_entity:set([{name, "c"}, {count, 30}], wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node2 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "x"}, {count, 10}], wm_entity:new(resource)),
                         wm_entity:set([{name, "y"}, {count, 20}], wm_entity:new(resource)),
                         wm_entity:set([{name, "z"}, {count, 30}], wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    ?assertEqual(false, job_suited_node(Job, Node2)),
    ?assertEqual(false, job_suited_node(Job, Node0)),
    ?assertEqual(true, job_suited_node(Job, Node1)),
    ok.

select_remote_site_test() ->
    Job0 = wm_entity:set([{account_id, JobAccoundId = 1}, {input_files, []}], wm_entity:new(job)),
    Job1 = wm_entity:set([{account_id, JobAccoundId = 1}, {input_files, ["1.tar.gz"]}], wm_entity:new(job)),
    Job2 = wm_entity:set([{account_id, JobAccoundId = 1}, {input_files, ["2.tar.gz"]}], wm_entity:new(job)),
    Node0 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "a"}, {count, 1}, {prices, #{JobAccoundId => 25.0, 2 => 2.5}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "network_latency"}, {count, 1 * 1000}], wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node1 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "a"}, {count, 1}, {prices, #{JobAccoundId => 30.0, 2 => 2.5}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "network_latency"}, {count, 10 * 1000}], wm_entity:new(resource))]}],
                      wm_entity:new(node)),
    Node2 =
        wm_entity:set([{resources,
                        [wm_entity:set([{name, "a"}, {count, 1}, {prices, #{JobAccoundId => 15.0, 2 => 2.5}}],
                                       wm_entity:new(resource)),
                         wm_entity:set([{name, "network_latency"}, {count, 50 * 1000}], wm_entity:new(resource))]}],
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

match_resource_test() ->
    Resource0 = wm_entity:set([{name, "a"}, {count, 100}], wm_entity:new(resource)),
    Resource1 = wm_entity:set([{name, "b"}, {count, 10}], wm_entity:new(resource)),
    Resource2 = wm_entity:set([{name, "a"}, {count, 150}], wm_entity:new(resource)),
    Resource3 = wm_entity:set([{name, "c"}, {count, 100}], wm_entity:new(resource)),
    Resource4 = wm_entity:set([{name, "d"}, {count, 100}], wm_entity:new(resource)),
    ?assertEqual(false, match_resource(Resource0, [Resource1, Resource3, Resource4])),
    ?assertEqual(true, match_resource(Resource0, [Resource1, Resource2, Resource3, Resource4])),
    ?assertEqual(true, match_resource(Resource0, [Resource0, Resource1, Resource2, Resource3, Resource4])),
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

-endif.
