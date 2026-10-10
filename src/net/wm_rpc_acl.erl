-module(wm_rpc_acl).

%% RPC authorization for the mTLS API port (wm_session).
%% Default deny. Roles: node | admin | user | unknown.

-export([peer_uid/1, classify_uid/1, allowed/3, is_admin_acl/1, is_admin_user/1]).

-include("../lib/wm_entity.hrl").
-include("../lib/wm_log.hrl").
-include_lib("public_key/include/public_key.hrl").

-type rpc_role() :: node | admin | user | unknown.

%% ============================================================================
%% API
%% ============================================================================

%% @doc Entity UUID from the peer certificate on an SSL socket.
-spec peer_uid(ssl:sslsocket()) -> string() | unknown.
peer_uid(Socket) ->
    try
        case ssl:peercert(Socket) of
            {ok, CertBin} ->
                Cert = public_key:pkix_decode_cert(CertBin, otp),
                case wm_cert:get_uid(Cert) of
                    Uid when is_list(Uid), Uid =/= "" ->
                        Uid;
                    _ ->
                        unknown
                end;
            _ ->
                unknown
        end
    catch
        _:_ ->
            unknown
    end.

%% @doc Classify a cert UID: node table, user table (+ admin), or on-disk bootstrap.
-spec classify_uid(string() | unknown) -> rpc_role().
classify_uid(unknown) ->
    unknown;
classify_uid(Uid) when is_list(Uid) ->
    case node_uid_known(Uid) of
        true ->
            node;
        false ->
            case user_by_uid(Uid) of
                {ok, User} ->
                    case is_admin_user(User) of
                        true ->
                            admin;
                        false ->
                            user
                    end;
                not_found ->
                    case uid_matches_node_cert(Uid) of
                        true ->
                            node;
                        false ->
                            case uid_matches_spool_user_cert(Uid) of
                                true ->
                                    %% Bootstrap: admin user cert on disk before DB row exists.
                                    admin;
                                false ->
                                    unknown
                            end
                    end
            end
    end.

%% @doc Whether role may invoke Module:Fun over RPC.
-spec allowed(rpc_role(), atom(), atom()) -> boolean().
allowed(node, Module, _Fun) when is_atom(Module) ->
    lists:member(Module, node_modules());
allowed(admin, wm_admin, _Fun) ->
    true;
allowed(admin, _, _) ->
    false;
allowed(user, _, _) ->
    false;
allowed(unknown, _, _) ->
    false.

%% @doc True if acl string grants RPC admin (token "admin").
-spec is_admin_acl(term()) -> boolean().
is_admin_acl(Acl) when is_list(Acl) ->
    Tokens = string:tokens(Acl, ", \t"),
    lists:member("admin", Tokens);
is_admin_acl(_) ->
    false.

%% @doc Admin if acl says so, or name matches SWM_ADMIN_USER (legacy installs).
-spec is_admin_user(#user{}) -> boolean().
is_admin_user(User) ->
    is_admin_acl(
        wm_entity:get(acl, User))
    orelse name_is_env_admin(
               wm_entity:get(name, User)).

%% ============================================================================
%% Allowlists
%% ============================================================================

-spec node_modules() -> [atom()].
node_modules() ->
    [wm_api,
     wm_core,
     wm_compute,
     wm_pmix,
     wm_conf,
     wm_db,
     wm_data,
     wm_event,
     wm_factory,
     wm_factory_mst,
     wm_factory_commit,
     wm_factory_proc,
     wm_factory_virtres,
     wm_mst,
     wm_commit,
     wm_proc,
     wm_virtres,
     wm_pinger].

%% ============================================================================
%% Classification helpers
%% ============================================================================

-spec node_uid_known(string()) -> boolean().
node_uid_known(Uid) ->
    case safe_select(node, Uid) of
        {ok, _} ->
            true;
        _ ->
            false
    end.

-spec user_by_uid(string()) -> {ok, #user{}} | not_found.
user_by_uid(Uid) ->
    case safe_select(user, Uid) of
        {ok, User} ->
            {ok, User};
        _ ->
            not_found
    end.

-spec safe_select(atom(), string()) -> {ok, term()} | {error, term()}.
safe_select(Tab, Uid) ->
    try
        case wm_conf:select(Tab, {id, Uid}) of
            {ok, Rec} ->
                {ok, Rec};
            Other ->
                {error, Other}
        end
    catch
        _:_ ->
            {error, unavailable}
    end.

-spec name_is_env_admin(string()) -> boolean().
name_is_env_admin(Name) when is_list(Name) ->
    case os:getenv("SWM_ADMIN_USER") of
        false ->
            false;
        Name ->
            true;
        _ ->
            false
    end;
name_is_env_admin(_) ->
    false.

-spec spool_dir() -> string() | undefined.
spool_dir() ->
    case os:getenv("SWM_SPOOL") of
        false ->
            undefined;
        "" ->
            undefined;
        Spool ->
            Spool
    end.

-spec uid_matches_node_cert(string()) -> boolean().
uid_matches_node_cert(Uid) ->
    case spool_dir() of
        undefined ->
            false;
        Spool ->
            {_Ca, _Key, CertFile} = wm_utils:get_node_cert_paths(Spool),
            cert_file_uid(CertFile) =:= Uid
    end.

%% @doc Any end-entity under secure/users/<name>/cert.pem with matching UID.
-spec uid_matches_spool_user_cert(string()) -> boolean().
uid_matches_spool_user_cert(Uid) ->
    case spool_dir() of
        undefined ->
            false;
        Spool ->
            UsersDir = filename:join([Spool, "secure", "users"]),
            case file:list_dir(UsersDir) of
                {ok, Names} ->
                    lists:any(fun(Name) ->
                                 Cert = filename:join([UsersDir, Name, "cert.pem"]),
                                 cert_file_uid(Cert) =:= Uid
                              end,
                              Names);
                _ ->
                    false
            end
    end.

-spec cert_file_uid(string()) -> string() | unknown.
cert_file_uid(Path) ->
    try
        case file:read_file(Path) of
            {ok, Bin} ->
                case public_key:pem_decode(Bin) of
                    [{'Certificate', Der, _} | _] ->
                        Cert = public_key:pkix_decode_cert(Der, otp),
                        case wm_cert:get_uid(Cert) of
                            Uid when is_list(Uid), Uid =/= "" ->
                                Uid;
                            _ ->
                                unknown
                        end;
                    _ ->
                        unknown
                end;
            _ ->
                unknown
        end
    catch
        _:_ ->
            unknown
    end.
