-module(wm_pinger).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([add/1, del/1, send_if_pinged/3, ping_sync/1, start_route/4]).

-include("wm_log.hrl").

-define(DEFAULT_PING_PERIOD, 15).
-define(DEFAULT_PINGER_PERIOD, 15).
-define(MICROSECONDS_IN_SECOND, 1000).

-record(mstate, {nodes = #{}, answers = #{}}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%%doc Add new node address to monitoring
-spec add({string(), number()}) -> ok.
add(Address) ->
    Ms = wm_conf:g(node_ping_period, {?DEFAULT_PING_PERIOD, integer}),
    gen_server:cast(?MODULE, {add, Address, Ms}).

%%doc Remove new node address from monitoring
-spec del({string(), number()}) -> ok.
del(Address) ->
    gen_server:cast(?MODULE, {del, Address}).

send_if_pinged(Address, CallbackModule, Msg) ->
    gen_server:cast(?MODULE, {send_if_pinged, Address, CallbackModule, Msg}).

ping_sync(Address) ->
    do_ping(Address).

%% @doc Initialize route determination
start_route(From, To, RouteID, RequestorPid) ->
    gen_server:cast(?MODULE, {start_route, From, To, RouteID, RequestorPid}).

%% ============================================================================
%% Callbacks
%% ============================================================================

init(_) ->
    ?LOG_DEBUG("Load nodes pinger"),
    process_flag(trap_exit, true),
    MState = #mstate{},
    NextS = wm_conf:g(pinger_period, {?DEFAULT_PINGER_PERIOD, integer}),
    Next = NextS * ?MICROSECONDS_IN_SECOND,
    wm_utils:wake_up_after(Next, wakeup),
    {ok, MState}.

handle_call(Msg, From, MState) ->
    ?LOG_ERROR("Received unknown call from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast({start_route, StartNode, EndNode, RouteID, RequestorPid}, MState) ->
    ?LOG_DEBUG("Route creation is started (from=~p, "
               "to=~p, id=~p, pid=~p)",
               [StartNode, EndNode, RouteID, RequestorPid]),
    StartAddr = wm_utils:get_address(StartNode),
    EndAddr = wm_utils:get_address(EndNode),
    Requestor = {wm_conf:get_my_address(), RequestorPid},
    Msg = {route, StartAddr, EndAddr, RouteID, Requestor, tostart, []},
    wm_api:cast_self(Msg, [StartAddr]),
    {noreply, MState};
handle_cast({route, StartAddr, EndAddr, RouteID, Requestor, D, Route}, MState) ->
    {RequestorAddr, RequestorPid} = Requestor,
    case wm_conf:get_my_address() of
        RequestorAddr -> % route message is returned to requestor node
            Msg = {route, StartAddr, EndAddr, RouteID, Requestor, done, Route},
            RequestorPid ! Msg;
        StartAddr -> % route message is received on route start node
            case D of
                tostart -> % send forward to route end node
                    Msg = {route, StartAddr, EndAddr, RouteID, Requestor, toend, Route},
                    wm_api:cast_self(Msg, [EndAddr]);
                fromend -> % the raundtrip is finished, send the route to the requestor
                    Msg = {route, StartAddr, EndAddr, RouteID, Requestor, toreq, Route},
                    wm_api:cast_self(Msg, [RequestorAddr])
            end;
        EndAddr -> % send back to route start node
            Msg = {route, StartAddr, EndAddr, RouteID, Requestor, fromend, Route},
            wm_api:cast_self(Msg, [StartAddr])
    end,
    {noreply, MState};
handle_cast({send_if_pinged, Address, CallbackModule, Msg}, MState) ->
    ?LOG_DEBUG("Send-if-pinged: ~p ~p ~p", [Address, CallbackModule, Msg]),
    case do_ping(Address) of
        {pong, _} ->
            gen_server:cast(CallbackModule, Msg);
        _ ->
            ok
    end,
    {noreply, MState};
handle_cast({add, Address, Interval}, MState) ->
    ?LOG_DEBUG("Add new address: ~p (period=~p)", [Address, Interval]),
    Now = wm_utils:timestamp(second),
    NewMap = maps:put(Address, {Now, Interval}, MState#mstate.nodes),
    {noreply, MState#mstate{nodes = NewMap}};
handle_cast({del, Address}, MState) ->
    ?LOG_DEBUG("Remove address: ~p", [Address]),
    NewMap = maps:remove(Address, MState#mstate.nodes),
    {noreply, MState#mstate{nodes = NewMap}};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Received unknown cast message: ~p", [Msg]),
    {noreply, MState}.

handle_info(wakeup, MState) ->
    {noreply, do_wakeup(MState)};
handle_info({RpcTag, {error, timeout}}, MState) ->
    ?LOG_DEBUG("Ping failed by timeout: ~p", [RpcTag]),
    {noreply, MState};
handle_info(Info, MState) ->
    ?LOG_DEBUG("Received unknown info message: ~p", [Info]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

do_wakeup(MState = #mstate{nodes = Nodes}) ->
    ?LOG_DEBUG("Nodes to ping: ~p", [Nodes]),
    Size = maps:size(Nodes),
    NextS = wm_conf:g(pinger_period, {?DEFAULT_PINGER_PERIOD, integer}),
    Next = NextS * ?MICROSECONDS_IN_SECOND,
    Now1 = wm_utils:timestamp(second),
    ShouldBePinged = fun(_, {LastPing, Interval}) -> Now1 - LastPing > Interval end,
    ToPingMap = maps:filter(ShouldBePinged, Nodes),
    AnswersMap = maps:merge(MState#mstate.answers, do_ping(ToPingMap)),
    Now2 = wm_utils:timestamp(second),
    UpFun = fun(K, {_, I}, M) -> maps:put(K, {Now2, I}, M) end,
    UpdatedNodes = maps:fold(UpFun, Nodes, ToPingMap),
    wm_utils:wake_up_after(Next, wakeup),
    announce_node_states_change(MState#mstate.answers, AnswersMap),
    MState#mstate{answers = AnswersMap, nodes = UpdatedNodes}.

announce_node_states_change(Old, New) ->
    F = fun(Key, NewVal) ->
           case maps:get(Key, Old, {pang, stopped}) of
               {pong, OldState} ->
                   case NewVal of
                       {pong, OldState} -> % nothing has changed
                           ok;
                       {pong, NewState} -> % state changed
                           wm_event:announce(nodeup, {NewState, Key});
                       {pang, _} -> % ping changed
                           wm_event:announce(nodedown, {stopped, Key})
                   end;
               {pang, _} ->
                   case NewVal of
                       {pang, _} -> % nothing has changed
                           ok;
                       {pong, NewState} -> % ping changed
                           wm_event:announce(nodeup, {NewState, Key})
                   end
           end
        end,
    maps:map(F, New).

do_ping(Map) when is_map(Map) ->
    PingFun =
        fun(Address, _, Answers) ->
           ?LOG_DEBUG("Ping ~p", [Address]),
           case wm_api:call_self(ping, Address) of
               [{pong, AllocState}] ->
                   ?LOG_DEBUG("Ping OK: ~p (alloc=~p)", [Address, AllocState]),
                   maps:put(Address, {pong, AllocState}, Answers);
               Error ->
                   ?LOG_DEBUG("Ping FAILED: ~p (~p)", [Address, Error]),
                   maps:put(Address, {pang, stopped}, Answers)
           end
        end,
    maps:fold(PingFun, #{}, Map);
do_ping(Address) ->
    ?LOG_DEBUG("Ping ~p", [Address]),
    case wm_api:call_self(ping, Address) of
        [{pong, AllocState}] ->
            ?LOG_DEBUG("PING OK: ~p (alloc=~p)", [Address, AllocState]),
            {pong, AllocState};
        Error ->
            ?LOG_DEBUG("PING FAILED: ~p (~p)", [Address, Error]),
            {pang, stopped}
    end.
