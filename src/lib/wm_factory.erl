-module(wm_factory).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([new/3, send_confirm/5, send_event_locally/3, notify_initiated/2, subscribe/3]).

-include("wm_log.hrl").

-record(mstate,
        {module,
         root,
         regname,
         done_event,
         activate_passive = true,
         subscribers = maps:new(),
         sups = maps:new(),
         mods = maps:new(),
         reqs =
             maps:new(),   % requests came before module initalized
         status = maps:new(), % modules with finished init()
         nodes = maps:new()}).   % nodes per distributed task

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

-spec new(atom(), [term()], [atom()]) -> integer().
new(Type, ExtraData, Nodes) ->
    Msg = {new, ExtraData, Nodes},
    wm_utils:protected_call(get_factory_name(Type), Msg, timeout).

%% @doc send locally waiting until the module receives it
-spec send_confirm(atom(), atom(), integer(), term(), [atom()]) -> term().
send_confirm(Type, AllState, TASK_ID, Msg, Nodes) ->
    Request = {send_confirm, AllState, TASK_ID, Msg, Nodes},
    wm_utils:cast(get_factory_name(Type), Request).

-spec send_event_locally(term(), atom(), integer()) -> ok.
send_event_locally(Msg, Type, TASK_ID) ->
    Factory = get_factory_name(Type),
    ?LOG_DEBUG("Send locally: ~p, ~p, ~p", [Msg, TASK_ID, Factory]),
    wm_utils:cast(Factory, {send_event_locally, Msg, TASK_ID}).

-spec notify_initiated(atom(), integer()) -> ok.
notify_initiated(Type, TASK_ID) ->
    Factory = get_factory_name(Type),
    ?LOG_DEBUG("Notified: init(...) has finished from "
               "~p, ~p",
               [TASK_ID, Factory]),
    wm_utils:cast(Factory, {initiated, TASK_ID}).

-spec subscribe(atom(), integer(), atom()) -> ok.
subscribe(Type, TASK_ID, EventType) ->
    Factory = get_factory_name(Type),
    ?LOG_DEBUG("Subscribe ~p (factory: ~p) to ~p", [TASK_ID, Factory, EventType]),
    wm_utils:cast(Factory, {subscribe, TASK_ID, EventType}).

%% ============================================================================
%% Server callbacks
%% ============================================================================

handle_call({new, ExtraData, Nodes}, _, MState) ->
    ?LOG_DEBUG("Recieved call to create new module"),
    {TASK_ID, MState2} = start_module(not_exists, ExtraData, Nodes, MState),
    send_event_to_module(one_state, TASK_ID, activate, MState2),
    {reply, {ok, TASK_ID}, MState2}.

handle_cast({get_task_nodes, TASK_ID, RequestorAddr}, MState) ->
    ?LOG_DEBUG("Requested nodes for distributed task ~p", [TASK_ID]),
    Nodes = get_nodes(TASK_ID, MState),
    wm_api:cast_self({task_nodes, TASK_ID, Nodes}, [RequestorAddr]),
    {noreply, MState};
handle_cast({task_nodes, TASK_ID, []}, MState) ->
    ?LOG_DEBUG("No nodes for the task ~p have been found", [TASK_ID]),
    {noreply, MState};
handle_cast({task_nodes, TASK_ID, Nodes}, MState) ->
    ?LOG_DEBUG("Nodes for the task ~p have been found: ~p", [TASK_ID, Nodes]),
    {TASK_ID, MState2} = start_module(TASK_ID, [], Nodes, MState),
    {noreply, MState2};
handle_cast({send_confirm, AllState, TASK_ID, Msg, Nodes}, MState) ->
    do_send_confirm(AllState, TASK_ID, Msg, Nodes),
    {noreply, MState};
handle_cast({subscribe, TASK_ID, EventType}, MState) ->
    wm_event:subscribe_async(EventType, node(), MState#mstate.regname),
    SsMap =
        case maps:is_key(TASK_ID, MState#mstate.subscribers) of
            true ->
                Set1 = maps:get(TASK_ID, MState#mstate.subscribers),
                Set2 = sets:add_element(EventType, Set1),
                maps:update(TASK_ID, Set2, MState#mstate.subscribers);
            false ->
                maps:put(TASK_ID, sets:new(), MState#mstate.subscribers)
        end,
    {noreply, MState#mstate{subscribers = SsMap}};
handle_cast({event, EventType, EventData}, MState) ->
    ?LOG_DEBUG("Event recevied: ~p, ~p}", [EventType, EventData]),
    {noreply, handle_event(EventType, EventData, MState)};
handle_cast({send_event, AllState, From, TASK_ID, Msg}, MState) ->
    ?LOG_DEBUG("Received send event cast, task=~p, msg=~P", [TASK_ID, Msg, 10]),
    handle_send_event(AllState, From, TASK_ID, Msg, MState);
handle_cast({check_event_handling, AllState, From, TASK_ID, Msg}, #mstate{reqs = ReqMap} = MState) ->
    ReqList = maps:get(TASK_ID, ReqMap, []),
    case lists:any(fun(X) -> X =:= TASK_ID end, ReqList) of
        true ->
            handle_send_event(AllState, From, TASK_ID, Msg, MState);
        _ ->
            ok
    end,
    {noreply, MState};
handle_cast({send_event_locally, Msg, TASK_ID}, MState) ->
    MState2 = send_event_to_module(all_state, TASK_ID, Msg, MState),
    {noreply, MState2};
handle_cast({initiated, TASK_ID}, MState) ->
    Pid = maps:get(TASK_ID, MState#mstate.mods),
    MState2 = set_ready(TASK_ID, MState),
    case MState2#mstate.activate_passive of
        true ->
            apply(MState#mstate.module, activate, [Pid]);
        _ ->
            ok
    end,
    MState3 = release_requested(TASK_ID, MState2),
    {noreply, MState3};
handle_cast(_Msg, MState) ->
    {noreply, MState}.

handle_info({send_event, AllState, From, TASK_ID, Msg}, MState) ->
    handle_send_event(AllState, From, TASK_ID, Msg, MState);
handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @hidden
init(Args) ->
    process_flag(trap_exit, true),
    MState1 = parse_args(Args, #mstate{}),
    MState2 = subscribe(MState1),
    ?LOG_INFO("Factory to produce ~p has been started", [MState2#mstate.module]),
    ?LOG_DEBUG("Factory initial MState: ~p", [MState2]),
    {ok, MState2}.

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
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

subscribe(MState) ->
    DoneEvent = list_to_atom(atom_to_list(MState#mstate.module) ++ "_done"),
    wm_event:subscribe(DoneEvent, node(), MState#mstate.regname),
    MState#mstate{done_event = DoneEvent}.

handle_event(Event, {TASK_ID, Extra}, MState) when Event == MState#mstate.done_event ->
    ?LOG_DEBUG("Task ~p has finished (Extra=~p)", [TASK_ID, Extra]),
    Me = node(),
    case Extra of
        {node, Me} ->
            Nodes = get_nodes(TASK_ID, MState),
            wm_event:announce_nodes(Nodes, Event, {TASK_ID, Extra});
        _ ->
            ok
    end,
    terminate_task(TASK_ID, MState);
handle_event(Event, {TASK_ID, EventData}, MState) ->
    case maps:get(TASK_ID, MState#mstate.subscribers, []) of
        SubscribedEvents ->
            case sets:is_element(TASK_ID, SubscribedEvents) of
                true ->
                    send_event_to_module(one_state, TASK_ID, {Event, EventData}, MState);
                fasle ->
                    MState
            end
    end.

calc_id(Nodes) ->
    erlang:phash2({lists:sort(Nodes), wm_utils:timestamp(microsecond)}).

start_module(not_exists, ExtraData, Nodes, MState) ->
    TASK_ID = calc_id(Nodes),
    AddrList = [wm_utils:get_address(X) || X <- Nodes],
    start_module(TASK_ID, ExtraData, AddrList, MState);
start_module(TASK_ID, ExtraData, Nodes, MState) ->
    ?LOG_DEBUG("Start module ~p for task ~p (~p)", [?MODULE, TASK_ID, Nodes]),
    Module = MState#mstate.module,
    AddrList = [wm_utils:get_address(X) || X <- Nodes],
    ?LOG_DEBUG("Start ~p for ~p nodes, ~p", [Module, length(AddrList) + 1, TASK_ID]),
    Args = [{extra, ExtraData}, {nodes, AddrList}, {task_id, TASK_ID}, {root, MState#mstate.root}],
    case wm_sup:start_link({[Module], Args}) of
        {ok, SupPid} ->
            ModPid = wm_sup:get_child_pid(SupPid),
            ?LOG_DEBUG("Supervisor ~p for ~p (~p) started", [SupPid, Module, ModPid]),
            Sups = maps:put(TASK_ID, SupPid, MState#mstate.sups),
            Mods = maps:put(TASK_ID, ModPid, MState#mstate.mods),
            SMap = maps:put(TASK_ID, not_ready, MState#mstate.status),
            NMap = maps:put(TASK_ID, AddrList, MState#mstate.nodes),
            {TASK_ID,
             MState#mstate{sups = Sups,
                           mods = Mods,
                           status = SMap,
                           nodes = NMap}};
        {error, {shutdown, Error}} ->
            ?LOG_ERROR("Cannot start module ~p (id=~p, nodes=~p): ~p",
                       [MState#mstate.module, TASK_ID, AddrList, Error]),
            {TASK_ID, MState}
    end.

do_send_confirm(AllState, TASK_ID, Msg, Nodes) ->
    ?LOG_DEBUG("Send ~P to ~p (~p)", [Msg, 10, Nodes, TASK_ID]),
    MyAddr = wm_conf:get_my_relative_address(hd(Nodes)),
    NewMsg = {send_event, AllState, MyAddr, TASK_ID, Msg},
    wm_api:cast_self_confirm(NewMsg, Nodes).

get_status(TASK_ID, MState) ->
    maps:get(TASK_ID, MState#mstate.status, not_ready).

get_nodes(TASK_ID, MState) ->
    maps:get(TASK_ID, MState#mstate.nodes, []).

set_ready(TASK_ID, MState) ->
    Status = maps:put(TASK_ID, ready, MState#mstate.status),
    MState#mstate{status = Status}.

queue_request(AllState, TASK_ID, Msg, MState) ->
    ?LOG_DEBUG("Queue request ~P (~p, ~p)", [Msg, 10, TASK_ID, AllState]),
    ReqsList = [{AllState, Msg} | maps:get(TASK_ID, MState#mstate.reqs, [])],
    ReqsMap = maps:put(TASK_ID, ReqsList, MState#mstate.reqs),
    MState#mstate{reqs = ReqsMap}.

release_requested(TASK_ID, MState) ->
    F = fun({AllState, Msg}) -> send_event_to_module(AllState, TASK_ID, Msg, MState) end,
    [F(X) || X <- maps:get(TASK_ID, MState#mstate.reqs, [])],
    Reqs = maps:put(TASK_ID, [], MState#mstate.reqs),
    MState#mstate{reqs = Reqs}.

send_event_to_module(AllState, TASK_ID, Msg, MState) ->
    case maps:get(TASK_ID, MState#mstate.mods, not_found) of
        not_found ->
            ?LOG_DEBUG("Cannot send event, no such task id: ~p", [TASK_ID]);
        Pid ->
            ?LOG_DEBUG("Send event to ~p: ~P (~p, ~p)", [MState#mstate.module, Msg, 10, Pid, TASK_ID]),
            case AllState of
                one_state ->
                    gen_fsm:send_event(Pid, Msg);
                all_state ->
                    gen_fsm:send_all_state_event(Pid, Msg)
            end
    end,
    MState.

request_nodes_async(TASK_ID, From) ->
    ?LOG_DEBUG("Request nodes for task ~p from ~p", [TASK_ID, From]),
    MyAddr = wm_conf:get_my_relative_address(From),
    ok = wm_api:cast_self({get_task_nodes, TASK_ID, MyAddr}, [From]).

terminate_task(TASK_ID, MState) ->
    case maps:get(TASK_ID, MState#mstate.sups, not_found) of
        not_found ->
            MState;
        Sup ->
            ?LOG_DEBUG("Shutdown module ~p (~p)", [MState#mstate.module, TASK_ID]),
            exit(Sup, shutdown),
            Sbrs =
                case maps:is_key(TASK_ID, MState#mstate.subscribers) of
                    true ->
                        maps:remove(TASK_ID, MState#mstate.subscribers);
                    false ->
                        MState#mstate.subscribers
                end,
            Sups = maps:remove(TASK_ID, MState#mstate.sups),
            Mods = maps:remove(TASK_ID, MState#mstate.mods),
            Reqs = maps:remove(TASK_ID, MState#mstate.reqs),
            SMap = maps:remove(TASK_ID, MState#mstate.status),
            NMap = maps:remove(TASK_ID, MState#mstate.nodes),
            MState#mstate{sups = Sups,
                          mods = Mods,
                          reqs = Reqs,
                          status = SMap,
                          nodes = NMap,
                          subscribers = Sbrs}
    end.

get_factory_name(Type) ->
    NameStr = atom_to_list(?MODULE) ++ "_" ++ atom_to_list(Type),
    list_to_existing_atom(NameStr).

handle_send_event(AllState, From, TASK_ID, Msg, MState) ->
    ?LOG_DEBUG("Handle send event: a=~p f=~p id=~p", [AllState, From, TASK_ID]),
    case get_status(TASK_ID, MState) of
        ready ->
            {noreply, send_event_to_module(AllState, TASK_ID, Msg, MState)};
        not_ready ->
            Check = {check_event_handling, AllState, From, TASK_ID, Msg},
            wm_utils:wake_up_after(?REPEAT_CALL_INTERVAL, Check),
            request_nodes_async(TASK_ID, From),
            {noreply, queue_request(AllState, TASK_ID, Msg, MState)}
    end.
