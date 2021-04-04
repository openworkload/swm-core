-module(wm_parent).

-export([find_my_parents/5, get_current/1]).

-include("../../lib/wm_log.hrl").

%% @doc Return current parent address if any
-spec get_current(list()) -> {string(), integer()} | not_found.
get_current(PStack) ->
    case PStack of
        [] ->
            not_found;
        _ ->
            hd(PStack)
    end.

%% @doc Search for my parent and return a new parents list
-spec find_my_parents(string(), string(), pos_integer(), string(), string()) -> list().
find_my_parents(ParentName, ParentHost, ParentPort, NodeName, Host) ->
    case is_grid_management_node(NodeName) of
        true -> % grid management node never has any parents
            ?LOG_DEBUG("No parents are set (I am a grid management "
                       "node)"),
            [];
        false ->
            L0 = [],
            L1 = add_parent_from_my_sname(NodeName, L0),
            L2 = add_parent_from_parent_sname(ParentName, NodeName, L1),
            add_parent_from_boot_args(ParentHost, ParentPort, L2)
    end.

%% @doc Search parent in my node entity defined by $SWM_SNAME
add_parent_from_my_sname(NodeShortName, List) ->
    ?LOG_DEBUG("Get parent from sname: ~p (~p)", [NodeShortName, List]),
    case wm_conf:select(node, {name, NodeShortName}) of
        {ok, Me} ->
            case wm_entity:get_attr(parent, Me) of
                undefined ->
                    List;
                ParentName ->
                    case wm_conf:select(node, {name, ParentName}) of
                        {ok, Parent} ->
                            [wm_conf:get_relative_address(Parent, Me) | List];
                        _ ->
                            List
                    end
            end;
        _ ->
            List
    end.

%% @doc Search parent entity defined by $SWM_PARENT_SNAME
add_parent_from_parent_sname(ParentShortName, NodeName, List) ->
    ?LOG_DEBUG("Get parent from parent sname: ~p ~p "
               "(~p)",
               [ParentShortName, NodeName, List]),
    case wm_conf:select(node, {name, ParentShortName}) of
        {ok, Parent} ->
            case wm_conf:select_node(NodeName) of
                {ok, Me} ->
                    [wm_conf:get_relative_address(Parent, Me) | List];
                _ ->
                    List
            end;
        _ ->
            List
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
            wm_entity:get_attr(subdivision, Node) == grid;
        _ ->
            false
    end.
