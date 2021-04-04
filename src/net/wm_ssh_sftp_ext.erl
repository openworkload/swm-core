-module(wm_ssh_sftp_ext).

-behaviour(ssh_server_channel).

-export([init/1, handle_msg/2, handle_ssh_msg/2, terminate/2]).
-export([command/2, subsystem_spec/0]).

-include("../lib/wm_log.hrl").

-include_lib("kernel/include/file.hrl").

-define(SSH_EXT_SUBSYSTEM, atom_to_list(?MODULE)).

%% ============================================================================
%% Module API
%% ============================================================================

-spec command(pid(), term()) -> term().
command(Pid, Command) ->
    case ssh_connection:session_channel(Pid, _Timeout = 60000) of
        {ok, ChannelId} ->
            try ssh_connection:subsystem(Pid, ChannelId, ?SSH_EXT_SUBSYSTEM, _Timeout = 60000) of
                success ->
                    case ssh_connection:send(Pid, ChannelId, term_to_binary(Command), 60000) of
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
                                            ?LOG_WARN("SSH SFTP EXT peer command '~p' execution "
                                                      "timed-out",
                                                      [Command]),
                                            {error, ssh_sftp_ext_command_timeout}
                                        end
                                end,
                            F();
                        Error ->
                            ?LOG_WARN("SSH SFTP EXT peer command '~p' execution "
                                      "error '~p'",
                                      [Command, Error]),
                            {error, ssh_sftp_ext_command_failed}
                    end;
                Otherwise ->
                    ?LOG_WARN("SSH SFTP EXT peer init error '~p'", [Otherwise]),
                    {error, ssh_sftp_ext_init_failed}
            catch
                Class:Reason ->
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

-spec subsystem_spec() -> {atom(), {atom(), [stub]}}.
subsystem_spec() ->
    {?SSH_EXT_SUBSYSTEM, {?MODULE, [stub]}}.

%% ============================================================================
%% Server callbacks
%% ============================================================================

handle_msg({ssh_channel_up, ChannelId, ConnectionManager}, State) ->
    {ok, State}.

%% We have to implement `delete_directory`, `file_size` and `md5sum` by own,
%% due ssh_sftpd don't support this commands
handle_ssh_msg({ssh_cm, ConnectionManager, {data, ChannelId, 0, Data}}, State) ->
    Result =
        case binary_to_term(Data) of
            {delete_directory, File} ->
                wm_file_utils:delete_directory(File);
            {file_size, File} ->
                wm_file_utils:get_size(File);
            {md5sum, File} ->
                case wm_file_utils:async_md5sum(File) of
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
                                        %% silently timeout
                                        %% let final receiver decide to do
                                        terminate_without_reply
                                    end
                            end,
                        F();
                    Otherwise ->
                        Otherwise
                end
        end,
    case Result of
        terminate_without_reply ->
            ?LOG_WARN("SSH SFTP EXT async_md5sum timed out, "
                      "terminate without reply to caller",
                      []),
            {stop, ChannelId, State};
        Result ->
            case ssh_connection:send(ConnectionManager, ChannelId, term_to_binary(Result)) of
                ok ->
                    ok;
                {error, closed} ->
                    ?LOG_WARN("SSH SFTP EXT peer connection closed", [])
            end,
            {stop, ChannelId, State}
    end;
handle_ssh_msg({ssh_cm, _ConnectionManager, Msg}, State) ->
    ?LOG_INFO("Got not handled ssh message ~p", [Msg]),
    {ok, State}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

%% ============================================================================
%% Implementation functions
%% ============================================================================

init(_) ->
    {ok, stub}.
