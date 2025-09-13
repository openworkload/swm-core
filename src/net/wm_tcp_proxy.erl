-module(wm_tcp_proxy).

-behaviour(gen_server).

-export([start_link/3, stop/1]).          %% Public API
-export([acceptor/3]).                    %% Internal accept loop (spawned)
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

                                          %% gen_server callbacks

-include("../lib/wm_log.hrl").

-define(LISTEN_OPTS, [binary, {packet, raw}, {active, false}, {reuseaddr, true}, {backlog, 128}]).
-define(CONNECT_OPTS,
        [binary,
         {packet, raw},
         {active, false},
         {nodelay, true},
         {keepalive, true},
         {send_timeout, 15000},
         {exit_on_close, false}]).

-record(lstate, {lsock :: port(), up_host :: inet:hostname() | inet:ip_address(), up_port :: inet:port_number()}).
-record(cstate,
        {csock :: port(),
         usock :: undefined | port(),
         up_host :: inet:hostname() | inet:ip_address(),
         up_port :: inet:port_number()}).

-type listen_socket() :: port().
-type socket() :: port().

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link(inet:port_number(), inet:hostname() | inet:ip_address(), inet:port_number()) ->
                    {ok, pid()} | {error, term()}.
start_link(Port, UpHost, UpPort) ->
    gen_server:start_link(?MODULE, {listener, Port, UpHost, UpPort}, []).

-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init({listener, inet:port_number(), inet:hostname() | inet:ip_address(), inet:port_number()} |
           {conn, socket(), inet:hostname() | inet:ip_address(), inet:port_number()}) ->
              {ok, {listener, #lstate{}} | {conn, #cstate{}}} | {stop, term()}.
-spec handle_call(term(), {pid(), term()}, {listener, #lstate{}} | {conn, #cstate{}}) ->
                     {reply, term(), {listener, #lstate{}} | {conn, #cstate{}}}.
-spec handle_cast(term(), {listener, #lstate{}} | {conn, #cstate{}}) ->
                     {noreply, {listener, #lstate{}} | {conn, #cstate{}}} |
                     {stop, term(), {listener, #lstate{}} | {conn, #cstate{}}}.
-spec handle_info(term(), {listener, #lstate{}} | {conn, #cstate{}}) ->
                     {noreply, {listener, #lstate{}} | {conn, #cstate{}}} |
                     {stop, term(), {listener, #lstate{}} | {conn, #cstate{}}}.
init({listener, Port, UpHost, UpPort}) ->
    ?LOG_DEBUG("Start proxy listener from localhost:~p to ~s:~p", [Port, UpHost, UpPort]),
    process_flag(trap_exit, true),
    case gen_tcp:listen(Port, ?LISTEN_OPTS) of
        {ok, LSock} ->
            _ = spawn_link(?MODULE, acceptor, [LSock, UpHost, UpPort]),
            {ok,
             {listener,
              #lstate{lsock = LSock,
                      up_host = UpHost,
                      up_port = UpPort}}};
        {error, Reason} ->
            {stop, {listen_failed, Reason}}
    end;
init({conn, CSock, UpHost, UpPort}) ->
    ?LOG_DEBUG("Start proxy connector to ~s:~p", [UpHost, UpPort]),
    process_flag(trap_exit, true),
    {ok,
     {conn,
      #cstate{csock = CSock,
              usock = undefined,
              up_host = UpHost,
              up_port = UpPort}}}.

handle_call(stop, _From, {listener, L} = State) ->
    ?LOG_DEBUG("Stop proxy listener"),
    catch gen_tcp:close(L#lstate.lsock),
    {stop, normal, ok, State};
handle_call(_Other, _From, State) ->
    {reply, {error, unsupported}, State}.

handle_cast(activate,
            {conn,
             C0 = #cstate{csock = CSock,
                          up_host = Host,
                          up_port = Port}}) ->
    ?LOG_DEBUG("Activete proxy connector"),
    case gen_tcp:connect(Host, Port, ?CONNECT_OPTS) of
        {ok, USock} ->
            ok = inet:setopts(CSock, [{active, once}]),
            ok = inet:setopts(USock, [{active, once}]),
            {noreply, {conn, C0#cstate{usock = USock}}};
        {error, Reason} ->
            catch gen_tcp:close(CSock),
            {stop, {upstream_connect_failed, Reason}, {conn, C0}}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, {listener, _} = State) ->
    %% Listener has no special infos
    {noreply, State};
handle_info({tcp, CSock, Data}, {conn, C = #cstate{csock = CSock, usock = USock}}) when is_port(USock) ->
    ?LOG_DEBUG("Proxy connection: client -> upstream"),
    case gen_tcp:send(USock, Data) of
        ok ->
            ok;
        {error, _} ->
            exit(send_error_client_to_upstream)
    end,
    ok = inet:setopts(CSock, [{active, once}]),
    {noreply, {conn, C}};
handle_info({tcp, USock, Data}, {conn, C = #cstate{csock = CSock, usock = USock}}) ->
    ?LOG_DEBUG("Proxy connection: upstream -> client"),
    case gen_tcp:send(CSock, Data) of
        ok ->
            ok;
        {error, _} ->
            exit(send_error_upstream_to_client)
    end,
    ok = inet:setopts(USock, [{active, once}]),
    {noreply, {conn, C}};
handle_info({tcp_closed, CSock}, {conn, C = #cstate{csock = CSock, usock = USock}}) ->
    ?LOG_DEBUG("Proxy connection closed (1)"),
    shutdown_both(CSock, USock),
    {stop, normal, {conn, C}};
handle_info({tcp_closed, USock}, {conn, C = #cstate{csock = CSock, usock = USock}}) ->
    ?LOG_DEBUG("Proxy connection closed (2)"),
    shutdown_both(USock, CSock),
    {stop, normal, {conn, C}};
handle_info({tcp_error, _Sock, Reason}, {conn, C = #cstate{csock = CSock, usock = USock}}) ->
    ?LOG_DEBUG("Proxy TCP error: ~p", [Reason]),
    close_both(CSock, USock),
    {stop, tcp_error, {conn, C}};
handle_info({'EXIT', _From, Why}, State) ->
    ?LOG_DEBUG("Proxy exit: ~p", [Why]),
    {noreply, State}.

-spec terminate(term(), {listener, #lstate{}} | {conn, #cstate{}}) -> ok.
terminate(_Reason, {listener, L}) ->
    catch gen_tcp:close(L#lstate.lsock),
    ok;
terminate(_Reason, {conn, C}) ->
    close_maybe(C#cstate.csock),
    close_maybe(C#cstate.usock),
    ok.

-spec code_change(term(), {listener, #lstate{}} | {conn, #cstate{}}, term()) ->
                     {ok, {listener, #lstate{}} | {conn, #cstate{}}}.
code_change(_Vsn, State, _Extra) ->
    {ok, State}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec acceptor(listen_socket(), inet:hostname() | inet:ip_address(), inet:port_number()) -> no_return().
acceptor(LSock, UpHost, UpPort) ->
    ?LOG_DEBUG("Proxy acceptor ~p:~p", [UpHost, UpPort]),
    process_flag(trap_exit, true),
    case gen_tcp:accept(LSock) of
        {ok, CSock} ->
            case gen_server:start_link(?MODULE, {conn, CSock, UpHost, UpPort}, []) of
                {ok, Pid} ->
                    ok = gen_tcp:controlling_process(CSock, Pid),
                    gen_server:cast(Pid, activate),
                    acceptor(LSock, UpHost, UpPort);
                {error, _} = Err ->
                    catch gen_tcp:close(CSock),
                    exit(Err)
            end;
        {error, closed} ->
            exit(normal);
        {error, Reason} ->
            exit({accept_error, Reason})
    end.

-spec shutdown_both(socket(), undefined | socket()) -> ok.
shutdown_both(_From, undefined) ->
    ok;
shutdown_both(FromSock, ToSock) ->
    catch gen_tcp:shutdown(ToSock, write),
    close_maybe(ToSock),
    close_maybe(FromSock),
    ok.

-spec close_both(undefined | socket(), undefined | socket()) -> ok.
close_both(A, B) ->
    close_maybe(A),
    close_maybe(B),
    ok.

-spec close_maybe(undefined | socket()) -> ok.
close_maybe(undefined) ->
    ok;
close_maybe(S) when is_port(S) ->
    catch gen_tcp:close(S),
    ok.
