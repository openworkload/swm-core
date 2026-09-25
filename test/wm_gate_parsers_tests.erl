-module(wm_gate_parsers_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_gate_parsers_tests

-spec parse_images_test() -> ok.
parse_images_test() ->
    Input =
        <<"{\"images\":[",
          "{\"id\":\"i1\",\"name\":\"image1\",\"extra\":{\"status\":\"creating\"}},",
          "{\"id\":\"i2\",\"name\":\"cirros\",\"extra\":{\"status\":\"created\"}}]}">>,
    ExpectedImages =
        [wm_entity:set([{id, "i1"}, {name, "image1"}, {status, "creating"}, {kind, cloud}], wm_entity:new(image)),
         wm_entity:set([{id, "i2"}, {name, "cirros"}, {status, "created"}, {kind, cloud}], wm_entity:new(image))],
    ?assertEqual({ok, ExpectedImages}, wm_gate_parsers:parse_images(Input)),
    ?assertMatch({ok, []}, wm_gate_parsers:parse_images(<<"{\"images\":[]}">>)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_images(<<"foo">>)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_images(<<"">>)).

-spec parse_flavors_test() -> ok.
parse_flavors_test() ->
    AccountId = "899cd1a8-5f9f-11eb-9812-878c21b6d2b9",
    RemoteId = "75c7a748-5ed4-11ee-b279-83ee40f8d3f7",
    Remote = wm_entity:set([{id, RemoteId}, {account_id, AccountId}], wm_entity:new(remote)),
    Input =
        <<"{\"flavors\":[",
          "{\"id\":\"f1\",\"name\":\"flavor1\",\"cpus\":"
          "2,\"mem\":123456789, \"price\":2.5},",
          "{\"id\":\"f2\",\"name\":\"flavor2\",\"cpus\":"
          "1,\"mem\":100000000,\"storage\":12884901888, "
          "\"price\":0.3}]}">>,
    {ok, [ResultFlavorNodes1, ResultFlavorNodes2]} = wm_gate_parsers:parse_flavors(Input, Remote),
    ExpectedFlavorNodes =
        [wm_entity:set([{id, wm_entity:get(id, ResultFlavorNodes1)},
                        {name, "flavor1"},
                        {resources,
                         [wm_entity:set([{name, "cpus"}, {count, 2}], wm_entity:new(resource)),
                          wm_entity:set([{name, "mem"}, {count, 123456789}], wm_entity:new(resource))]},
                        {prices, #{AccountId => 2.5}},
                        {comment, "Cloud templated node"},
                        {remote_id, RemoteId},
                        {is_template, true}],
                       wm_entity:new(node)),
         wm_entity:set([{id, wm_entity:get(id, ResultFlavorNodes2)},
                        {name, "flavor2"},
                        {resources,
                         [wm_entity:set([{name, "cpus"}, {count, 1}], wm_entity:new(resource)),
                          wm_entity:set([{name, "mem"}, {count, 100000000}], wm_entity:new(resource)),
                          wm_entity:set([{name, "storage"}, {count, 12884901888}], wm_entity:new(resource))]},
                        {prices, #{AccountId => 0.3}},
                        {remote_id, RemoteId},
                        {comment, "Cloud templated node"},
                        {is_template, true}],
                       wm_entity:new(node))],
    ?assertEqual(ExpectedFlavorNodes, [ResultFlavorNodes1, ResultFlavorNodes2]),
    ?assertMatch({ok, []}, wm_gate_parsers:parse_flavors(<<"{\"flavors\":[]}">>, Remote)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_flavors(<<"foo">>, Remote)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_flavors(<<"">>, Remote)).

-spec parse_partitions_test() -> ok.
parse_partitions_test() ->
    Input =
        <<"{\"partitions\":[",
          "{\"id\":\"p1\",\"name\":\"stack1\",\"status\""
          ":\"creating\",",
          "\"created\":\"2021-01-02T15:18:39\", "
          "\"updated\":\"2021-01-02T16:18:40\",",
          "\"description\":\"test stack 1\"},",
          "{\"id\":\"p2\",\"name\":\"stack2\",\"status\""
          ":\"succeeded\",",
          "\"created\":\"2020-11-12T10:00:00\", "
          "\"updated\":\"2021-01-02T11:18:38\",",
          "\"description\":\"test stack 2\"}]}">>,
    ExpectedPartitions =
        [wm_entity:set([{id, "p1"},
                        {external_id, "p1"},
                        {name, "stack1"},
                        {state, creating},
                        {created, "2021-01-02T15:18:39"},
                        {updated, "2021-01-02T16:18:40"},
                        {comment, "test stack 1"}],
                       wm_entity:new(partition)),
         wm_entity:set([{id, "p2"},
                        {external_id, "p2"},
                        {name, "stack2"},
                        {state, up},
                        {created, "2020-11-12T10:00:00"},
                        {updated, "2021-01-02T11:18:38"},
                        {comment, "test stack 2"}],
                       wm_entity:new(partition))],
    {ok, Result} = wm_gate_parsers:parse_partitions(Input),
    ?assertEqual(2, length(Result)),
    [Part1, Part2] = Result,
    Part1_WithKnownId = wm_entity:set({id, "p1"}, Part1),
    Part2_WithKnownId = wm_entity:set({id, "p2"}, Part2),
    ?assertEqual(ExpectedPartitions, [Part1_WithKnownId, Part2_WithKnownId]),
    ?assertMatch({ok, []}, wm_gate_parsers:parse_partitions(<<"{\"partitions\":[]}">>)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_partitions(<<"foo">>)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_partitions(<<"">>)).

-spec parse_partition_created_test() -> ok.
parse_partition_created_test() ->
    ?assertEqual({ok, "part-1"},
                 wm_gate_parsers:parse_partition_created(<<"{\"partition\":{\"id\":\"part-1\",\"name\":\"n1\"}}">>)),
    ?assertMatch({error, {<<"boom">>, {part_id, "part-2"}}},
                 wm_gate_parsers:parse_partition_created(<<"{\"error\":\"boom\",\"partition\":{\"id\":\"part-2\"}}">>)),
    ?assertEqual({error, <<"Error from Azure: QuotaExceeded">>},
                 wm_gate_parsers:parse_partition_created(<<"{\"error\":\"Error from Azure: QuotaExceeded\",\"partition\":null}">>)),
    ?assertEqual({error, <<"Cannot create Azure deployment">>},
                 wm_gate_parsers:parse_partition_created(<<"{\"error\":\"Cannot create Azure deployment\"}">>)),
    ?assertMatch({error, _}, wm_gate_parsers:parse_partition_created(<<"foo">>)).
