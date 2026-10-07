-module(wm_ssh_sftpd).

%% SFTP subsystem wrapper: per-connection allowlist of user home and
%% $SWM_SPOOL/job/. Delegates protocol handling to OTP ssh_sftpd (no chroot;
%% wm_ssh_sftp_file enforces the allowlist).

-behaviour(ssh_server_channel).

-export([subsystem_spec/1]).
-export([init/1, handle_msg/2, handle_ssh_msg/2, terminate/2]).

-include("../lib/wm_log.hrl").
-include("../../include/wm_general.hrl").

-record(mstate, {inner :: term() | undefined, spool = "" :: string()}).

%% ============================================================================
%% API
%% ============================================================================

-spec subsystem_spec(string()) -> {string(), {module(), [term()]}}.
subsystem_spec(Spool) ->
    {"sftp", {?MODULE, [{spool, normalize(Spool)}]}}.

%% ============================================================================
%% ssh_server_channel
%% ============================================================================

-spec init(term()) -> {ok, term()}.
init(Options) ->
    Spool = proplists:get_value(spool, Options, ""),
    {ok, #mstate{inner = undefined, spool = normalize(Spool)}}.

-spec handle_msg(term(), term()) -> {ok, term()} | {stop, ssh:channel_id(), term()}.
handle_msg({ssh_channel_up, ChannelId, ConnectionManager} = Msg, #mstate{inner = undefined, spool = Spool} = MState) ->
    case jail_roots_from_connection(ConnectionManager, Spool) of
        {ok, Home, Roots} ->
            ?LOG_DEBUG("SFTP allowlist for connection: ~p", [Roots]),
            FileState = #{roots => Roots, cwd => Home},
            {ok, Inner0} = ssh_sftpd:init([{cwd, Home}, {file_handler, {wm_ssh_sftp_file, FileState}}]),
            case ssh_sftpd:handle_msg(Msg, Inner0) of
                {ok, Inner1} ->
                    {ok, MState#mstate{inner = Inner1}};
                {stop, ChId, Inner1} ->
                    {stop, ChId, MState#mstate{inner = Inner1}}
            end;
        {error, Reason} ->
            _ = Reason,
            ?LOG_ERROR("SFTP refused: cannot resolve allowlist (~p)", [Reason]),
            {stop, ChannelId, MState}
    end;
handle_msg(Msg, #mstate{inner = Inner} = MState) when Inner =/= undefined ->
    case ssh_sftpd:handle_msg(Msg, Inner) of
        {ok, Inner2} ->
            {ok, MState#mstate{inner = Inner2}};
        {stop, ChId, Inner2} ->
            {stop, ChId, MState#mstate{inner = Inner2}}
    end.

-spec handle_ssh_msg(ssh_connection:event(), term()) -> {ok, term()} | {stop, ssh:channel_id(), term()}.
handle_ssh_msg(_Msg, #mstate{inner = undefined} = MState) ->
    {ok, MState};
handle_ssh_msg(Msg, #mstate{inner = Inner} = MState) ->
    case ssh_sftpd:handle_ssh_msg(Msg, Inner) of
        {ok, Inner2} ->
            {ok, MState#mstate{inner = Inner2}};
        {stop, ChId, Inner2} ->
            {stop, ChId, MState#mstate{inner = Inner2}}
    end.

-spec terminate(term(), term()) -> term().
terminate(Reason, #mstate{inner = undefined}) ->
    wm_utils:terminate_msg(?MODULE, Reason);
terminate(Reason, #mstate{inner = Inner}) ->
    _ = ssh_sftpd:terminate(Reason, Inner),
    wm_utils:terminate_msg(?MODULE, Reason).

%% ============================================================================
%% Internal
%% ============================================================================

-spec jail_roots_from_connection(pid(), string()) -> {ok, string(), [string()]} | {error, term()}.
jail_roots_from_connection(ConnectionManager, Spool) ->
    case ssh:connection_info(ConnectionManager, [user]) of
        [{user, User}] when is_list(User), User =/= "" ->
            case wm_posix_utils:get_user_home(User) of
                {ok, Home} ->
                    JobRoot = filename:join([Spool, ?REMOTE_USER_DIR_NAME]),
                    {ok, Home, [Home, JobRoot]};
                Error ->
                    Error
            end;
        Other ->
            {error, {no_user, Other}}
    end.

-spec normalize(string()) -> string().
normalize(Spool) when is_list(Spool) ->
    string:trim(Spool, trailing, "/");
normalize(_) ->
    "".
