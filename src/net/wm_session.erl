-module(wm_session).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([handle_received_call/1, handle_received_cast/1]).

-include("../lib/wm_entity.hrl").
-include("../lib/wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

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
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("Session manager has been started ~p", [MState]),
    {ok, MState}.

handle_call(Msg, From, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown call from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast({call, Params}, #mstate{} = MState) ->
    spawn(?MODULE, handle_received_call, [Params]),
    {noreply, MState};
handle_cast({cast, Params}, #mstate{} = MState) ->
    spawn(?MODULE, handle_received_cast, [Params]),
    {noreply, MState};
handle_cast(Msg, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown cast: ~p", [Msg]),
    {noreply, MState}.

handle_info(Msg, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown info message: ~p", [Msg]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_, #mstate{} = MState, _) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, MState).

-spec handle_received_call({atom(), atom(), term(), any(), pid()}) -> any().
handle_received_call({wm_api, Fun, {Mod, Msg}, Socket, ServerPid}) ->
    ?LOG_DEBUG("Direct remote call: ~p:~p", [?MODULE, Fun]),
    Return =
        case verify_rpc(Mod, Fun, {Mod, Msg}, Socket) of
            {ok, _} ->
                Result =
                    case Msg of
                        ping ->
                            ?LOG_DEBUG("I'm pinged by ~p", [Mod]),
                            % Special case is needed for:
                            % 1. optimization
                            % 2. wm_pinger may be busy pinging other nodes
                            {pong, wm_state:get_current()};
                        _ ->
                            wm_utils:protected_call(Mod, Msg)
                    end,
                ?LOG_DEBUG("Direct call result: ~P", [Result, 5]),
                Result;
            Error ->
                {error, Error}
        end,
    wm_tcp_server:reply(Return, Socket),
    ServerPid
    ! replied; % only now the connection can be closed
handle_received_call({Module, Arg0, [], Socket}) ->
    handle_received_call({Module, Arg0, {}, Socket});
handle_received_call({Module, Arg0, Args, Socket, ServerPid}) ->
    ?LOG_DEBUG("API call: module=~p, arg0=~p", [Module, Arg0]),
    case verify_rpc(Module, Arg0, Args, Socket) of
        {ok, _} ->
            try
                Msg = erlang:insert_element(1, Args, Arg0),
                Result = wm_utils:protected_call(Module, Msg),
                %?LOG_DEBUG("Call result: ~P", [Result, 10]),
                wm_tcp_server:reply(Result, Socket)
            catch
                T:Error ->
                    ErrRet = {string, io_lib:format("Cannot handle RPC to ~p: ~p(~P)", [Module, Arg0, Args, 5])},
                    ?LOG_DEBUG("RPC FAILED [CALL]: ~p:~p", [T, Error]),
                    wm_tcp_server:reply(ErrRet, Socket)
            end;
        Error ->
            wm_tcp_server:reply({error, Error}, Socket)
    end,
    ServerPid ! replied.

-spec handle_received_cast({atom(), term(), list(), string(), node_address(), any(), pid()}) -> ok | {error, term()}.
handle_received_cast({Module, Arg0, Args, Tag, Addr, Socket, ServerPid}) ->
    ServerPid
    ! replied, % release the waiting connection process
    ?LOG_DEBUG("API cast: ~p ~p ~P ~100p ~1000p", [Module, Arg0, Args, 3, Tag, Addr]),
    case verify_rpc(Module, Arg0, Args, Socket) of
        {ok, NewArgs} ->
            case wm_conf:is_my_address(Addr) of
                true ->
                    Msg = case NewArgs of
                              [] ->
                                  {Arg0};
                              _ ->
                                  erlang:insert_element(1, NewArgs, Arg0)
                          end,
                    gen_server:cast(Module, Msg);
                false ->
                    wm_rpc:cast(Module, Arg0, NewArgs, Addr)
            end,
            wm_tcp_server:reply(ok, Socket);
        Error ->
            wm_tcp_server:reply({error, Error}, Socket)
    end.

verify_rpc(_, route, {StartAddr, EndAddr, RouteID, Requestor, D, Route}, _) ->
    {ok, {StartAddr, EndAddr, RouteID, Requestor, D, [node() | Route]}};
verify_rpc(_, _, Msg, _) ->
    {ok, Msg}.
