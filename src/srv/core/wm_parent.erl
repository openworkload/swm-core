-module(wm_parent).

-export([find_my_parents/3, get_current/1]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").

%% @doc Return current parent address if any
-spec get_current(list()) -> node_address() | not_found.
get_current(PStack) ->
    case PStack of
        [] ->
            not_found;
        _ ->
            hd(PStack)
    end.

%% @doc Search for my parent and return a new parents list
-spec find_my_parents(string(), pos_integer(), string()) -> list().
find_my_parents(ParentHost, ParentPort, NodeName) ->
    case is_grid_management_node(NodeName) of
        true ->
            ?LOG_DEBUG("No parents are set (I am a grid management node)"),
            [];
        false ->
            add_parent_from_boot_args(ParentHost, ParentPort, [])
    end.

%% @doc Search and add parent to pstack from the application arguments
add_parent_from_boot_args(Host, Port, List) when is_list(Host) ->
    ?LOG_DEBUG("Get parent from boot args: ~p:~p (~p)", [Host, Port, List]),
    [{Host, Port} | List];
add_parent_from_boot_args(_, _, List) ->
    List.

%% @doc Returns true if the short name is owned by grid management node
is_grid_management_node(ShortName) ->
    case wm_conf:select(node, {name, ShortName}) of
        {ok, Node} ->
            wm_entity:get(subdivision, Node) == grid;
        _ ->
            false
    end.
