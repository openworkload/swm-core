%% @doc Grid service REST API handler.
-module(wm_grid_rest).

-export([init/2, content_types_provided/2]).
-export([json_handler/2]).

-include("../../lib/wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% Callbacks
%% ============================================================================

init(Req, _Opts) ->
    ?LOG_INFO("Load grid manager REST API handler: ~p", [Req]),
    {cowboy_rest, Req, #mstate{}}.

content_types_provided(Req, MState) ->
    {[{<<"application/json">>, json_handler}], Req, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

% curl -i -H "Accept: application/json" "http://localhost:8008/grid?limit=8"
json_handler(Req, MState) ->
    Method = cowboy_req:method(Req),
    Body = grid_to_json(Method, Req),
    {Body, Req, MState}.

grid_to_json(<<"GET">>, Req) ->
    Map = #{limit := Limit} = cowboy_req:match_qs([{limit, int, 100}], Req),
    ?LOG_DEBUG("Received HTTP parameters: ~p", [Map]),
    Xs = wm_grid:get_nodes(Limit),
    F1 = fun(Node, FullJson) ->
            SubDiv = wm_entity:get_attr(subdivision, Node),
            SubDivId = wm_entity:get_attr(subdivision_id, Node),
            Parent = wm_entity:get_attr(parent, Node),
            Name = atom_to_list(wm_utils:node_to_fullname(Node)),
            NodeJson =
                "{\"name\":\""
                ++ Name
                ++ "\","
                ++ " \"subname\":\""
                ++ atom_to_list(SubDiv)
                ++ "\","
                ++ " \"subid\":\""
                ++ io_lib:format("~p", [SubDivId])
                ++ "\","
                ++ " \"parent\":\""
                ++ Parent
                ++ "\""
                ++ "}",
            [NodeJson | FullJson]
         end,
    Ms = lists:foldl(F1, [], Xs),
    ["{\"nodes\": ["] ++ string:join(Ms, ", ") ++ ["]}"].
