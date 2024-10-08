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
    {CertPath, KeyPath} = get_cert_key_paths(Args),
    Port2 =
        case is_list(Port) of
            true ->
                {X, _} = string:to_integer(Port),
                X;
            _ ->
                Port
        end,
    To = io_lib:format("~p:~p", [Host, Port2]),
    Opts = mk_opts(CertPath, KeyPath),
    ?LOG_DEBUG("Connect to ~s", [To]),
    try
        case ssl:connect(Host, Port2, Opts, Timeout) of
            {ok, Socket} ->
                {ok, {IPv4, LocalPort}} = ssl:sockname(Socket),
                {IP1, IP2, IP3, IP4} = IPv4,
                From = io_lib:format("~p.~p.~p.~p:~p", [IP1, IP2, IP3, IP4, LocalPort]),
                ?LOG_DEBUG("SSL connection from ~s to ~s has established", [From, To]),
                {ok, Socket};
            Error ->
                ?LOG_ERROR("Could not connect to ~s: ~10000p", [To, Error]),
                Error
        end
    catch
        E1:E2 ->
            ?LOG_ERROR("SSL error: ~p: ~p", [E1, E2]),
            {error, {E1, E2}}
    end.

-spec disconnect(any) -> ok.
disconnect(Socket) ->
    ok = ssl:close(Socket).

-spec rpc(term(), term()) -> term().
rpc(RPC, Socket) ->
    ?MODULE:send(RPC, Socket),
    ?MODULE:recv(Socket, []).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec send(term(), any()) -> ok.
send(Msg, Socket) ->
    Bin = wm_utils:encode_to_binary(Msg),
    ok = ssl:send(Socket, Bin).

-spec recv(any(), term()) -> any().
recv(Socket, Answers) ->
    case ssl:recv(Socket, 0) of
        {ok, Bin} ->
            Answer = wm_utils:decode_from_binary(Bin),
            recv(Socket, [Answer | Answers]);
        {error, closed} ->
            ?LOG_DEBUG("Connection has been closed, previous answers: ~p", [Answers]),
            Answers;
        {error, Error} ->
            ?LOG_ERROR("Connection error: ~p", [Error]),
            halt(1)
    end.

-spec mk_opts(string(), string()) -> list().
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

-spec get_host(term()) -> string().
get_host(Args) ->
    Server = maps:get(server, Args, ?DEFAULT_SERVER),
    case inet:parse_address(Server) of
        {ok, IPv4Tuple} ->
            IPv4Tuple;
        {error, einval} ->
            Server
    end.

-spec get_cert_key_paths(map()) -> {string(), string()}.
get_cert_key_paths(Args) ->
    Home = wm_utils:get_env("HOME"),
    UserCert = filename:join([Home, ".swm", "cert.pem"]),
    UserKey = filename:join([Home, ".swm", "key.pem"]),
    {Cert, Key} =
        case {filelib:is_file(UserCert), filelib:is_file(UserKey)} of
            {true, true} ->
                {UserCert, UserKey};
            _ ->
                ArgCert = maps:get(cert, Args, filename:absname(UserCert)),
                ArgKey = maps:get(key, Args, filename:absname(UserKey)),
                case {filelib:is_file(ArgCert), filelib:is_file(ArgKey)} of
                    {true, true} ->
                        {ArgCert, ArgKey};
                    _ ->
                        {"/opt/swm/spool/secure/node/cert.pem", "/opt/swm/spool/secure/node/key.pem"}
                end
        end,
    {filename:nativename(Cert), filename:nativename(Key)}.
