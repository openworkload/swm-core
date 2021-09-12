-module(wm_event).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([announce/1, announce/2, announce_neighbours/2, announce_nodes/3, subscribe/3, subscribe_async/3, unsubscribe/3,
         unsubscribe_async/3]).

-include("wm_entity.hrl").
-include("wm_log.hrl").

-record(mstate, {cleaned}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc send event without data to local subscribers
-spec announce(atom()) -> ok.
announce(EventType) ->
    gen_server:cast(?MODULE, {cast_subscribers, EventType, []}).

%% @doc send event with data to local subscribers
-spec announce(atom(), term()) -> ok.
announce(EventType, EventData) ->
    gen_server:cast(?MODULE, {cast_subscribers, EventType, EventData}).

%% @doc send event with data to all neighbours
-spec announce_neighbours(atom(), term()) -> ok.
announce_neighbours(EventType, EventData) ->
    gen_server:cast(?MODULE, {cast_neighbours, EventType, EventData}).

%% @doc send event with data to specific nodes
-spec announce_nodes(list(), atom(), term()) -> ok.
announce_nodes(Nodes, EventType, EventData) ->
    gen_server:cast(?MODULE, {cast_nodes, Nodes, EventType, EventData}).

-spec subscribe(atom(), atom(), atom()) -> ok.
subscribe(EventType, Node, Module) ->
    gen_server:call(?MODULE, {subscribe, EventType, Node, Module}).

-spec subscribe_async(atom(), atom(), atom()) -> ok.
subscribe_async(EventType, Node, Module) ->
    gen_server:cast(?MODULE, {subscribe, EventType, Node, Module}).

-spec unsubscribe(atom(), atom(), atom()) -> ok.
unsubscribe(EventType, Node, Module) ->
    do_unsubscribe(EventType, Node, Module).

-spec unsubscribe_async(atom(), atom(), atom()) -> ok.
unsubscribe_async(EventType, Node, Module) ->
    gen_server:cast(?MODULE, {unsubscribe, EventType, Node, Module}).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init(term()) -> {ok, term()} | {ok, term(), hibernate | infinity | non_neg_integer()} | {stop, term()} | ignore.
-spec handle_call(term(), term(), term()) ->
                     {reply, term(), term()} |
                     {reply, term(), term(), hibernate | infinity | non_neg_integer()} |
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()} |
                     {stop, term(), term(), term()}.
-spec handle_cast(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec handle_info(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec terminate(term(), term()) -> ok.
-spec code_change(term(), term(), term()) -> {ok, term()}.
init(_Args) ->
    ?LOG_DEBUG("Load events service"),
    process_flag(trap_exit, true),
    MState = #mstate{cleaned = false},
    {ok, MState}.

handle_call({subscribe, EventType, Node, Module}, _From, MState) ->
    MState2 =
        case MState#mstate.cleaned of
            false ->
                remove_all_subscribers(),
                MState#mstate{cleaned = true};
            _ ->
                MState
        end,
    {reply, do_subscribe(EventType, Node, Module), MState2};
handle_call(_Msg, _From, MState) ->
    {reply, not_handled, MState}.

handle_cast({unsubscribe, EventType, Node, Module}, MState) ->
    do_unsubscribe(EventType, Node, Module),
    {noreply, MState};
handle_cast({subscribe, EventType, Node, Module}, MState) ->
    MState2 =
        case MState#mstate.cleaned of
            false ->
                remove_all_subscribers(),
                MState#mstate{cleaned = true};
            _ ->
                MState
        end,
    do_subscribe(EventType, Node, Module),
    {noreply, MState2};
handle_cast({cast_subscribers, EventType, EventData}, MState) ->
    do_cast_subscribers(EventType, EventData),
    {noreply, MState};
handle_cast({cast_neighbours, EventType, EventData}, MState) ->
    do_cast_neighbours(EventType, EventData),
    {noreply, MState};
handle_cast({cast_nodes, Nodes, EventType, EventData}, MState) ->
    do_cast_nodes(Nodes, EventType, EventData),
    {noreply, MState};
handle_cast({forward_event_locally, Module, Msg}, MState) ->
    forward_event(Module, Msg),
    {noreply, MState}.

handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

do_cast_neighbours(EventType, EventData) ->
    FullNodeNames = wm_topology:get_neighbour_addresses(unsorted),
    do_cast_nodes(FullNodeNames, EventType, EventData).

do_cast_nodes(Nodes, EventType, EventData) ->
    ?LOG_DEBUG("Cast nodes ~d with event ~p", [length(Nodes), EventType]),
    Args = {EventType, EventData},
    F = fun(Addr) -> wm_rpc:cast(?MODULE, cast_subscribers, Args, Addr) end,
    [F(Node) || Node <- Nodes].

do_cast_subscribers(EventType, EventData) ->
    ?LOG_DEBUG("Cast subscribers on event: ~p ~p", [EventType, EventData]),
    case wm_db:table_exists(subscriber) of
        true ->
            case wm_db:get_many(subscriber, event, [EventType]) of
                [] ->
                    ?LOG_DEBUG("No subscribers found for event: ~p", [EventType]);
                Subscribers1 ->
                    F1 = fun(S) ->
                            Ref = wm_entity:get_attr(ref, S),
                            ?LOG_DEBUG("Cast ~p with event: ~p, data=~W", [Ref, EventType, EventData, 10]),
                            forward_event(Ref, {event, EventType, EventData})
                         end,
                    lists:map(F1, Subscribers1)
            end,
            case wm_db:get_many(subscriber, event, [any_event]) of
                [] ->
                    ?LOG_DEBUG("No subscribers found for any event");
                Subscribers2 ->
                    F2 = fun(S) ->
                            Ref = wm_entity:get_attr(ref, S),
                            ?LOG_DEBUG("Cast ~p with event '~p', data=~W", [Ref, EventType, EventData, 10]),
                            forward_event(Ref, {event, EventType, EventData})
                         end,
                    lists:map(F2, Subscribers2)
            end;
        false ->
            ?LOG_ERROR("Subscriber table has not been found in DB")
    end.

do_subscribe(EventType, Node, Module) ->
    ?LOG_DEBUG("Subscribe ~p on ~p:~p", [EventType, Node, Module]),
    case wm_db:ensure_running() of
        ok ->
            wm_db:ensure_table_exists(subscriber, [], local_bag),
            F = fun(A) -> wm_entity:get_attr(event, A) =:= EventType end,
            Subscribers = wm_db:get_one(subscriber, ref, {Module, Node}),
            case lists:any(F, Subscribers) of
                true ->
                    ?LOG_DEBUG("Service ~p:~p has already been subscribed "
                               "on event: ~p",
                               [Node, Module, EventType]);
                false ->
                    S1 = wm_entity:new(<<"subscriber">>),
                    S2 = wm_entity:set_attr({ref, {Module, Node}}, S1),
                    S3 = wm_entity:set_attr({event, EventType}, S2),
                    ?LOG_DEBUG("Update ~p", S3),
                    wm_db:update([S3])
            end;
        {error, Reason} ->
            ?LOG_ERROR("~p", [Reason])
    end.

do_unsubscribe(EventType, Node, Module) ->
    ?LOG_DEBUG("Unsubscribe ~p on ~p:~p", [EventType, Node, Module]),
    case wm_db:ensure_running() of
        ok ->
            Subscribers = wm_db:get_one(subscriber, ref, {Module, Node}),
            F1 = fun(A) -> wm_entity:get_attr(event, A) =:= EventType end,
            case lists:filter(F1, Subscribers) of
                [] ->
                    ?LOG_DEBUG("Service ~p:~p is not subscribed on event: ~p", [Node, Module, EventType]);
                Records ->
                    F2 = fun(Record) -> ok = wm_db:delete(Record) end,
                    [F2(X) || X <- Records]
            end;
        {error, Reason} ->
            ?LOG_ERROR("~p", [Reason])
    end.

remove_all_subscribers() ->
    ?LOG_DEBUG("Clear subscribers"),
    AllSubscribers = wm_db:get_all(subscriber),
    [wm_db:delete(X) || X <- AllSubscribers].

forward_event({Module, Node}, Msg) when Node =:= node() ->
    forward_event(Module, Msg);
forward_event({Module, Node}, Msg) ->
    wm_api:cast_self({forward_event_locally, Module, Msg}, [Node]);
forward_event(Module, Msg) ->
    ok = wm_utils:cast(Module, Msg).
