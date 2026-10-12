-module(wm_ssh_key_cb).

%% SSH key callback: user auth from CA-issued node key under secure/node,
%% verified against secure/cluster/cert.pem. Host keys stay in secure/host
%% (delegated to ssh_file). Client host-key checks pin against
%% secure/host/ssh_host_*.pub (shared via worker archive) and
%% secure/host/known_hosts (OpenSSH / provisioning TOFU).

-behaviour(ssh_server_key_api).
-behaviour(ssh_client_key_api).

-export([host_key/2, is_auth_key/3]).
-export([user_key/2, is_host_key/5, add_host_key/4]).
-export([daemon_options/1, client_options/1, client_options/2]).
-export([host_dir/1, pinned_host_key_matches/2]).

-include_lib("public_key/include/public_key.hrl").

-include("../lib/wm_log.hrl").

-define(SSH_USER, "swm").

%% ============================================================================
%% Option builders
%% ============================================================================

-spec daemon_options(string()) -> [ssh:daemon_option()].
daemon_options(Spool) ->
    HostDir = host_dir(Spool),
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
    HostDir = host_dir(Spool),
    [{user, Username},
     {auth_methods, "publickey"},
     %% Fail closed: only pinned secure/host keys or known_hosts entries.
     {silently_accept_hosts, false},
     {user_interaction, false},
     {user_dir, HostDir},
     {key_cb, {?MODULE, [{spool, normalize_spool(Spool)}]}}].

-spec host_dir(string()) -> string().
host_dir(Spool) ->
    filename:join([normalize_spool(Spool), "secure", "host"]).

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
                     boolean() | {error, term()}.
is_host_key(Key, Host, Port, Algorithm, Options) ->
    case get_spool(Options) of
        "" ->
            false;
        Spool ->
            case pinned_host_key_matches(Spool, Key) of
                true ->
                    true;
                false ->
                    HostDir = host_dir(Spool),
                    FileOpts = [{user_dir, HostDir} | Options],
                    case ssh_file:is_host_key(Key, Host, Port, Algorithm, FileOpts) of
                        true ->
                            true;
                        {error, _} = Err ->
                            Err;
                        false ->
                            false
                    end
            end
    end.

-spec add_host_key(inet:ip_address() | inet:hostname() | [inet:ip_address() | inet:hostname()],
                   inet:port_number(),
                   public_key:public_key(),
                   ssh_client_key_api:client_key_cb_options(term())) ->
                      ok | {error, term()}.
add_host_key(Host, Port, Key, Options) ->
    case get_spool(Options) of
        "" ->
            {error, spool_not_set};
        Spool ->
            HostDir = host_dir(Spool),
            ok =
                filelib:ensure_dir(
                    filename:join(HostDir, "known_hosts")),
            ssh_file:add_host_key(Host, Port, Key, [{user_dir, HostDir} | Options])
    end.

%% ============================================================================
%% Host-key pin helpers (exported for tests)
%% ============================================================================

%% @doc True when Key matches a public host key under secure/host/.
-spec pinned_host_key_matches(string(), public_key:public_key()) -> boolean().
pinned_host_key_matches(Spool, Key) ->
    HostDir = host_dir(Spool),
    case file:list_dir(HostDir) of
        {ok, Names} ->
            lists:any(fun(Name) ->
                         case lists:suffix(".pub", Name) of
                             true ->
                                 pub_file_matches(filename:join(HostDir, Name), Key);
                             false ->
                                 false
                         end
                      end,
                      Names);
        _ ->
            false
    end.

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
            case wm_cert:profile_from_der(CertDer) of
                user ->
                    {error, user_cert_not_allowed_for_node_ssh};
                _Profile ->
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
                    end
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

-spec pub_file_matches(string(), public_key:public_key()) -> boolean().
pub_file_matches(Path, Key) ->
    try
        case file:read_file(Path) of
            {ok, Bin} ->
                case ssh_file:decode(Bin, openssh_key) of
                    [{Pub, _Attrs} | _] ->
                        public_keys_equal(Pub, Key);
                    _ ->
                        false
                end;
            _ ->
                false
        end
    catch
        _:_ ->
            false
    end.

-spec public_keys_equal(public_key:public_key(), public_key:public_key()) -> boolean().
public_keys_equal(A, B) ->
    try
        ssh_file:extract_public_key(A) =:= ssh_file:extract_public_key(B)
    catch
        _:_ ->
            A =:= B
    end.
