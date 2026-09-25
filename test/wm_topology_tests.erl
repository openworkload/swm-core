-module(wm_topology_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/lib/wm_entity.hrl").

%% Match wm_topology mstate so #mstate.ct / .rh work under eunit export_all.
-record(mstate,
        {rh :: map(),
         rh_index = #{} :: map(),
         rh_children = #{} :: map(),
         rh_neighbours = #{} :: map(),
         nl :: binary(),
         ct :: binary(),
         ct_map :: map(),
         mrole :: atom(),
         sname :: string(),
         constructing = false :: boolean()}).

%% ./rebar3 eunit --module=wm_topology_tests
%% Relies on eunit_compile_opts export_all for private helpers.

-spec get_mock_ct() -> #mstate{}.
get_mock_ct() ->
    RH = #{{grid, 1} =>
               #{{cluster, 1} => #{},
                 {cluster, 2} =>
                     #{{partition, 1} =>
                           #{{node, 1} => #{},
                             {node, 2} => #{},
                             {node, 3} => #{}},
                       {partition, 2} => #{}},
                 {cluster, 3} => #{}}},
    MState1 = #mstate{rh = RH},
    MState2 = wm_topology:do_make_nl(cluster, MState1),
    wm_topology:init_ct(MState2).

-spec init_ct_test() -> ok.
init_ct_test() ->
    MState = get_mock_ct(),
    RefCt =
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0,
          0, 0, 0, 0>>,
    ?assert(MState#mstate.ct == RefCt).

-spec get_value_from_cl_test() -> ok.
get_value_from_cl_test() ->
    CT = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
           0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7,
           0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
           0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1>>,
    ?assert(wm_topology:get_integer_by_pos(0, 0, 4, CT) == 0),
    ?assert(wm_topology:get_integer_by_pos(2, 1, 4, CT) == 8),
    ?assert(wm_topology:get_integer_by_pos(3, 3, 4, CT) == 72340172838076673).

-spec prepare_test_rh1() -> #{}.
prepare_test_rh1() ->
    % NOTE: in this RH id is also its name (for simplification),
    % grid, cluster and partition manager nodes have names/ids equals
    % to its subdivision id plus "_n0". All non-manager node names/ids
    % are formed as SUBDIVISION_ID plus "_nX", where X > 0.
    SetParent =
        fun ("c1_n0", Node) ->
                wm_entity:set([{parent, "g1_n0"}], Node);
            ("p11_n0", Node) ->
                wm_entity:set([{parent, "c1_n0"}], Node);
            ("c2_n0", Node) ->
                wm_entity:set([{parent, "g1_n0"}], Node);
            ("p21_n0", Node) ->
                wm_entity:set([{parent, "c2_n0"}], Node);
            ("p21_n1", Node) ->
                wm_entity:set([{parent, "p21_n0"}], Node);
            ("p21_n2", Node) ->
                wm_entity:set([{parent, "p21_n0"}], Node);
            ("p211_n0", Node) ->
                wm_entity:set([{parent, "p21_n0"}], Node);
            ("p211_n1", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p211_n2", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p211_n3", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p2111_n0", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p22_n0", Node) ->
                wm_entity:set([{parent, "c2_n0"}], Node);
            ("p221_n0", Node) ->
                wm_entity:set([{parent, "p22_n0"}], Node);
            ("p2211_n0", Node) ->
                wm_entity:set([{parent, "p221_n0"}], Node);
            ("p22111_n0", Node) ->
                wm_entity:set([{parent, "p2211_n0"}], Node);
            ("p22111_n1", Node) ->
                wm_entity:set([{parent, "p22111_n0"}], Node);
            ("c3_n0", Node) ->
                wm_entity:set([{parent, "g1_n0"}], Node);
            (_, Node) ->
                Node
        end,
    SelectById =
        fun (node, {id, Id}) ->
                Node = wm_entity:set([{id, Id}, {name, Id}], wm_entity:new(node)),
                {ok, SetParent(Id, Node)};
            (SubDiv, {id, Id}) ->
                {ok, wm_entity:set([{id, Id}, {name, Id}, {manager, Id ++ "_n0"}], wm_entity:new(SubDiv))}
        end,
    SelectByName = fun(NameIsAlsoId) -> SelectById(node, {id, NameIsAlsoId}) end,
    meck:new(wm_conf),
    meck:expect(wm_conf, select, SelectById),
    meck:expect(wm_conf, select_node, SelectByName),
    meck:new(wm_self),
    meck:expect(wm_self, get_node_id, fun() -> "c2_n0" end),
    #{{grid, "g1"} =>
          #{{cluster, "c1"} => #{{partition, "p11"} => #{}},
            {cluster, "c2"} =>
                #{{partition, "p21"} =>
                      #{{node, "p21_n1"} => #{},
                        {node, "p21_n2"} => #{},
                        {partition, "p211"} =>
                            #{{node, "p211_n1"} => #{},
                              {node, "p211_n2"} => #{},
                              {node, "p211_n3"} => #{},
                              {partition, "p2111"} => #{}}},
                  {partition, "p22"} =>
                      #{{partition, "p221"} =>
                            #{{partition, "p2211"} => #{{partition, "p22111"} => #{{node, "p22111_n1"} => #{}}}}}},
            {cluster, "c3"} => #{}}}.

-spec prepare_test_rh2() -> #{}.
prepare_test_rh2() ->
    % NOTE: in this RH node id is also its name (for simplification)
    SetExtraProperties =
        fun ("compute-node-1", Node) ->
                wm_entity:set([{parent, "node-skyport"}], Node);
            ("compute-node-2", Node) ->
                wm_entity:set([{parent, "compute-node-1"}], Node);
            ("template-node-1", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-2", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-3", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-4", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-5", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-6", Node) ->
                wm_entity:set([{is_template, true}], Node);
            (_, Node) ->
                Node
        end,
    SelectById =
        fun (node, {id, Id}) ->
                Node = wm_entity:set([{id, Id}, {name, Id}], wm_entity:new(node)),
                {ok, SetExtraProperties(Id, Node)};
            (cluster, {id, Id = "cluster"}) ->
                {ok,
                 wm_entity:set([{id, Id},
                                {name, Id},
                                {manager, "node-skyport"},
                                {partitions, ["remote-partition", "local-partition"]}],
                               wm_entity:new(cluster))};
            (partition, {id, Id = "remote-partition"}) ->
                {ok,
                 wm_entity:set([{id, Id},
                                {name, Id},
                                {manager, "node-skyport"},
                                {partitions, ["remote-sub-partition"]}],
                               wm_entity:new(partition))};
            (partition, {id, Id = "local-partition"}) ->
                {ok, wm_entity:set([{id, Id}, {name, Id}, {manager, "node-skyport"}], wm_entity:new(partition))};
            (partition, {id, Id = "remote-sub-partition"}) ->
                {ok, wm_entity:set([{id, Id}, {name, Id}, {manager, "compute-node-1"}], wm_entity:new(partition))}
        end,
    SelectByName = fun(NameIsAlsoId) -> SelectById(node, {id, NameIsAlsoId}) end,
    meck:new(wm_conf),
    meck:expect(wm_conf, select, SelectById),
    meck:expect(wm_conf, select_node, SelectByName),
    meck:new(wm_self),
    meck:expect(wm_self, get_node_id, fun() -> "node-skyport" end),
    #{{cluster, "cluster"} =>
          #{{partition, "remote-partition"} =>
                #{{node, "template-node-1"} => #{},
                  {node, "template-node-2"} => #{},
                  {node, "template-node-3"} => #{},
                  {node, "template-node-4"} => #{},
                  {node, "template-node-5"} => #{},
                  {node, "template-node-6"} => #{},
                  {partition, "remote-sub-partition"} =>
                      #{{node, "compute-node-1"} => #{}, {node, "compute-node-2"} => #{}}},
            {partition, "local-partition"} => #{{node, "node-skyport"} => #{}}}}.

-spec finalize() -> ok.
finalize() ->
    meck:unload().

-spec node_surrounding_rh_test() -> ok.
node_surrounding_rh_test() ->
    RH = prepare_test_rh1(),
    Expected =
        #{{node, "p21_n1"} => #{},
          {node, "p21_n2"} => #{},
          {partition, "p211"} =>
              #{{node, "p211_n1"} => #{},
                {node, "p211_n2"} => #{},
                {node, "p211_n3"} => #{},
                {partition, "p2111"} => #{}}},
    ?assertEqual(Expected, wm_topology:get_node_rh("p211_n0", RH, children_and_neighbours)),
    finalize().

-spec node_children_rh_test() -> ok.
node_children_rh_test() ->
    RH = prepare_test_rh1(),
    Expected =
        #{{node, "p211_n1"} => #{},
          {node, "p211_n2"} => #{},
          {node, "p211_n3"} => #{},
          {partition, "p2111"} => #{}},
    ?assertEqual(Expected, wm_topology:get_node_rh("p211_n0", RH, children_only)),
    finalize().

-spec children_nodes_test() -> ok.
children_nodes_test() ->
    RH = prepare_test_rh1(),
    Result = wm_topology:find_close_nodes("p211_n0", RH, children_only),
    ?assertEqual(4, length(Result)),
    ?assertMatch(#node{id = "p2111_n0"}, lists:nth(1, Result)),
    ?assertMatch(#node{id = "p211_n3"}, lists:nth(2, Result)),
    ?assertMatch(#node{id = "p211_n2"}, lists:nth(3, Result)),
    ?assertMatch(#node{id = "p211_n1"}, lists:nth(4, Result)),
    finalize().

-spec search_path_in_rh_test() -> ok.
search_path_in_rh_test() ->
    RH = prepare_test_rh1(),
    Index = wm_topology:build_rh_index(RH),
    % From top to bottom:
    ?assertEqual([], wm_topology:find_rh_path_from_index("c2_n0", "foo", Index)),
    ?assertEqual(["c2_n0", "p22_n0", "p221_n0", "p2211_n0", "p22111_n0", "p22111_n1"],
                 wm_topology:find_rh_path_from_index("c1_n0", "p22111_n1", Index)),
    ?assertEqual(["p211_n3"], wm_topology:find_rh_path_from_index("p211_n0", "p211_n3", Index)),
    ?assertEqual(["p211_n0"], wm_topology:find_rh_path_from_index("p21_n0", "p211_n0", Index)),
    ?assertEqual(["c2_n0"], wm_topology:find_rh_path_from_index("c1_n0", "c2_n0", Index)),
    ?assertEqual(["p21_n0", "p211_n0", "p211_n2"], wm_topology:find_rh_path_from_index("c2_n0", "p211_n2", Index)),
    ?assertEqual(["p21_n0", "p211_n0", "p2111_n0"], wm_topology:find_rh_path_from_index("c2_n0", "p2111_n0", Index)),
    ?assertEqual(["p22_n0", "p221_n0", "p2211_n0", "p22111_n0", "p22111_n1"],
                 wm_topology:find_rh_path_from_index("c2_n0", "p22111_n1", Index)),
    % From bottom to top:
    ?assertEqual([], wm_topology:find_rh_path_from_index("foo", "c2_n0", Index)),
    ?assertEqual(["p211_n0"], wm_topology:find_rh_path_from_index("p211_n3", "p211_n0", Index)),
    ?assertEqual(["p21_n0"], wm_topology:find_rh_path_from_index("p211_n0", "p21_n0", Index)),
    ?assertEqual([], wm_topology:find_rh_path_from_index("p2111_n0", "c2_n0", Index)),
    ?assertEqual([], wm_topology:find_rh_path_from_index("p22111_n1", "c2_n0", Index)),
    ?assertEqual([], wm_topology:find_rh_path_from_index("p211_n3", "c1_n0", Index)),
    finalize().

-spec children_duplicate_managers_test() -> ok.
children_duplicate_managers_test() ->
    RH = prepare_test_rh2(),
    Result = wm_topology:find_close_nodes("node-skyport", RH, children_only),
    ?assertEqual(1, length(Result)),
    ?assertMatch(#node{id = "compute-node-1"}, lists:nth(1, Result)),
    finalize().

-spec neighbours_duplicate_managers_test() -> ok.
neighbours_duplicate_managers_test() ->
    RH = prepare_test_rh2(),
    Result = wm_topology:find_close_nodes("node-skyport", RH, neighbours_only),
    ?assertEqual(0, length(Result)),
    finalize().

