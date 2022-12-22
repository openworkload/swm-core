-module(wm_tcp_server).

-behavior(gen_server).

-export([start_link/1, loop/1]).
-export([init/1, recv/1, reply/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include("../lib/wm_log.hrl").

-define(DEFAULT_TIMEOUT, 60000).
-define(SSL_HANDSHAKE_TIMEOUT, 5000).

-record(mstate, {port = none, default_port = none, sname :: string(), spool, ip = any, lsocket = null, pids = []}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    case ssl:start() of
        ok ->
            gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []);
        {error, Reason} ->
            ?LOG_ERROR("Cannot start ssl: ~p", [Reason]),
            {stop, Reason}
    end.

reply(Data, Socket) ->
    ?LOG_DEBUG("Reply ~P", [Data, 5]),
    Bin = wm_utils:encode_to_binary(Data),
    ssl:send(Socket, Bin).

recv(Socket) ->
    %?LOG_DEBUG("Receiving data using socket: ~p", [Socket]),
    case ssl:recv(Socket, 0) of
        {ok, Bin} ->
            case wm_utils:decode_from_binary(Bin) of
                {call, M, F, Args} ->
                    ?LOG_DEBUG("Received CALL-RPC ~p:~p(~P)", [M, F, Args, 10]),
                    {call, M, F, Args};
                {cast, M, F, Args, Tag, FinalNodeName} ->
                    ?LOG_DEBUG("Received CAST-RPC ~p:~p(~P) tag=~p addr=~p", [M, F, Args, 10, Tag, FinalNodeName]),
                    {cast, M, F, Args, Tag, FinalNodeName};
                {error, closed} ->
                    ?LOG_ERROR("Socket closed"),
                    reply(closed, Socket);
                {error, Error} ->
                    ?LOG_ERROR("Socket: ~p", [Error]),
                    reply(Error, Socket)
            end;
        {error, closed} ->
            ?LOG_ERROR("Connection has been closed by client"),
            {error, closed};
        Other ->
            ?LOG_ERROR("Received unknown data: ~p", [Other]),
            Other
    end.

%% ============================================================================
%% Callbacks
%% ============================================================================

handle_call(start_listen, _, MState) ->
    Port = MState#mstate.port,
    Spool = MState#mstate.spool,
    ?LOG_DEBUG("Start listening to port number ~p (spool=~p)", [Port, Spool]),
    DefaultCA = filename:join([Spool, "secure/cluster/cert.pem"]),
    DefaultCert = filename:join([Spool, "secure/node/cert.pem"]),
    DefaultKey = filename:join([Spool, "secure/node/key.pem"]),
    NodeCert = wm_conf:g(node_cert, {DefaultCert, string}),
    NodeKey = wm_conf:g(node_key, {DefaultKey, string}),
    CA = wm_conf:g(cluster_cert, {DefaultCA, string}),
    case filelib:is_file(CA) of
        false ->
            ErrMsg = io_lib:format("No such file (CA): ~p", [CA]),
            ?LOG_ERROR(ErrMsg),
            io:format(ErrMsg ++ "~n"),
            {reply, no_exists, MState};
        _ ->
            case filelib:is_file(NodeCert) of
                false ->
                    ErrMsg = io_lib:format("No such file: ~p", [NodeCert]),
                    ?LOG_ERROR(ErrMsg),
                    io:format(ErrMsg ++ "~n"),
                    {reply, no_exists, MState};
                _ ->
                    case filelib:is_file(NodeKey) of
                        false ->
                            ErrMsg = io_lib:format("No such file: ~p", [NodeKey]),
                            ?LOG_ERROR(ErrMsg),
                            io:format(ErrMsg ++ "~n"),
                            {reply, no_exists, MState};
                        _ ->
                            ?LOG_DEBUG("Required certificates have been found"),
                            {Reply, MState2} = listen(Port, NodeCert, NodeKey, CA, MState),
                            {reply, Reply, MState2}
                    end
            end
    end;
handle_call(_Msg, _Caller, State) ->
    {reply, State}.

handle_cast({accepted, _Pid}, State = #mstate{}) ->
    {noreply, accept(State)}.

handle_info({'EXIT', Pid, normal}, MState) ->
    ?LOG_DEBUG("Process ~p has finished normally", [Pid]),
    {noreply, MState};
handle_info({'EXIT', Pid, Msg}, MState) ->
    ?LOG_DEBUG("Process ~p has not finished normally: ~p", [Pid, Msg]),
    {noreply, MState};
handle_info(Msg, MState) ->
    ?LOG_DEBUG("Received unknown message: ~p", [Msg]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason),
    ssl:stop().

code_change(_OldVersion, Library, _Extra) ->
    {ok, Library}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

init(Args) ->
    ?LOG_INFO("Load tcpserver"),
    MState1 = parse_args(Args, #mstate{}),
    Port =
        case wm_conf:select(node, {name, MState1#mstate.sname}) of
            {error, _} ->
                case MState1#mstate.default_port of
                    none ->
                        ?LOG_INFO("TCP server will not be started (no port)"),
                        none;
                    ConfPort ->
                        ?LOG_DEBUG("Going to start TCP server on port ~p", [ConfPort]),
                        ConfPort
                end;
            {ok, SelfNode} ->
                ?LOG_DEBUG("My node ~p was found in the local db", [SelfNode]),
                wm_entity:get(api_port, SelfNode)
        end,
    %FIXME If port of node001 was X and port of node002
    %      is changed to X and port of node001 is changed
    %      to Y, then node001 will still start to leasten
    %      to the old port X and node002 will fail to start
    %      leasten the port X. This will lead to the scenario
    %      when parent cannot update configs of the both node001
    %      and node002, so for now port cannot be moved (if moved
    %      then remove spool of children nodes).
    MState2 = MState1#mstate{port = Port},
    wm_works:call_asap(?MODULE, start_listen),
    ?LOG_DEBUG("Module state: ~p", [MState2]),
    {ok, MState2}.

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{sname, Name} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{sname = Name});
parse_args([{default_api_port, Port} | T], #mstate{} = MState) when is_list(Port) ->
    parse_args(T, MState#mstate{default_port = list_to_integer(Port)});
parse_args([{default_api_port, Port} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{default_port = Port});
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, #mstate{} = MState).

accept(MState = #mstate{lsocket = ListenSocket}) ->
    ?LOG_DEBUG("Connection has been accepting"),
    Pid = spawn(?MODULE, loop, [{self(), ListenSocket, wm_api}]),
    ?LOG_DEBUG("New connection process pid: ~p", [Pid]),
    MState#mstate{pids = [Pid | MState#mstate.pids]}. %TODO should the pids be used?

loop({Server, ListenSocket, Module}) ->
    ?LOG_DEBUG("Ready to accept new SSL connection"),
    try
        case ssl:transport_accept(ListenSocket) of
            {ok, TlsTransportSocket} ->
                ?LOG_DEBUG("Transport connection has been accepted"),
                case ssl:handshake(TlsTransportSocket, ?SSL_HANDSHAKE_TIMEOUT) of
                    {ok, SslSocket} ->
                        {IPv4, Port} =
                            case ssl:peername(SslSocket) of
                                {ok, {X, Y}} ->
                                    {X, Y};
                                {error, Reason} ->
                                    {Reason, []}
                            end,
                        {IP1, IP2, IP3, IP4} = IPv4,
                        {ok, [{protocol, ProtoVer}, {selected_cipher_suite, CipherSuite}]} =
                            ssl:connection_information(SslSocket, [protocol, selected_cipher_suite]),
                        ?LOG_DEBUG("SSL handshake performed with peer: ~p.~p.~p.~p:~p; proto: ~p, cipher: ~w",
                                   [IP1, IP2, IP3, IP4, Port, ProtoVer, CipherSuite]),
                        {ok, CertBin} = ssl:peercert(SslSocket),
                        Cert = public_key:pkix_decode_cert(CertBin, otp),
                        UserId = wm_cert:get_uid(Cert),
                        ?LOG_DEBUG("Peer certificate user id: ~p", [UserId]),
                        gen_server:cast(Server, {accepted, self()}),
                        T = wm_conf:g(conn_timeout, {?DEFAULT_TIMEOUT, integer}),
                        %?LOG_DEBUG("Call ~p with message ~p",
                        %[Module, {accept_conn, SslSocket}]),
                        ServerPid = self(),
                        case gen_server:call(Module, {accept_conn, ServerPid, SslSocket}, T) of
                            ok ->
                                ?LOG_DEBUG("Module ~p has handled the connection", [Module]);
                            Error ->
                                ?LOG_ERROR("Module ~p could not handle the connection: ~p", [Module, Error])
                        end,
                        % Wait for the call handling, otherwise the connection
                        % will be closed by the server automatically:
                        receive
                            replied ->
                                ok
                        after T ->
                            ?LOG_ERROR("API call timeout (~pms) Pid=~p", [T, ServerPid]),
                            []
                        end;
                    {error, Reason} ->
                        ?LOG_ERROR("Connection error: ~p", [Reason]),
                        exit(normal)
                end;
            {error, closed} ->
                ?LOG_DEBUG("Socket has closed"),
                exit(normal);
            {error, timeout} ->
                ?LOG_DEBUG("Socket timeout has accured"),
                exit(normal)
        end
    catch
        exit:normal ->
            ?LOG_DEBUG("SSL transport normal exit"),
            exit(normal);
        E1:E2 ->
            ?LOG_DEBUG("SSL transport exception: ~p:~p", [E1, E2]),
            exit(normal)
    end.

enum_cacerts([], _Certs) ->
    unknown_ca;
enum_cacerts([Cert | Rest], Certs) ->
    case lists:member(Cert, Certs) of
        true ->
            {trusted_ca, Cert};
        false ->
            enum_cacerts(Rest, Certs)
    end.

mk_opts(Cert, Key, CA) ->
    {ok, ServerCAs} = file:read_file(CA),
    Pems = public_key:pem_decode(ServerCAs),
    CaCerts = lists:map(fun({_, Der, _}) -> Der end, Pems),
    PartChain = fun(ChainCerts) -> enum_cacerts(CaCerts, ChainCerts) end,
    [binary,
     {header, 0},
     {packet, 4},
     {depth, 99},
     {active, false},
     {reuseaddr, true},
     {verify, verify_peer},
     {fail_if_no_peer_cert, true},
     {versions, ['tlsv1.3']},
     {partial_chain, PartChain},
     {cacertfile, CA},
     {certfile, Cert},
     {keyfile, Key}].

listen(Port, NodeCert, NodeKey, CA, MState) ->
    case ssl:listen(Port, mk_opts(NodeCert, NodeKey, CA)) of
        {ok, ListenSocket} ->
            {ok, accept(MState#mstate{lsocket = ListenSocket})};
        {error, Reason} ->
            ?LOG_ERROR("Could not start listening port ~p: ~p", [Port, Reason]),
            {Reason, MState};
        Error ->
            ?LOG_ERROR("Failed to start listening port ~p: ~p", [Port, Error]),
            {Error, MState}
    end.
