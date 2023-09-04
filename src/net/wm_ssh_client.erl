-module(wm_ssh_client).

-behaviour(gen_server).

-export([start_link/1, connect/3, make_tunnel/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../lib/wm_log.hrl").

-define(TCPIP_CONN_TIMEOUT, 2000).

-record(mstate, {spool = "" :: string(), connection = undefined :: reference()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    ?LOG_INFO("Start SSH client process with args: ~p", [Args]),
    gen_server:start_link(?MODULE, Args, []).

-spec connect(pid(), inet:ip_address(), inet:port_number()) -> ok | {error, term()}.
connect(ProcessPid, Host, Port) ->
    gen_server:call(ProcessPid, {connect, Host, Port}).

-spec make_tunnel(inet:ip_address(), inet:port_number(), inet:ip_address(), inet:port_number()) ->
                     {ok, inet:port_number()} | {error, term()}.
make_tunnel(ListenHost, ListenPort, ConnectToHost, ConnectToPort) ->
    gen_server:call(?MODULE, {make_tunnel, ListenHost, ListenPort, ConnectToHost, ConnectToPort}).

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
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("SSH tunnel server has been started"),
    {ok, MState}.

handle_call({connect, Host, Port}, _From, #mstate{spool = Spool} = MState) ->
    {Result, MState2} = do_connect(Host, Port, Spool, MState),
    {reply, Result, MState2};
handle_call({make_tunnel, ListenHost, ListenPort, ConnectToHost, ConnectToPort}, _, #mstate{} = MState) ->
    Result = do_make_tunnel(ListenHost, ListenPort, ConnectToHost, ConnectToPort, MState),
    {reply, Result, MState};
handle_call(_Msg, _From, #mstate{} = MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast(_, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(_Info, #mstate{} = MState) ->
    {noreply, MState}.

terminate(Reason, #mstate{} = MState) ->
    do_close_connection(MState),
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec do_connect(any | string() | inet:ip_address(), inet:port_number(), string(), #mstate{}) -> {term(), #mstate{}}.
do_connect(any, Port, Spool, #mstate{} = MState) ->
    do_connect(wm_utils:get_my_hostname(), Port, Spool, MState);
do_connect(Host, Port, Spool, #mstate{} = MState) ->
    HostCertsDir = filename:join([Spool, "secure/host"]),
    Options =
        [{silently_accept_hosts, true},
         {user_dir, HostCertsDir},
         {user, "swm"},
         {password, "swm"},
         {user_interaction, false}],
    case ssh:connect(Host, Port, Options) of
        {ok, Connection} ->
            ?LOG_DEBUG("SSH client connection to  ~p:~p returned connection reference: ~p", [Host, Port, Connection]),
            {ok, MState#mstate{connection = Connection}};
        {error, Error} ->
            ?LOG_DEBUG("SSH client connection to  ~p:~p failed: ~p", [Host, Port, Error]),
            {{error, Error}, MState}
    end.

-spec do_make_tunnel(any | string() | inet:ip_address(),
                     inet:port_number(),
                     any | string() | inet:ip_address(),
                     inet:port_number(),
                     #mstate{}) ->
                        {ok, inet:port_number()} | {error, term()}.
do_make_tunnel(ListenHost, ListenPort, ConnectToHost, ConnectToPort, #mstate{connection = Connection}) ->
    ?LOG_INFO("Open ssh tunnel: ~p:~p <==> ~p:~p", [ListenHost, ListenPort, ConnectToHost, ConnectToPort]),
    ssh:tcpip_tunnel_to_server(Connection, ListenHost, ListenPort, ConnectToHost, ConnectToPort, ?TCPIP_CONN_TIMEOUT).

-spec do_close_connection(#mstate{}) -> ok | {error, term()}.
do_close_connection(#mstate{connection = Connection}) ->
    ssh:close(Connection).
