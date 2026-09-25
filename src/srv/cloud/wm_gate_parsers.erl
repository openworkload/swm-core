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
    case wm_json:decode(Bin) of
        #{<<"images">> := List} when is_list(List) ->
            {ok, get_images_from_json(List, [])};
        Error ->
            {error, Error}
    end.

-spec parse_image(binary()) -> {ok, #image{}} | {error, any()}.
parse_image(Bin) ->
    case wm_json:decode(Bin) of
        Map when is_map(Map) ->
            {ok, get_one_image_from_json(Map)};
        Error ->
            {error, Error}
    end.

-spec get_images_from_json(list(), [#image{}]) -> [#image{}].
get_images_from_json([], Images) ->
    lists:reverse(Images);
get_images_from_json([ImageParams | T], Images) when is_map(ImageParams) ->
    EmptyImage = wm_entity:set([{kind, cloud}], wm_entity:new(image)),
    NewImage = fill_image_params(ImageParams, EmptyImage),
    get_images_from_json(T, [NewImage | Images]);
get_images_from_json([_ | T], Images) ->
    get_images_from_json(T, Images).

-spec get_one_image_from_json(map()) -> #image{}.
get_one_image_from_json(ImageParams) ->
    EmptyImage = wm_entity:set([{kind, cloud}], wm_entity:new(image)),
    fill_image_params(ImageParams, EmptyImage).

-spec fill_image_params(map(), #image{}) -> #image{}.
fill_image_params(Params, Image) when is_map(Params) ->
    maps:fold(fun fill_image_param/3, Image, Params).

-spec fill_image_param(binary(), term(), #image{}) -> #image{}.
fill_image_param(<<"id">>, Value, Image) when is_binary(Value) ->
    wm_entity:set({id, binary_to_list(Value)}, Image);
fill_image_param(<<"name">>, Value, Image) when is_binary(Value) ->
    wm_entity:set({name, binary_to_list(Value)}, Image);
fill_image_param(<<"extra">>, Extra, Image) when is_map(Extra) ->
    fill_image_extra(Extra, Image);
fill_image_param(_, null, Image) ->
    Image;
fill_image_param(_, _, Image) ->
    Image.

-spec fill_image_extra(map(), #image{}) -> #image{}.
fill_image_extra(Extra, Image) ->
    maps:fold(fun fill_image_extra_param/3, Image, Extra).

-spec fill_image_extra_param(binary(), term(), #image{}) -> #image{}.
fill_image_extra_param(<<"status">>, Value, Image) when is_binary(Value) ->
    wm_entity:set({status, binary_to_list(Value)}, Image);
fill_image_extra_param(<<"created">>, Value, Image) when is_binary(Value) ->
    wm_entity:set({created, binary_to_list(Value)}, Image);
fill_image_extra_param(<<"updated">>, Value, Image) when is_binary(Value) ->
    wm_entity:set({updated, binary_to_list(Value)}, Image);
fill_image_extra_param(_, _, Image) ->
    Image.

%%
%% Parse flavors
%%
-spec parse_flavors(binary(), #remote{}) -> {ok, [#node{}]} | {error, any()}.
parse_flavors(Bin, Remote) ->
    case wm_json:decode(Bin) of
        #{<<"flavors">> := List} when is_list(List) ->
            AccountId = wm_entity:get(account_id, Remote),
            RemoteId = wm_entity:get(id, Remote),
            {ok, get_flavor_nodes_from_json(List, AccountId, RemoteId, [])};
        Error ->
            {error, Error}
    end.

-spec get_flavor_nodes_from_json(list(), account_id(), remote_id(), [#node{}]) -> [#node{}].
get_flavor_nodes_from_json([], _, _, Nodes) ->
    lists:reverse(Nodes);
get_flavor_nodes_from_json([FlavorParams | T], AccountId, RemoteId, Nodes) when is_map(FlavorParams) ->
    NodeId = wm_utils:uuid(v4),
    EmptyNode =
        wm_entity:set([{id, NodeId}, {is_template, true}, {remote_id, RemoteId}, {comment, "Cloud templated node"}],
                      wm_entity:new(node)),
    NewNode = fill_flavor_node_params(FlavorParams, EmptyNode, AccountId),
    get_flavor_nodes_from_json(T, AccountId, RemoteId, [NewNode | Nodes]);
get_flavor_nodes_from_json([_ | T], AccountId, RemoteId, Nodes) ->
    get_flavor_nodes_from_json(T, AccountId, RemoteId, Nodes).

-spec fill_flavor_node_params(map(), #node{}, account_id()) -> #node{}.
fill_flavor_node_params(Params, Node, AccountId) when is_map(Params) ->
    Node2 = maps:fold(fun(K, V, Acc) -> fill_flavor_node_param(K, V, Acc, AccountId) end, Node, Params),
    wm_entity:set({resources,
                   lists:reverse(
                       wm_entity:get(resources, Node2))},
                  Node2).

-spec fill_flavor_node_param(binary(), term(), #node{}, account_id()) -> #node{}.
fill_flavor_node_param(<<"name">>, Value, Node, _) when is_binary(Value) ->
    wm_entity:set([{name, binary_to_list(Value)}], Node);
fill_flavor_node_param(<<"cpus">>, Value, Node, _) ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "cpus"}, {count, Value}], wm_entity:new(resource)),
    wm_entity:set({resources, [NewResource | Resources]}, Node);
fill_flavor_node_param(<<"gpus">>, Value, Node, _) when Value > 0 ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "gpus"}, {count, Value}], wm_entity:new(resource)),
    wm_entity:set({resources, [NewResource | Resources]}, Node);
fill_flavor_node_param(<<"mem">>, Value, Node, _) ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "mem"}, {count, Value}], wm_entity:new(resource)),
    wm_entity:set({resources, [NewResource | Resources]}, Node);
fill_flavor_node_param(<<"storage">>, Value, Node, _) ->
    Resources = wm_entity:get(resources, Node),
    NewResource = wm_entity:set([{name, "storage"}, {count, Value}], wm_entity:new(resource)),
    wm_entity:set({resources, [NewResource | Resources]}, Node);
fill_flavor_node_param(<<"price">>, Value, Node, AccountId) ->
    wm_entity:set({prices, #{AccountId => Value}}, Node);
fill_flavor_node_param(_, _, Node, _) ->
    Node.

%%
%% Parse partitions
%%
-spec parse_partition_created(binary()) -> {ok, string()} | {error, any()}.
parse_partition_created(Bin) ->
    case wm_json:decode(Bin) of
        Map when is_map(Map) ->
            Error = maps:get(<<"error">>, Map, undefined),
            Partition = maps:get(<<"partition">>, Map, undefined),
            case {Partition, Error} of
                {PartMap, undefined} when is_map(PartMap) ->
                    case maps:get(<<"id">>, PartMap, undefined) of
                        PartIdBin when is_binary(PartIdBin) ->
                            {ok, binary_to_list(PartIdBin)};
                        _ ->
                            {error, {invalid_partition, Map}}
                    end;
                {PartMap, Msg} when is_map(PartMap), Msg =/= undefined ->
                    PartId =
                        case maps:get(<<"id">>, PartMap, undefined) of
                            PartIdBin when is_binary(PartIdBin) ->
                                binary_to_list(PartIdBin);
                            _ ->
                                undefined
                        end,
                    {error, {Msg, {part_id, PartId}}};
                {_, Msg} when Msg =/= undefined, Msg =/= null ->
                    %% Gate returns HTTP 200 with {"error": "...", "partition": null}
                    %% for permanent Azure failures (e.g. QuotaExceeded).
                    {error, Msg};
                _ ->
                    {error, Map}
            end;
        Error ->
            {error, Error}
    end.

-spec parse_partition_deleted(binary()) -> {ok, string()} | {error, any()}.
parse_partition_deleted(Bin) ->
    case wm_json:decode(Bin) of
        #{<<"result">> := Result} when is_binary(Result) ->
            {ok, binary_to_list(Result)};
        Error ->
            {error, Error}
    end.

-spec parse_partition(binary()) -> {ok, #partition{}} | {error, any()}.
parse_partition(Bin) ->
    case wm_json:decode(Bin) of
        Map when is_map(Map) ->
            {ok, get_one_partition_from_json(Map)};
        Error ->
            {error, Error}
    end.

-spec parse_partitions(binary()) -> {ok, [#partition{}]} | {error, any()}.
parse_partitions(Bin) ->
    case wm_json:decode(Bin) of
        #{<<"partitions">> := List} when is_list(List) ->
            {ok, get_partitions_from_json(List, [])};
        Error ->
            {error, Error}
    end.

-spec get_one_partition_from_json(map()) -> #partition{}.
get_one_partition_from_json(PartParams) ->
    EmptyPart = wm_entity:set([{id, wm_utils:uuid(v4)}], wm_entity:new(partition)),
    fill_partition_params(PartParams, EmptyPart).

-spec get_partitions_from_json(list(), [#partition{}]) -> [#partition{}].
get_partitions_from_json([], Parts) ->
    lists:reverse(Parts);
get_partitions_from_json([Params | T], Parts) when is_map(Params) ->
    PartId = wm_utils:uuid(v4),
    EmptyPart = wm_entity:set([{id, PartId}], wm_entity:new(partition)),
    NewPart = fill_partition_params(Params, EmptyPart),
    get_partitions_from_json(T, [NewPart | Parts]);
get_partitions_from_json([_ | T], Parts) ->
    get_partitions_from_json(T, Parts).

-spec fill_partition_params(map(), #partition{}) -> #partition{}.
fill_partition_params(Params, Part) when is_map(Params) ->
    maps:fold(fun fill_partition_param/3, Part, Params).

-spec fill_partition_param(binary(), term(), #partition{}) -> #partition{}.
fill_partition_param(<<"name">>, Value, Part) when is_binary(Value) ->
    wm_entity:set([{name, binary_to_list(Value)}], Part);
fill_partition_param(<<"id">>, Value, Part) when is_binary(Value) ->
    wm_entity:set([{external_id, binary_to_list(Value)}], Part);
fill_partition_param(<<"status">>, Value, Part) when is_binary(Value) ->
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
    wm_entity:set([{state, State}], Part);
fill_partition_param(<<"created">>, Value, Part) when Value =/= null, is_binary(Value) ->
    wm_entity:set([{created, binary_to_list(Value)}], Part);
fill_partition_param(<<"updated">>, Value, Part) when Value =/= null, is_binary(Value) ->
    wm_entity:set([{updated, binary_to_list(Value)}], Part);
fill_partition_param(<<"description">>, Value, Part) when Value =/= null, is_binary(Value) ->
    wm_entity:set([{comment, binary_to_list(Value)}], Part);
fill_partition_param(<<"master_public_ip">>, Value, Part) when Value =/= null, is_binary(Value) ->
    Addresses1 = wm_entity:get(addresses, Part),
    Addresses2 = maps:put(master_public_ip, binary_to_list(Value), Addresses1),
    wm_entity:set([{addresses, Addresses2}], Part);
fill_partition_param(<<"master_private_ip">>, Value, Part) when Value =/= null, is_binary(Value) ->
    Addresses1 = wm_entity:get(addresses, Part),
    Addresses2 = maps:put(master_private_ip, binary_to_list(Value), Addresses1),
    wm_entity:set([{addresses, Addresses2}], Part);
fill_partition_param(<<"compute_instances_ips">>, Values, Part) when Values =/= null, is_list(Values) ->
    Addresses1 = wm_entity:get(addresses, Part),
    IPsOld = maps:get(compute_instances_ips, Addresses1, []),
    IPsNew =
        lists:map(fun (X) when X =/= null, is_binary(X) ->
                          binary_to_list(X);
                      (Y) ->
                          Y
                  end,
                  Values),
    Addresses2 = maps:put(compute_instances_ips, IPsNew ++ IPsOld, Addresses1),
    wm_entity:set([{addresses, Addresses2}], Part);
fill_partition_param(_, _, Part) ->
    Part.
