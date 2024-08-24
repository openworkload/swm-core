-module(wm_gate_parsers).

-export([parse_images/1, parse_image/1, parse_flavors/2, parse_partitions/1, parse_partition/1,
         parse_partition_created/1, parse_partition_deleted/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

%%
%% Parse images
%%
-spec parse_images(binary()) -> {ok, [#image{}]} | {error, any()}.
parse_images(Bin) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, [{<<"images">>, List}]} ->
            {ok, get_images_from_json(List, [])};
        Error ->
            {error, Error}
    end.

-spec parse_image(binary()) -> {ok, #image{}} | {error, any()}.
parse_image(Bin) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, ImageParams} when is_list(ImageParams) ->
            {ok, get_one_image_from_json(ImageParams)};
        Error ->
            {error, Error}
    end.

-spec get_images_from_json(list(), [#image{}]) -> [#image{}].
get_images_from_json([], Images) ->
    lists:reverse(Images);
get_images_from_json([{struct, ImageParams} | T], Images) ->
    EmptyImage = wm_entity:set([{kind, cloud}], wm_entity:new(image)),
    NewImage = fill_image_params(ImageParams, EmptyImage),
    get_images_from_json(T, [NewImage | Images]).

-spec get_one_image_from_json(list()) -> #image{}.
get_one_image_from_json(ImageParams) ->
    EmptyImage = wm_entity:set([{kind, cloud}], wm_entity:new(image)),
    fill_image_params(ImageParams, EmptyImage).

-spec fill_image_params([{binary(), binary()}], #image{}) -> #image{}.
fill_image_params([], Image) ->
    Image;
fill_image_params([{B, _} | T], Image) when not is_binary(B) ->
    fill_image_params(T, Image);
fill_image_params([{<<"id">>, Value} | T], Image) ->
    fill_image_params(T, wm_entity:set({id, binary_to_list(Value)}, Image));
fill_image_params([{<<"name">>, Value} | T], Image) ->
    fill_image_params(T, wm_entity:set({name, binary_to_list(Value)}, Image));
fill_image_params([{<<"extra">>, {struct, List}} | T], Image) ->
    fill_image_params(T, fill_image_extra(List, Image));
fill_image_params([{_, null} | T], Image) ->
    fill_image_params(T, Image);
fill_image_params([_ | T], Image) ->
    fill_image_params(T, Image).

-spec fill_image_extra([{binary(), binary()}], #image{}) -> #image{}.
fill_image_extra([], Image) ->
    Image;
fill_image_extra([{<<"status">>, Value} | T], Image) ->
    fill_image_extra(T, wm_entity:set({status, binary_to_list(Value)}, Image));
fill_image_extra([{<<"created">>, Value} | T], Image) ->
    fill_image_extra(T, wm_entity:set({created, binary_to_list(Value)}, Image));
fill_image_extra([{<<"updated">>, Value} | T], Image) ->
    fill_image_extra(T, wm_entity:set({updated, binary_to_list(Value)}, Image));
fill_image_extra([{_, _} | T], Image) ->
    fill_image_extra(T, Image).

%%
%% Parse flavors
%%
-spec parse_flavors(binary(), #remote{}) -> {ok, [#node{}]} | {error, any()}.
parse_flavors(Bin, Remote) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, [{<<"flavors">>, List}]} ->
            AccountId = wm_entity:get(account_id, Remote),
            RemoteId = wm_entity:get(id, Remote),
            {ok, get_flavor_nodes_from_json(List, AccountId, RemoteId, [])};
        Error ->
            {error, Error}
    end.

-spec get_flavor_nodes_from_json(list(), account_id(), remote_id(), [#node{}]) -> [#node{}].
get_flavor_nodes_from_json([], _, _, Nodes) ->
    lists:reverse(Nodes);
get_flavor_nodes_from_json([{struct, FlavorParams} | T], AccountId, RemoteId, Nodes) ->
    NodeId = wm_utils:uuid(v4),
    EmptyNode =
        wm_entity:set([{id, NodeId}, {is_template, true}, {remote_id, RemoteId}, {comment, "Cloud templated node"}],
                      wm_entity:new(node)),
    NewNode = fill_flavor_node_params(FlavorParams, EmptyNode, AccountId),
    get_flavor_nodes_from_json(T, AccountId, RemoteId, [NewNode | Nodes]).

-spec fill_flavor_node_params([{binary(), binary()}], #node{}, account_id()) -> #node{}.
fill_flavor_node_params([], Node, _) ->
    wm_entity:set({resources,
                   lists:reverse(
                       wm_entity:get(resources, Node))},
                  Node);
fill_flavor_node_params([{B, _} | T], Node, AccountId) when not is_binary(B) ->
    fill_flavor_node_params(T, Node, AccountId);
fill_flavor_node_params([{<<"name">>, Value} | T], Node, AccountId) ->
    ValueStr = binary_to_list(Value),
    NewNode = wm_entity:set([{name, ValueStr}], Node),
    fill_flavor_node_params(T, NewNode, AccountId);
fill_flavor_node_params([{<<"cpus">>, Value} | T], Node, AccountId) ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "cpus"}, {count, Value}], wm_entity:new(resource)),
    fill_flavor_node_params(T, wm_entity:set({resources, [NewResource | Resources]}, Node), AccountId);
fill_flavor_node_params([{<<"mem">>, Value} | T], Node, AccountId) ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "mem"}, {count, Value}], wm_entity:new(resource)),
    fill_flavor_node_params(T, wm_entity:set({resources, [NewResource | Resources]}, Node), AccountId);
fill_flavor_node_params([{<<"storage">>, Value} | T], Node, AccountId) ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "storage"}, {count, Value}], wm_entity:new(resource)),
    fill_flavor_node_params(T, wm_entity:set({resources, [NewResource | Resources]}, Node), AccountId);
fill_flavor_node_params([{<<"price">>, Value} | T], Node, AccountId) ->
    NewNode = wm_entity:set({prices, #{AccountId => Value}}, Node),
    fill_flavor_node_params(T, NewNode, AccountId);
fill_flavor_node_params([_ | T], Node, AccountId) ->
    fill_flavor_node_params(T, Node, AccountId).

%%
%% Parse partitions
%%
-spec parse_partition_created(binary()) -> {ok, string()} | {error, any()}.
parse_partition_created(Bin) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, [{<<"partition">>, {struct, [{<<"id">>, PartIdBin} | _]}}]} ->
            {ok, binary_to_list(PartIdBin)};
        Error ->
            {error, Error}
    end.

-spec parse_partition_deleted(binary()) -> {ok, string()} | {error, any()}.
parse_partition_deleted(Bin) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, [{<<"result">>, Result}]} ->
            {ok, binary_to_list(Result)};
        Error ->
            {error, Error}
    end.

-spec parse_partition(binary()) -> {ok, #partition{}} | {error, any()}.
parse_partition(Bin) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, PartParams} when is_list(PartParams) ->
            {ok, get_one_partition_from_json(PartParams)};
        Error ->
            {error, Error}
    end.

-spec parse_partitions(binary()) -> {ok, [#partition{}]} | {error, any()}.
parse_partitions(Bin) ->
    JsonStr = binary_to_list(Bin),
    case wm_json:decode(JsonStr) of
        {struct, [{<<"partitions">>, List}]} ->
            {ok, get_partitions_from_json(List, [])};
        Error ->
            {error, Error}
    end.

-spec get_one_partition_from_json(list()) -> #partition{}.
get_one_partition_from_json(PartParams) ->
    EmptyPart = wm_entity:set([{id, wm_utils:uuid(v4)}], wm_entity:new(partition)),
    fill_partition_params(PartParams, EmptyPart).

-spec get_partitions_from_json(list(), [#partition{}]) -> [#partition{}].
get_partitions_from_json([], Parts) ->
    lists:reverse(Parts);
get_partitions_from_json([{struct, Params} | T], Parts) ->
    PartId = wm_utils:uuid(v4),
    EmptyPart = wm_entity:set([{id, PartId}], wm_entity:new(partition)),
    NewPart = fill_partition_params(Params, EmptyPart),
    get_partitions_from_json(T, [NewPart | Parts]).

-spec fill_partition_params([{binary(), binary()}], #partition{}) -> #partition{}.
fill_partition_params([], Part) ->
    Part;
fill_partition_params([{B, _} | T], Part) when not is_binary(B) ->
    fill_partition_params(T, Part);
fill_partition_params([{<<"name">>, Value} | T], Part) ->
    ValueStr = binary_to_list(Value),
    NewPart = wm_entity:set([{name, ValueStr}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"id">>, Value} | T], Part) ->
    ValueStr = binary_to_list(Value),
    NewPart = wm_entity:set([{external_id, ValueStr}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"status">>, Value} | T], Part) ->
    State =
        case Value of
            <<"creating">> ->
                creating;
            <<"updating">> ->
                creating;
            <<"succeeded">> ->
                up;
            _ ->
                down
        end,
    NewPart = wm_entity:set([{state, State}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"created">>, Value} | T], Part) when Value =/= null ->
    NewPart = wm_entity:set([{created, binary_to_list(Value)}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"updated">>, Value} | T], Part) when Value =/= null ->
    NewPart = wm_entity:set([{updated, binary_to_list(Value)}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"description">>, Value} | T], Part) when Value =/= null ->
    NewPart = wm_entity:set([{comment, binary_to_list(Value)}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"master_public_ip">>, Value} | T], Part) when Value =/= null ->
    Addresses1 = wm_entity:get(addresses, Part),
    Addresses2 = maps:put(master_public_ip, binary_to_list(Value), Addresses1),
    NewPart = wm_entity:set([{addresses, Addresses2}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"master_private_ip">>, Value} | T], Part) when Value =/= null ->
    Addresses1 = wm_entity:get(addresses, Part),
    Addresses2 = maps:put(master_private_ip, binary_to_list(Value), Addresses1),
    NewPart = wm_entity:set([{addresses, Addresses2}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([{<<"compute_instances_ips">>, Values} | T], Part) when Values =/= null ->
    Addresses1 = wm_entity:get(addresses, Part),
    IPsOld = maps:get(compute_instances_ips, Addresses1, []),
    IPsNew =
        lists:map(fun (X) when X =/= null ->
                          binary_to_list(X);
                      (Y) ->
                          Y
                  end,
                  Values),
    Addresses2 = maps:put(compute_instances_ips, IPsNew ++ IPsOld, Addresses1),
    NewPart = wm_entity:set([{addresses, Addresses2}], Part),
    fill_partition_params(T, NewPart);
fill_partition_params([_ | T], Part) ->
    fill_partition_params(T, Part).

%% ============================================================================
%% Tests
%% ============================================================================

-ifdef(EUNIT).

-include_lib("eunit/include/eunit.hrl").

% ./rebar3 eunit --module=wm_gate_parsers
-spec parse_images_test() -> ok.
parse_images_test() ->
    Input =
        <<"{\"images\":[",
          "{\"id\":\"i1\",\"name\":\"image1\",\"extra\":{\"status\":\"creating\"}},",
          "{\"id\":\"i2\",\"name\":\"cirros\",\"extra\":{\"status\":\"created\"}}]}">>,
    ExpectedImages =
        [wm_entity:set([{id, "i1"}, {name, "image1"}, {status, "creating"}, {kind, cloud}], wm_entity:new(image)),
         wm_entity:set([{id, "i2"}, {name, "cirros"}, {status, "created"}, {kind, cloud}], wm_entity:new(image))],
    ?assertEqual({ok, ExpectedImages}, parse_images(Input)),
    ?assertMatch({ok, []}, parse_images(<<"{\"images\":[]}">>)),
    ?assertMatch({error, _}, parse_images(<<"foo">>)),
    ?assertMatch({error, _}, parse_images(<<"">>)).

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
    {ok, [ResultFlavorNodes1, ResultFlavorNodes2]} = parse_flavors(Input, Remote),
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
    ?assertMatch({ok, []}, parse_flavors(<<"{\"flavors\":[]}">>, Remote)),
    ?assertMatch({error, _}, parse_flavors(<<"foo">>, Remote)),
    ?assertMatch({error, _}, parse_flavors(<<"">>, Remote)).

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
    {ok, Result} = parse_partitions(Input),
    ?assertEqual(2, length(Result)),
    [Part1, Part2] = Result,
    Part1_WithKnownId = wm_entity:set({id, "p1"}, Part1),
    Part2_WithKnownId = wm_entity:set({id, "p2"}, Part2),
    ?assertEqual(ExpectedPartitions, [Part1_WithKnownId, Part2_WithKnownId]),
    ?assertMatch({ok, []}, parse_partitions(<<"{\"partitions\":[]}">>)),
    ?assertMatch({error, _}, parse_partitions(<<"foo">>)),
    ?assertMatch({error, _}, parse_partitions(<<"">>)).

-endif.
