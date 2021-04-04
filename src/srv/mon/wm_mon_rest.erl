%% @doc Monitoring REST API handler.
-module(wm_mon_rest).

-export([init/2, content_types_provided/2]).
-export([json_handler/2]).

-include("../../lib/wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% Callbacks
%% ============================================================================

init(Req, _Opts) ->
    ?LOG_INFO("Start monitoring REST API handler: ~p", [Req]),
    {cowboy_rest, Req, #mstate{}}.

content_types_provided(Req, MState) ->
    {[{<<"application/json">>, json_handler}], Req, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

% curl -i -H "Accept: application/json" "http://localhost:8008/mon?\
%  metric=msg_route&begintime=1460300086618999&endtime=1470500000000000&limit=8"
json_handler(Req, MState) ->
    Method = cowboy_req:method(Req),
    Body = metrics_to_json(Method, Req),
    {Body, Req, MState}.

metrics_to_json(<<"GET">>, Req) ->
    Map = #{metric := NameBin,
            limit := Limit,
            begintime := BeginTime,
            endtime := EndTime} =
              cowboy_req:match_qs([{metric, nonempty}, {limit, int, <<"10">>}, {begintime, int}, {endtime, int}], Req),
    ?LOG_DEBUG("Received HTTP parameters: ~p", [Map]),
    Name = binary_to_existing_atom(NameBin, utf8),
    Xs = wm_mon:get_values(Name, {BeginTime, EndTime, Limit}),
    F0 = fun(Timestamp, {event, {Node1, Node2}}, Json) ->
            S = "{\"t\":\"~p\", \"s\":\"~p\", \"d\":\"~p\"}",
            Json ++ io_lib:format(S, [Timestamp, Node1, Node2])
         end,
    F1 = fun({Timestamp, Values}, Json) -> Json ++ [F0(Timestamp, M, []) || M <- Values] end,
    Ms = lists:foldl(F1, [], Xs),
    ["{\"metrics\": ["] ++ string:join(Ms, ", ") ++ ["]}"].
