-module(wm_ssh_key_cb).

%% SSH key callback: user auth from CA-issued node key under secure/node,
%% verified against secure/cluster/cert.pem. Host keys stay in secure/host
%% (delegated to ssh_file).

-behaviour(ssh_server_key_api).
-behaviour(ssh_client_key_api).

-export([host_key/2, is_auth_key/3]).
-export([user_key/2, is_host_key/5, add_host_key/4]).
-export([daemon_options/1, client_options/1, client_options/2]).

-include_lib("public_key/include/public_key.hrl").

-include("../lib/wm_log.hrl").

-define(SSH_USER, "swm").

%% ============================================================================
%% Option builders
%% ============================================================================

-spec daemon_options(string()) -> [ssh:daemon_option()].
daemon_options(Spool) ->
    HostDir = filename:join([Spool, "secure", "host"]),
    [{auth_methods, "publickey"},
     {shell, disabled},
     {exec, disabled},
     {system_dir, HostDir},
     {key_cb, {?MODULE, [{spool, normalize_spool(Spool)}]}}].

-spec client_options(string()) -> [ssh:client_option()].
client_options(Spool) ->
    client_options(Spool, ?SSH_USER).

-spec client_options(string(), string()) -> [ssh:client_option()].
client_options(Spool, Username) ->
    [{user, Username},
     {auth_methods, "publickey"},
     {silently_accept_hosts, true},
     {user_interaction, false},
     {key_cb, {?MODULE, [{spool, normalize_spool(Spool)}]}}].

%% ============================================================================
%% ssh_server_key_api
%% ============================================================================

-spec host_key(ssh:pubkey_alg(), ssh_server_key_api:daemon_key_cb_options(term())) ->
                  {ok, public_key:private_key()} | {error, term()}.
host_key(Algorithm, DaemonOptions) ->
    ssh_file:host_key(Algorithm, DaemonOptions).

-spec is_auth_key(public_key:public_key(), string(), ssh_server_key_api:daemon_key_cb_options(term())) -> boolean().
is_auth_key(PublicKey, _User, DaemonOptions) ->
    case get_spool(DaemonOptions) of
        "" ->
            ?LOG_ERROR("SSH is_auth_key: spool not set in key_cb options"),
            false;
        Spool ->
            case authorized_node_pubkey(Spool) of
                {ok, AuthKey} ->
                    PublicKey =:= AuthKey;
                {error, Reason} ->
                    %% Keep Reason used when TEST builds expand LOG macros to ok.
                    _ = Reason,
                    ?LOG_ERROR("SSH is_auth_key: reject key (~p)", [Reason]),
                    false
            end
    end.

%% ============================================================================
%% ssh_client_key_api
%% ============================================================================

-spec user_key(ssh:pubkey_alg(), ssh_client_key_api:client_key_cb_options(term())) ->
                  {ok, public_key:private_key()} | {error, string()}.
user_key(Algorithm, ClientOptions) ->
    case get_spool(ClientOptions) of
        "" ->
            {error, "spool not set in key_cb options"};
        Spool ->
            case load_node_private_key(Spool) of
                {ok, PrivKey} ->
                    case algorithm_matches_key(Algorithm, PrivKey) of
                        true ->
                            {ok, PrivKey};
                        false ->
                            {error,
                             lists:flatten(
                                 io_lib:format("node key does not match algorithm ~p", [Algorithm]))}
                    end;
                {error, Reason} ->
                    {error,
                     lists:flatten(
                         io_lib:format("~p", [Reason]))}
            end
    end.

-spec is_host_key(public_key:public_key(),
                  inet:ip_address() | inet:hostname() | [inet:ip_address() | inet:hostname()],
                  inet:port_number(),
                  ssh:pubkey_alg(),
                  ssh_client_key_api:client_key_cb_options(term())) ->
                     boolean().
is_host_key(_Key, _Host, _Port, _Algorithm, _Options) ->
    %% SWM internal daemons; matches prior silently_accept_hosts behaviour.
    true.

-spec add_host_key(inet:ip_address() | inet:hostname() | [inet:ip_address() | inet:hostname()],
                   inet:port_number(),
                   public_key:public_key(),
                   ssh_client_key_api:client_key_cb_options(term())) ->
                      ok | {error, term()}.
add_host_key(_Host, _Port, _Key, _Options) ->
    ok.

%% ============================================================================
%% Internal
%% ============================================================================

-spec get_spool([{atom(), term()}]) -> string().
get_spool(Options) ->
    Private = proplists:get_value(key_cb_private, Options, []),
    normalize_spool(proplists:get_value(spool, Private, "")).

-spec normalize_spool(string()) -> string().
normalize_spool(Spool) when is_list(Spool) ->
    string:trim(Spool, trailing, "/");
normalize_spool(_) ->
    "".

-spec authorized_node_pubkey(string()) -> {ok, public_key:public_key()} | {error, term()}.
authorized_node_pubkey(Spool) ->
    {CaFile, _KeyFile, CertFile} = wm_utils:get_node_cert_paths(Spool),
    case read_pem_der(CertFile) of
        {ok, CertDer} ->
            case read_pem_der(CaFile) of
                {ok, CaDer} ->
                    case public_key:pkix_path_validation(CaDer, [CertDer], []) of
                        {ok, _} ->
                            extract_cert_pubkey(CertDer);
                        {error, Reason} ->
                            {error, {ca_validation_failed, Reason}}
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

-spec load_node_private_key(string()) -> {ok, public_key:private_key()} | {error, term()}.
load_node_private_key(Spool) ->
    {_Ca, KeyFile, _Cert} = wm_utils:get_node_cert_paths(Spool),
    case file:read_file(KeyFile) of
        {ok, Bin} ->
            case public_key:pem_decode(Bin) of
                [Entry | _] ->
                    {ok, public_key:pem_entry_decode(Entry)};
                [] ->
                    {error, {empty_pem, KeyFile}}
            end;
        {error, Reason} ->
            {error, {read_key_failed, KeyFile, Reason}}
    end.

-spec read_pem_der(string()) -> {ok, binary()} | {error, term()}.
read_pem_der(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            case public_key:pem_decode(Bin) of
                [{_, Der, _} | _] ->
                    {ok, Der};
                [] ->
                    {error, {empty_pem, Path}}
            end;
        {error, Reason} ->
            {error, {read_pem_failed, Path, Reason}}
    end.

-spec extract_cert_pubkey(binary()) -> {ok, public_key:public_key()} | {error, term()}.
extract_cert_pubkey(CertDer) ->
    Dec = public_key:pkix_decode_cert(CertDer, otp),
    TBS = Dec#'OTPCertificate'.tbsCertificate,
    SPKI = TBS#'OTPTBSCertificate'.subjectPublicKeyInfo,
    {ok, SPKI#'OTPSubjectPublicKeyInfo'.subjectPublicKey}.

-spec algorithm_matches_key(ssh:pubkey_alg(), public_key:private_key()) -> boolean().
algorithm_matches_key(Alg, #'RSAPrivateKey'{}) ->
    lists:member(Alg, ['ssh-rsa', 'rsa-sha2-256', 'rsa-sha2-512']);
algorithm_matches_key(Alg, #'ECPrivateKey'{}) ->
    lists:member(Alg, ['ssh-ed25519', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521']);
algorithm_matches_key(_, _) ->
    false.
