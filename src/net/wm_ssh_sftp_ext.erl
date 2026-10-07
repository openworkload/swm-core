-module(wm_ssh_sftp_ext).

-behaviour(ssh_server_channel).

-export([init/1, handle_msg/2, handle_ssh_msg/2, terminate/2]).
-export([command/2, subsystem_spec/1]).

-include("../lib/wm_log.hrl").
-include("../../include/wm_general.hrl").

-include_lib("kernel/include/file.hrl").

-define(SSH_EXT_SUBSYSTEM, atom_to_list(?MODULE)).

-record(mstate, {roots = [] :: [string()], cwd = "" :: string(), spool = "" :: string()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec command(pid(), term()) -> term().
command(Pid, Command) ->
    case ssh_connection:session_channel(Pid, _Timeout1 = 60000) of
        {ok, ChannelId} ->
            try ssh_connection:subsystem(Pid, ChannelId, ?SSH_EXT_SUBSYSTEM, _Timeout2 = 60000) of
                success ->
                    case ssh_connection:send(Pid, ChannelId, term_to_binary(Command), _Timeout3 = 60000) of
                        ok ->
                            F = fun Receive() ->
                                        receive
                                            {ssh_cm, Pid, {data, _, _, Binary}} ->
                                                case binary_to_term(Binary) of
                                                    yield ->
                                                        Receive();
                                                    Otherwise ->
                                                        Otherwise
                                                end
                                        after 45000 ->
                                            ?LOG_WARN("SSH SFTP EXT peer command '~p' execution timed-out", [Command]),
                                            {error, ssh_sftp_ext_command_timeout}
                                        end
                                end,
                            F();
                        Error ->
                            _ = Error,
                            ?LOG_WARN("SSH SFTP EXT peer command '~p' execution error '~p'", [Command, Error]),
                            {error, ssh_sftp_ext_command_failed}
                    end;
                Otherwise ->
                    _ = Otherwise,
                    ?LOG_WARN("SSH SFTP EXT peer init error '~p'", [Otherwise]),
                    {error, ssh_sftp_ext_init_failed}
            catch
                Class:Reason ->
                    _ = {Class, Reason},
                    ?LOG_WARN("SSH SFTP EXT peer init error '~p:~p'", [Class, Reason]),
                    {error, ssh_sftp_ext_init_failed}
            after
                ok = ssh_connection:close(Pid, ChannelId),
                receive
                    {ssh_cm, Pid, {closed, _}} ->
                        ok
                after 100 ->
                    ok
                end
            end;
        Error ->
            Error
    end.

-spec subsystem_spec(string()) -> {string(), {module(), [term()]}}.
subsystem_spec(Spool) ->
    {?SSH_EXT_SUBSYSTEM, {?MODULE, [{spool, normalize(Spool)}]}}.

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init(term()) -> {ok, term()} | {ok, term(), timeout()} | {stop, term()}.
init(Options) ->
    Spool = proplists:get_value(spool, Options, ""),
    {ok, #mstate{spool = normalize(Spool)}}.

-spec handle_msg(timeout | term(), term()) -> {ok, term()} | {stop, ssh:channel_id(), term()}.
handle_msg({ssh_channel_up, ChannelId, ConnectionManager}, #mstate{spool = Spool} = MState) ->
    case jail_roots_from_connection(ConnectionManager, Spool) of
        {ok, Home, Roots} ->
            ?LOG_DEBUG("SSH SFTP EXT allowlist for connection: ~p", [Roots]),
            {ok, MState#mstate{roots = Roots, cwd = Home}};
        {error, Reason} ->
            _ = Reason,
            ?LOG_ERROR("SSH SFTP EXT refused: cannot resolve allowlist (~p)", [Reason]),
            {stop, ChannelId, MState}
    end.

%% We have to implement `delete_directory`, `file_size` and `md5sum` by own,
%% due ssh_sftpd don't support this commands
-spec handle_ssh_msg(ssh_connection:event(), term()) -> {ok, term()} | {stop, ssh:channel_id(), term()}.
handle_ssh_msg({ssh_cm, ConnectionManager, {data, ChannelId, 0, Data}}, #mstate{roots = Roots, cwd = Cwd} = MState) ->
    Result =
        case binary_to_term(Data) of
            {delete_directory, File} ->
                with_jail_path(Roots, Cwd, File, fun(Abs) -> wm_file_utils:delete_directory(Abs) end);
            {file_size, File} ->
                with_jail_path(Roots, Cwd, File, fun(Abs) -> wm_file_utils:get_size(Abs) end);
            {md5sum, File} ->
                with_jail_path(Roots,
                               Cwd,
                               File,
                               fun(Abs) ->
                                  case wm_file_utils:async_md5sum(Abs) of
                                      Pid when is_pid(Pid) ->
                                          F = fun Receive() ->
                                                      receive
                                                          yield ->
                                                              _ = ssh_connection:send(ConnectionManager,
                                                                                      ChannelId,
                                                                                      term_to_binary(yield)),
                                                              Receive();
                                                          {ok, Hash} ->
                                                              {ok, Hash}
                                                      after 30000 ->
                                                          terminate_without_reply
                                                      end
                                              end,
                                          F();
                                      Otherwise ->
                                          Otherwise
                                  end
                               end)
        end,
    case Result of
        terminate_without_reply ->
            ?LOG_WARN("SSH SFTP EXT async_md5sum timed out, terminate without reply to caller", []),
            {stop, ChannelId, MState};
        Result ->
            case ssh_connection:send(ConnectionManager, ChannelId, term_to_binary(Result)) of
                ok ->
                    ok;
                {error, closed} ->
                    ?LOG_WARN("SSH SFTP EXT peer connection closed", [])
            end,
            {stop, ChannelId, MState}
    end;
handle_ssh_msg({ssh_cm, _ConnectionManager, Msg}, MState) ->
    _ = Msg,
    ?LOG_INFO("Got not handled ssh message ~p", [Msg]),
    {ok, MState}.

-spec terminate(term(), term()) -> _.
terminate(Reason, _) ->
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

-spec with_jail_path([string()], string(), file:filename(), fun((file:filename()) -> term())) -> term().
with_jail_path(Roots, Cwd, File, Fun) ->
    case resolve_jail_path(Roots, Cwd, File) of
        {ok, Abs} ->
            Fun(Abs);
        {error, _} = Error ->
            Error
    end.

-spec resolve_jail_path([string()], string(), file:filename()) -> {ok, file:filename()} | {error, permission_denied}.
resolve_jail_path([], _Cwd, _File) ->
    {error, permission_denied};
resolve_jail_path(Roots, Cwd, File0) ->
    File =
        case File0 of
            Bin when is_binary(Bin) ->
                binary_to_list(Bin);
            List when is_list(List) ->
                List
        end,
    Abs = case filename:pathtype(File) of
              absolute ->
                  filename:absname(File);
              _ ->
                  filename:absname(File, Cwd)
          end,
    case lists:any(fun(Root) -> is_within_root(Root, Abs) end, Roots) of
        true ->
            {ok, Abs};
        false ->
            ?LOG_WARN("SSH SFTP EXT path outside allowlist rejected: ~p", [File]),
            {error, permission_denied}
    end.

-spec is_within_root(string(), string()) -> boolean().
is_within_root("", _) ->
    false;
is_within_root(Root, File) ->
    lists:prefix(
        filename:split(Root), filename:split(File)).
