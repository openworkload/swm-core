%% @doc Helpers for wm_user_rest related to JSON generation.
-module(wm_user_json).

-export([get_resources_json/1, get_roles_json/1, find_resource_count/2, find_flavor_and_remote_ids/1,
         get_api_version_json/0]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(API_VERSION, "1").

-spec get_api_version_json() -> list().
get_api_version_json() ->
    ["{\"api_version\": "] ++ ?API_VERSION ++ ["}"].

-spec get_resources_json([#resource{}]) -> list().
get_resources_json(Resources) ->
    lists:foldl(fun(Resource, Acc) ->
                   Map1 =
                       #{name => list_to_binary(wm_entity:get_attr(name, Resource)),
                         count => wm_entity:get_attr(count, Resource)},
                   Map2 =
                       case find_value_property(Resource) of
                           "" ->
                               Map1;
                           Value ->
                               maps:put(value, list_to_binary(Value), Map1)
                       end,
                   [Map2 | Acc]
                end,
                [],
                Resources).

-spec get_roles_json(#node{}) -> list().
get_roles_json(Node) ->
    lists:foldl(fun(RoleId, Acc) ->
                   case wm_conf:select(role, {id, RoleId}) of
                       {ok, Role} ->
                           PropertiesMap =
                               #{id => wm_entity:get_attr(id, Role),
                                 name => list_to_binary(wm_entity:get_attr(name, Role)),
                                 comment => list_to_binary(wm_entity:get_attr(comment, Role))},
                           [PropertiesMap | Acc];
                       _ ->
                           Acc
                   end
                end,
                [],
                wm_entity:get_attr(roles, Node)).

-spec find_resource_count(string(), [#resource{}]) -> pos_integer().
find_resource_count(Name, Resources) ->
    case lists:keyfind(Name, 2, Resources) of
        false ->
            0;
        Resource ->
            wm_entity:get_attr(count, Resource)
    end.

-spec find_flavor_and_remote_ids(#job{}) -> {node_id(), remote_id()}.
find_flavor_and_remote_ids(Job) ->
    RequestedResources = wm_entity:get_attr(request, Job),
    case lists:keyfind("flavor", 2, RequestedResources) of
        false ->
            {"", ""};
        Resource ->
            Value = find_value_property(Resource),
            case wm_conf:select(node, {name, Value}) of
                {ok, Node} ->
                    {wm_entity:get_attr(id, Node), wm_entity:get_attr(remote_id, Node)};
                _ ->
                    {"", ""}
            end
    end.

-spec find_value_property(#resource{}) -> string().
find_value_property(Resource) ->
    Properties = wm_entity:get_attr(properties, Resource),
    case lists:keyfind(value, 1, Properties) of
        false ->
            "";
        Property ->
            element(2, Property)
    end.
