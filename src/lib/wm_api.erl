-module(wm_api).

-behaviour(gen_server).

-export([start_link/1, call_self/2, cast_self/2, call_self_process/5, cast_all_nodes_process/4, cast_self_confirm/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_log.hrl").

-record(mstate, {parent :: string(), sname :: string(), parent_port = unknown :: integer()}).

-define(DEFAULT_CONN_TIMEOUT, 60000).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Call gen_server:call of the same module on remote node
-spec call_self(term(), term()) -> ok.
call_self(Msg, Node) ->
    Mod = wm_utils:get_calling_module_name(),
    RequestID = wm_utils:uuid(v4),
    Pid = spawn(?MODULE, call_self_process, [Mod, Msg, self(), Node, RequestID]),
    ?LOG_DEBUG("Waiting for message {~p, Answer} from "
               "~p ...",
               [RequestID, Pid]),
    Ms = wm_conf:g(conn_timeout, {?DEFAULT_CONN_TIMEOUT, integer}),
    receive
        {RequestID, Answer} ->
            Answer
    after Ms ->
        ?LOG_ERROR("API call timeout (~pms), ID=~p", [Ms, RequestID]),
        []
    end.

%% @doc Cast gen_server module
-spec cast_self(term(), [atom()]) -> ok.
cast_self(Msg, Nodes) when is_list(Nodes) ->
    Mod = wm_utils:get_calling_module_name(),
    gen_server:cast(?MODULE, {send, Mod, Msg, Nodes});
cast_self(Msg, Node) when is_atom(Node) ->
    cast_self(Msg, [Node]).

%% @doc Cast message to gen_server module and wait for delivery confirmation
-spec cast_self_confirm(term(), [atom()]) -> ok.
cast_self_confirm(Msg, Nodes) when is_list(Nodes) ->
    Mod = wm_utils:get_calling_module_name(),
    %TODO: return on some timeout
    cast_all_nodes_process(Mod, Msg, Nodes, wait).

%% ============================================================================
%% Callbacks
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
handle_call({accept_conn, ServerPid, Socket}, _From, #mstate{} = MState) ->
    ?LOG_DEBUG("Accepting new connection"),
    MState2 = connection_loop(Socket, ServerPid, MState),
    ?LOG_DEBUG("Connection loop exit"),
    {reply, ok, MState2};
handle_call({recv, Mod, Msg}, From, #mstate{} = MState) ->
    ?LOG_DEBUG("Received self-call request (~p) from ~p", [Mod, From]),
    {reply, wm_utils:protected_call(Mod, Msg), MState}.

handle_cast({recv_event, Mod, Event}, #mstate{} = MState) ->
    ?LOG_DEBUG("Received self-cast request: ~p (event=~p)", [Mod, Event]),
    do_send_event(Mod, Event),
    {noreply, MState};
handle_cast({send, _, _, []}, #mstate{} = MState) ->
    ?LOG_DEBUG("Sent a self-cast to empty node list "
               "(just ignore)"),
    {noreply, MState};
handle_cast({send, Mod, Msg, Nodes}, #mstate{} = MState) ->
    NodesStr = io_lib:format("~p", [Nodes]),
    ?LOG_DEBUG("Perform remote self-cast init'ed by "
               "~p to ~s",
               [Mod, lists:flatten(NodesStr)]),
    Args = [Mod, Msg, Nodes, no_wait],
    Pid = spawn(?MODULE, cast_all_nodes_process, Args),
    ?LOG_DEBUG("Cast process started with pid=~p, nodes=~p", [Pid, Nodes]),
    {noreply, MState};
handle_cast({recv, Mod, Msg}, #mstate{} = MState) ->
    ?LOG_DEBUG("Received self-cast request: ~p, Msg=~p", [Mod, Msg]),
    gen_server:cast(Mod, Msg),
    {noreply, MState};
handle_cast({event, EventType, EventData}, MState) ->
    {noreply, handle_event(EventType, EventData, MState)}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

handle_info(Msg, MState) ->
    ?LOG_DEBUG("Received info message: ~p", [Msg]),
    {noreply, MState}.

code_change(_OldVsn, Data, _Extra) ->
    {ok, Data}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @hidden
init(Args) ->
    ?LOG_INFO("Load API service"),
    process_flag(trap_exit, true),
    Host = wm_utils:get_my_hostname(),
    MState1 = parse_args(Args, #mstate{}),
    MState2 =
        case wm_utils:get_parent_from_conf({MState1#mstate.sname, Host}) of
            not_found ->
                MState1;
            {ParentFromConf, ParentPort} ->
                MState1#mstate{parent = ParentFromConf, parent_port = ParentPort}
        end,
    wm_event:subscribe(mon_started, node(), ?MODULE),
    ?LOG_DEBUG("Module state: ~p", [MState2]),
    {ok, MState2}.

handle_event(mon_started, _, #mstate{} = MState) ->
    ?LOG_INFO("Initialize api monitoring metrics"),
    wm_mon:new(history, msg_route),
    MState.

connection_loop(Socket, ServerPid, #mstate{} = MState) ->
    case wm_tcp_server:recv(Socket) of
        {call, Module, Fun, Args} ->
            Msg = {call, {Module, Fun, Args, Socket, ServerPid}},
            gen_server:cast(wm_session, Msg);
        {cast, Module, Fun, Args, Tag, Addr} ->
            Msg = {cast, {Module, Fun, Args, Tag, Addr, Socket, ServerPid}},
            gen_server:cast(wm_session, Msg);
        Other ->
            ?LOG_INFO("Received unknown statement: ~p", [Other])
    end,
    MState.

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{sname, Name} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{sname = Name});
parse_args([{parent, Node} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{parent = Node});
parse_args([{parent_port, Port} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{parent_port = Port});
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, #mstate{} = MState).

split_rpc_msg(Msg) when is_atom(Msg) ->
    {Msg, []};
split_rpc_msg(Msg) ->
    List = tuple_to_list(Msg),
    Arg0 = hd(List),
    ArgT = tl(List),
    {Arg0, list_to_tuple(ArgT)}.

-spec cast_all_nodes_process(atom(), string(), list(), atom()) -> atom().
cast_all_nodes_process(_, _, [], _) ->
    ok;
cast_all_nodes_process(Mod, Msg, [Node | Nodes], Wait) when Node =:= node() ->
    gen_server:cast(?MODULE, {recv, Mod, Msg}),
    cast_all_nodes_process(Mod, Msg, Nodes, Wait);
cast_all_nodes_process(Mod, Msg, [Node | Nodes], no_wait) ->
    {Arg0, Args} = split_rpc_msg(Msg),
    case wm_utils:get_address(Node) of
        not_found ->
            ?LOG_DEBUG("The no_wait-cast to ~p will not be performed", [Node]);
        Addr = {_, _} ->
            ?LOG_DEBUG("no_wait-cast: ~p, ~p --> ~p", [Mod, Arg0, Addr]),
            wm_rpc:cast(Mod, Arg0, Args, Addr)
    end,
    cast_all_nodes_process(Mod, Msg, Nodes, no_wait);
cast_all_nodes_process(Mod,
                       Msg,
                       Nodes,
                       wait) -> %TODO get rid of this version
    F = fun(Node) ->
           {Arg0, Args} = split_rpc_msg(Msg),
           case wm_utils:get_address(Node) of
               not_found ->
                   ?LOG_DEBUG("The wait-cast to ~p will not be performed now", [Node]);
               Addr ->
                   ?LOG_DEBUG("wait-cast: ~p, ~p --> ~p", [Mod, Arg0, Addr]),
                   wm_rpc:cast(Mod, Arg0, Args, Addr)
           end
        end,
    Results1 = [F(X) || X <- Nodes],
    lists:all(fun (ok) ->
                      true;
                  (_) ->
                      false
              end,
              Results1).

do_send_event(Mod, Event) ->
    try
        ok = wm_utils:cast(Mod, Event)
    catch
        E1:E2 ->
            ?LOG_ERROR("Could not send event ~p to ~p: ~p:~p", [Event, Mod, E1, E2])
    end.

-spec call_self_process(atom(), string(), atom(), atom(), string()) -> atom().
call_self_process(Module, Msg, From, To, ID) ->
    ?LOG_DEBUG("call_self_process [remote]: M=~p, Msg=~p, From=~p,To=~p, ID=~p", [Module, Msg, From, To, ID]),
    Answer = wm_rpc:call(?MODULE, recv, {Module, Msg}, To),
    From ! {ID, Answer},
    exit(normal).
