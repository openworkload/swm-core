-module(wm_accounting_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_accounting_tests
%% Relies on eunit_compile_opts export_all for private helpers.

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
    PriceMap1 = wm_accounting:convert_price_list_to_map(PriceList, maps:new()),
    PriceMap2 =
        #{"cpus" => [{0.3, "partition", "*"}, {0.5, "node", "node001"}],
          "mem" => [{0.1, "", ""}],
          "gpu" => [{0.3, "", ""}, {0.2, "partition", "part1"}]},
    ?assertMatch(PriceMap1, PriceMap2).

get_test_nodes_with_applied_price() ->
    PriceList = get_mock_price_list(),
    PriceMap = wm_accounting:convert_price_list_to_map(PriceList, maps:new()),
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
    NewNode1 = wm_accounting:apply_price_map(Node1, Part1, Account, PriceMap),
    NewNode2 = wm_accounting:apply_price_map(Node2, Part1, Account, PriceMap),
    NewNode3 = wm_accounting:apply_price_map(Node3, Part2, Account, PriceMap),
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
    ?assertEqual({error, not_found}, wm_accounting:job_cost(Job, [])),
    ?assertEqual({ok, {Node1, 708669603872.0}}, wm_accounting:job_cost(Job, [Node0, Node1])),
    ?assertEqual({ok, {Node2, 408021893152.0}}, wm_accounting:job_cost(Job, [Node1, Node2])),
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
    ?assertEqual(#{1 => 31.0, 2 => 71.0}, wm_accounting:node_prices(Node0)),
    ?assertEqual(#{1 => 90.0}, wm_accounting:node_prices(Node1)),
    ok.

node_weight_common_test() ->
    Prices = [25.0, 30.0, 15.0],
    NetworkLatencies = [1000, 10 * 1000, 50 * 1000],
    [PN1, PN2, PN3] = wm_accounting:norming(Prices),
    [NLN1, NLN2, NLN3] = wm_accounting:norming(NetworkLatencies),
    ?assert(wm_utils:match_floats(1.4126172213833292, wm_accounting:node_weight(PN1, NLN1, 1), 5)),
    ?assert(wm_utils:match_floats(1.1407338024430969, wm_accounting:node_weight(PN2, NLN2, 1), 5)),
    ?assert(wm_utils:match_floats(1.7327807511042153, wm_accounting:node_weight(PN3, NLN3, 1), 5)),
    ?assert(wm_utils:match_floats(1.5873475143912377, wm_accounting:node_weight(PN1, NLN1, 1024), 5)),
    ?assert(wm_utils:match_floats(1.2500280148714087, wm_accounting:node_weight(PN2, NLN2, 1024), 5)),
    ?assert(wm_utils:match_floats(1.5999713139289142, wm_accounting:node_weight(PN3, NLN3, 1024), 5)),
    ?assert(wm_utils:match_floats(5.3560809346836940, wm_accounting:node_weight(PN1, NLN1, 10 * 1024 * 1024 * 1024), 5)),
    ?assert(wm_utils:match_floats(2.7474729303989958, wm_accounting:node_weight(PN2, NLN2, 10 * 1024 * 1024 * 1024), 5)),
    ?assert(wm_utils:match_floats(1.1141834944983267, wm_accounting:node_weight(PN3, NLN3, 10 * 1024 * 1024 * 1024), 5)),
    ok.
