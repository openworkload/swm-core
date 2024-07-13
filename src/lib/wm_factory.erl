-module(wm_factory).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([new/3, send_confirm/4, send_event_locally/3, notify_initiated/2, subscribe/3, is_running/2]).

-include("wm_entity.hrl").
-include("wm_log.hrl").

-record(mstate,
        {module :: atom(),
         root :: string(),
         spool :: string(),
         regname :: atom(),
         done_event :: atom(),
         activate_passive = true :: boolean(),
         subscribers = maps:new() :: map(),
         sups = maps:new() :: map(),
         mods = maps:new() :: map(),
         reqs = maps:new() :: map(),   % requests came before module initalized
         status = maps:new() :: map(), % modules with finished init()
         nodes = maps:new() :: map()}).   % nodes per distributed task

-define(REPEAT_CALL_INTERVAL, 3000).
-define(NODES_REQUEST_TIMEOUT, 10000).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    RegName =
        case lists:keysearch(regname, 1, Args) of
            false ->
                ?MODULE;
            {value, {regname, X}} ->
                X
        end,
    gen_server:start_link({local, RegName}, ?MODULE, Args, []).

-spec is_running(atom(), integer()) -> true | false.
is_running(Type, ModuleTaskId) ->
    wm_utils:protected_call(get_factory_name(Type), {is_running, ModuleTaskId}, timeout).

-spec new(atom(), [term()], [atom()]) -> {ok, integer()}.
new(Type, ExtraData, Nodes) ->
    Msg = {new, ExtraData, Nodes},
    wm_utils:protected_call(get_factory_name(Type), Msg, timeout).

%% @doc send locally waiting until the module receives it
-spec send_confirm(atom(), integer(), term(), [atom()]) -> term().
send_confirm(Type, ModuleTaskId, Msg, Nodes) ->
    Request = {send_confirm, ModuleTaskId, Msg, Nodes},
    wm_utils:cast(get_factory_name(Type), Request).

-spec send_event_locally(term(), atom(), integer()) -> ok.
send_event_locally(Msg, Type, ModuleTaskId) ->
    Factory = get_factory_name(Type),
    ?LOG_DEBUG("Send locally: ~p, ~p, ~p", [Msg, ModuleTaskId, Factory]),
    wm_utils:cast(Factory, {send_event_locally, Msg, ModuleTaskId}).

-spec notify_initiated(atom(), integer()) -> ok.
notify_initiated(Type, ModuleTaskId) ->
    Factory = get_factory_name(Type),
    ?LOG_DEBUG("Notified: init(...) has finished from ~p, ~p", [ModuleTaskId, Factory]),
    wm_utils:cast(Factory, {initiated, ModuleTaskId}).

-spec subscribe(atom(), integer(), atom()) -> ok.
subscribe(Type, ModuleTaskId, EventType) ->
    Factory = get_factory_name(Type),
    ?LOG_DEBUG("Subscribe ~p (factory: ~p) to ~p", [ModuleTaskId, Factory, EventType]),
    wm_utils:cast(Factory, {subscribe, ModuleTaskId, EventType}).

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
init(Args) ->
    process_flag(trap_exit, true),
    MState1 = parse_args(Args, #mstate{}),
    MState2 = subscribe(MState1),
    ?LOG_INFO("Factory to produce ~p has been started", [MState2#mstate.module]),
    ?LOG_DEBUG("Factory initial MState: ~10000p", [MState2]),
    {ok, MState2}.

handle_call({is_running, ModuleTaskId}, _, MState) ->
    Result =
        case maps:get(ModuleTaskId, MState#mstate.sups, not_found) of
            not_found ->
                false;
            _ ->
                true
        end,
    {reply, Result, MState};
handle_call({new, ExtraData, Nodes}, _, MState) ->
    ?LOG_DEBUG("Recieved call to create new module"),
    {ModuleTaskId, MState2} = start_module(not_exists, ExtraData, Nodes, MState),
    send_event_to_module(ModuleTaskId, activate, MState2),
    {reply, {ok, ModuleTaskId}, MState2}.

handle_cast({get_task_nodes, ModuleTaskId, RequestorAddr}, MState) ->
    ?LOG_DEBUG("Requested nodes for distributed task ~p", [ModuleTaskId]),
    Nodes = get_nodes(ModuleTaskId, MState),
    wm_api:cast_self({task_nodes, ModuleTaskId, Nodes}, [RequestorAddr]),
    {noreply, MState};
handle_cast({task_nodes, ModuleTaskId, []}, MState) ->
    ?LOG_DEBUG("No nodes for the task ~p have been found", [ModuleTaskId]),
    {noreply, MState};
handle_cast({task_nodes, ModuleTaskId, Nodes}, MState) ->
    ?LOG_DEBUG("Nodes for the task ~p have been found: ~p", [ModuleTaskId, Nodes]),
    {ModuleTaskId, MState2} = start_module(ModuleTaskId, [], Nodes, MState),
    {noreply, MState2};
handle_cast({send_confirm, ModuleTaskId, Msg, Nodes}, MState) ->
    Result = do_send_confirm(ModuleTaskId, Msg, Nodes),
    ?LOG_DEBUG("Send-confirm result: ~p (task: ~p, nodes = ~p)", [Result, ModuleTaskId, Nodes]),
    {noreply, MState};
handle_cast({subscribe, ModuleTaskId, EventType}, MState) ->
    wm_event:subscribe_async(EventType, node(), MState#mstate.regname),
    SsMap =
        case maps:is_key(ModuleTaskId, MState#mstate.subscribers) of
            true ->
                Set1 = maps:get(ModuleTaskId, MState#mstate.subscribers),
                Set2 = sets:add_element(EventType, Set1),
                maps:update(ModuleTaskId, Set2, MState#mstate.subscribers);
            false ->
                maps:put(ModuleTaskId, sets:new(), MState#mstate.subscribers)
        end,
    {noreply, MState#mstate{subscribers = SsMap}};
handle_cast({event, EventType, EventData}, MState) ->
    ?LOG_DEBUG("Event ~p received: ~p", [EventType, EventData]),
    {noreply, handle_event(EventType, EventData, MState)};
handle_cast({send_event, From, ModuleTaskId, Msg}, MState) ->
    ?LOG_DEBUG("Received send event cast, task=~p, msg=~P", [ModuleTaskId, Msg, 10]),
    handle_send_event(From, ModuleTaskId, Msg, MState);
handle_cast({check_event_handling, From, ModuleTaskId, Msg}, #mstate{reqs = ReqMap} = MState) ->
    ?LOG_DEBUG("Received check_event_handling cast from ~p, task=~p, msg=~P", [From, ModuleTaskId, Msg, 5]),
    ReqList = maps:get(ModuleTaskId, ReqMap, []),
    case lists:any(fun(X) -> X =:= ModuleTaskId end, ReqList) of
        true ->
            handle_send_event(From, ModuleTaskId, Msg, MState);
        _ ->
            ok
    end,
    {noreply, MState};
handle_cast({send_event_locally, Msg, ModuleTaskId}, MState) ->
    ?LOG_DEBUG("Received send_event_locally cast, task=~p, msg=~P", [ModuleTaskId, Msg, 5]),
    MState2 = send_event_to_module(ModuleTaskId, Msg, MState),
    {noreply, MState2};
handle_cast({initiated, ModuleTaskId}, MState) ->
    Pid = maps:get(ModuleTaskId, MState#mstate.mods),
    MState2 = set_ready(ModuleTaskId, MState),
    case MState2#mstate.activate_passive of
        true ->
            apply(MState#mstate.module, activate, [Pid]);
        _ ->
            ok
    end,
    MState3 = release_requested(ModuleTaskId, MState2),
    {noreply, MState3};
handle_cast(Msg, MState) ->
    ?LOG_WARN("Unknown message received: ~p", [Msg]),
    {noreply, MState}.

handle_info({send_event, From, ModuleTaskId, Msg}, MState) ->
    ?LOG_DEBUG("Received send event info from ~p, task=~p, msg=~P", [From, ModuleTaskId, Msg, 10]),
    handle_send_event(From, ModuleTaskId, Msg, MState);
handle_info(Info, MState) ->
    ?LOG_WARN("Unknown info message received: ~p", [Info]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{module, Module} | T], MState) ->
    parse_args(T, MState#mstate{module = Module});
parse_args([{regname, Name} | T], MState) ->
    parse_args(T, MState#mstate{regname = Name});
parse_args([{activate_passive, Activate} | T], MState) ->
    parse_args(T, MState#mstate{activate_passive = Activate});
parse_args([{root, Root} | T], MState) ->
    parse_args(T, MState#mstate{root = Root});
parse_args([{spool, Spool} | T], MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec subscribe(#mstate{}) -> #mstate{}.
subscribe(MState) ->
    DoneEvent = list_to_atom(atom_to_list(MState#mstate.module) ++ "_done"),
    wm_event:subscribe(DoneEvent, node(), MState#mstate.regname),
    MState#mstate{done_event = DoneEvent}.

-spec handle_event(atom(), {integer(), term()}, #mstate{}) -> #mstate{}.
handle_event(Event, {ModuleTaskId, Extra}, MState) when Event == MState#mstate.done_event ->
    ?LOG_DEBUG("Task ~p has finished (Extra=~p)", [ModuleTaskId, Extra]),
    Me = node(),
    case Extra of
        {node, Me} ->
            SelfNodeId = wm_self:get_node_id(),
            Nodes1 = get_nodes(ModuleTaskId, MState),
            Nodes2 = lists:filter(fun(Node) -> wm_entity:get(id, Node) =/= SelfNodeId end, Nodes1),
            wm_event:announce_nodes(Nodes2, Event, {ModuleTaskId, Extra});
        _ ->
            ok
    end,
    terminate_task(ModuleTaskId, MState);
handle_event(Event, {ModuleTaskId, EventData}, MState) ->
    ?LOG_DEBUG("Event received for task ~p: ~p", [ModuleTaskId, Event]),
    case maps:get(ModuleTaskId, MState#mstate.subscribers, []) of
        SubscribedEvents ->
            case sets:is_element(ModuleTaskId, SubscribedEvents) of
                true ->
                    send_event_to_module(ModuleTaskId, {Event, EventData}, MState);
                fasle ->
                    MState
            end
    end.

-spec calc_id([node_address()]) -> integer().
calc_id(Nodes) ->
    erlang:phash2({lists:sort(Nodes), wm_utils:timestamp(microsecond)}).

-spec start_module(atom(), term(), [#node{}], #mstate{}) -> {integer(), #mstate{}}.
start_module(not_exists, ExtraData, Nodes, MState) ->
    ModuleTaskId = calc_id(Nodes),
    AddrList = [wm_utils:get_address(X) || X <- Nodes],
    start_module(ModuleTaskId, ExtraData, AddrList, MState);
start_module(ModuleTaskId, ExtraData, Nodes, MState) ->
    ?LOG_DEBUG("Start module ~p for task ~p (~p)", [?MODULE, ModuleTaskId, Nodes]),
    Module = MState#mstate.module,
    AddrList = [wm_utils:get_address(X) || X <- Nodes],
    ?LOG_DEBUG("Start ~p for ~p nodes, ~p", [Module, length(AddrList), ModuleTaskId]),
    Args =
        [{extra, ExtraData},
         {nodes, AddrList},
         {task_id, ModuleTaskId},
         {root, MState#mstate.root},
         {spool, MState#mstate.spool}],
    case wm_sup:start_link({[Module], Args}) of
        {ok, SupPid} ->
            ModPid = wm_sup:get_child_pid(SupPid),
            ?LOG_DEBUG("Supervisor ~p for ~p (~p) started", [SupPid, Module, ModPid]),
            Sups = maps:put(ModuleTaskId, SupPid, MState#mstate.sups),
            Mods = maps:put(ModuleTaskId, ModPid, MState#mstate.mods),
            SMap = maps:put(ModuleTaskId, not_ready, MState#mstate.status),
            NMap = maps:put(ModuleTaskId, AddrList, MState#mstate.nodes),
            {ModuleTaskId,
             MState#mstate{sups = Sups,
                           mods = Mods,
                           status = SMap,
                           nodes = NMap}};
        {error, {shutdown, Error}} ->
            ?LOG_ERROR("Cannot start ~p (id=~p, nodes=~p): ~p", [MState#mstate.module, ModuleTaskId, AddrList, Error]),
            {ModuleTaskId, MState}
    end.

-spec do_send_confirm(integer(), term(), [node_address()]) -> ok.
do_send_confirm(ModuleTaskId, Msg, Nodes) ->
    ?LOG_DEBUG("Send ~P to ~p (~p)", [Msg, 10, Nodes, ModuleTaskId]),
    MyAddr = wm_conf:get_my_relative_address(hd(Nodes)),
    NewMsg = {send_event, MyAddr, ModuleTaskId, Msg},
    wm_api:cast_self_confirm(NewMsg, Nodes).

-spec get_status(integer(), #mstate{}) -> ready | not_ready.
get_status(ModuleTaskId, MState) ->
    maps:get(ModuleTaskId, MState#mstate.status, not_ready).

-spec get_nodes(integer(), #mstate{}) -> [#node{}].
get_nodes(ModuleTaskId, MState) ->
    maps:get(ModuleTaskId, MState#mstate.nodes, []).

-spec set_ready(integer(), #mstate{}) -> #mstate{}.
set_ready(ModuleTaskId, MState) ->
    Status = maps:put(ModuleTaskId, ready, MState#mstate.status),
    MState#mstate{status = Status}.

-spec queue_request(integer(), term(), #mstate{}) -> #mstate{}.
queue_request(ModuleTaskId, Msg, MState) ->
    ?LOG_DEBUG("Queue request ~P (~p)", [Msg, 10, ModuleTaskId]),
    ReqsList = [Msg | maps:get(ModuleTaskId, MState#mstate.reqs, [])],
    ReqsMap = maps:put(ModuleTaskId, ReqsList, MState#mstate.reqs),
    MState#mstate{reqs = ReqsMap}.

-spec release_requested(integer(), #mstate{}) -> #mstate{}.
release_requested(ModuleTaskId, MState) ->
    F = fun(Msg) -> send_event_to_module(ModuleTaskId, Msg, MState) end,
    [F(X) || X <- maps:get(ModuleTaskId, MState#mstate.reqs, [])],
    Reqs = maps:put(ModuleTaskId, [], MState#mstate.reqs),
    MState#mstate{reqs = Reqs}.

-spec send_event_to_module(integer(), term(), #mstate{}) -> #mstate{}.
send_event_to_module(ModuleTaskId, Msg, MState) ->
    case maps:get(ModuleTaskId, MState#mstate.mods, not_found) of
        not_found ->
            ?LOG_DEBUG("Cannot send event, no such task id: ~p", [ModuleTaskId]);
        Pid ->
            ?LOG_DEBUG("Send event to ~p: ~10000p (~p, ~p)", [MState#mstate.module, Msg, Pid, ModuleTaskId]),
            gen_statem:cast(Pid, Msg)
    end,
    MState.

-spec request_nodes_async(integer(), node_address()) -> ok.
request_nodes_async(ModuleTaskId, From) ->
    ?LOG_DEBUG("Request nodes for task ~p from ~p", [ModuleTaskId, From]),
    MyAddr = wm_conf:get_my_relative_address(From),
    ok = wm_api:cast_self({get_task_nodes, ModuleTaskId, MyAddr}, [From]).

-spec terminate_task(integer(), #mstate{}) -> #mstate{}.
terminate_task(ModuleTaskId, MState) ->
    case maps:get(ModuleTaskId, MState#mstate.sups, not_found) of
        not_found ->
            MState;
        Sup ->
            ?LOG_DEBUG("Shutdown module ~p (~p)", [MState#mstate.module, ModuleTaskId]),
            exit(Sup, shutdown),
            Sbrs =
                case maps:is_key(ModuleTaskId, MState#mstate.subscribers) of
                    true ->
                        maps:remove(ModuleTaskId, MState#mstate.subscribers);
                    false ->
                        MState#mstate.subscribers
                end,
            Sups = maps:remove(ModuleTaskId, MState#mstate.sups),
            Mods = maps:remove(ModuleTaskId, MState#mstate.mods),
            Reqs = maps:remove(ModuleTaskId, MState#mstate.reqs),
            SMap = maps:remove(ModuleTaskId, MState#mstate.status),
            NMap = maps:remove(ModuleTaskId, MState#mstate.nodes),
            MState#mstate{sups = Sups,
                          mods = Mods,
                          reqs = Reqs,
                          status = SMap,
                          nodes = NMap,
                          subscribers = Sbrs}
    end.

-spec get_factory_name(atom()) -> atom().
get_factory_name(Type) ->
    NameStr = atom_to_list(?MODULE) ++ "_" ++ atom_to_list(Type),
    list_to_existing_atom(NameStr).

-spec handle_send_event(node_address(), integer(), term(), #mstate{}) -> {noreply, #mstate{}}.
handle_send_event(From, ModuleTaskId, Msg, MState) ->
    ?LOG_DEBUG("Handle send event: f=~p id=~p", [From, ModuleTaskId]),
    case get_status(ModuleTaskId, MState) of
        ready ->
            {noreply, send_event_to_module(ModuleTaskId, Msg, MState)};
        not_ready ->
            Check = {check_event_handling, From, ModuleTaskId, Msg},
            wm_utils:wake_up_after(?REPEAT_CALL_INTERVAL, Check),
            request_nodes_async(ModuleTaskId, From),
            {noreply, queue_request(ModuleTaskId, Msg, MState)}
    end.
