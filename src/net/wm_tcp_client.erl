-module(wm_tcp_client).

-export([connect/1, disconnect/1, rpc/2, send/2, recv/2]).

-include("../lib/wm_log.hrl").

-define(DEFAULT_PORT, 10001).
-define(DEFAULT_SERVER, "localhost").
-define(DEFAULT_CONNECT_TIMEOUT, 5000).

%% ============================================================================
%% API functions
%% ============================================================================

-spec connect(list()) -> {ok, any()} | {error, term()}.
connect(Args) ->
    Host = get_host(Args),
    Port = maps:get(port, Args, ?DEFAULT_PORT),
    Timeout = maps:get(timeout, Args, ?DEFAULT_CONNECT_TIMEOUT),
    Home = wm_utils:get_env("HOME"),
    UserCert = filename:join([Home, ".swm", "cert.pem"]),
    UserKey = filename:join([Home, ".swm", "key.pem"]),
    {Cert, Key} =
        case {filelib:is_file(UserCert), filelib:is_file(UserKey)} of
            {true, true} ->
                {UserCert, UserKey};
            _ ->
                {maps:get(cert, Args, filename:absname(UserCert)), maps:get(key, Args, filename:absname(UserKey))}
        end,
    NativeCert = filename:nativename(Cert),
    NativeKey = filename:nativename(Key),
    ssl:start(),
    Port2 =
        case is_list(Port) of
            true ->
                {X, _} = string:to_integer(Port),
                X;
            _ ->
                Port
        end,
    To = io_lib:format("~p:~p", [Host, Port2]),
    ?LOG_DEBUG("Connect to ~s", [To]),
    try
        case ssl:connect(Host, Port2, mk_opts(NativeCert, NativeKey), Timeout) of
            {ok, Socket} ->
                {ok, {IPv4, LocalPort}} = ssl:sockname(Socket),
                {IP1, IP2, IP3, IP4} = IPv4,
                From = io_lib:format("~p.~p.~p.~p:~p", [IP1, IP2, IP3, IP4, LocalPort]),
                ?LOG_DEBUG("SSL connection from ~s to ~s has established", [From, To]),
                {ok, Socket};
            Error ->
                ?LOG_ERROR("Could not connect to ~s: ~p", [To, Error]),
                Error
        end
    catch
        E1:E2 ->
            ?LOG_ERROR("SSL error: ~p: ~p", [E1, E2]),
            {error, {E1, E2}}
    end.

disconnect(Socket) ->
    ok = ssl:close(Socket).

-spec rpc(term(), term()) -> term().
rpc(RPC, Socket) ->
    ?MODULE:send(RPC, Socket),
    ?MODULE:recv(Socket, []).

%% ============================================================================
%% Implementation functions
%% ============================================================================

send(Msg, Socket) ->
    Bin = wm_utils:encode_to_binary(Msg),
    ok = ssl:send(Socket, Bin).

recv(Socket, Answers) ->
    case ssl:recv(Socket, 0) of
        {ok, Bin} ->
            Answer = wm_utils:decode_from_binary(Bin),
            recv(Socket, [Answer | Answers]);
        {error, closed} ->
            ?LOG_DEBUG("Connection has been closed"),
            Answers;
        {error, Error} ->
            ?LOG_ERROR("Connection error: ~p", [Error]),
            halt(1)
    end.

mk_opts(CertFile, KeyFile) ->
    CaFile = wm_utils:get_env("SWM_CLUSTER_CA"),
    ?LOG_DEBUG("Use ssl certs: ~p ~p ~p", [CertFile, KeyFile, CaFile]),
    [binary,
     {header, 0},
     {packet, 4},
     {active, false},
     {versions, ['tlsv1.3']},
     {partial_chain, wm_utils:get_cert_partial_chain_fun(CaFile)},
     {reuseaddr, true},
     {depth, 99},
     {verify, verify_peer},
     {server_name_indication, disable},
     {cacertfile, CaFile},
     {certfile, CertFile},
     {keyfile, KeyFile}].

get_host(Args) ->
    Server = maps:get(server, Args, ?DEFAULT_SERVER),
    case inet:parse_address(Server) of
        {ok, IPv4Tuple} ->
            IPv4Tuple;
        {error, einval} ->
            Server
    end.
