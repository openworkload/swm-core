-module(wm_ssh_sftp_file).

%% SFTP file_handler: delegate to ssh_sftpd_file, allow only configured roots
%% (user home and $SWM_SPOOL/job/). Used with ssh_sftpd root="" so absolute
%% paths under those trees work.

-behaviour(ssh_sftpd_file_api).

-export([close/2, delete/2, del_dir/2, get_cwd/1, is_dir/2, list_dir/2, make_dir/2, make_symlink/3, open/3, position/3,
         read/3, read_link/2, read_link_info/2, read_file_info/2, rename/3, write/3, write_file_info/3]).

-include("../lib/wm_log.hrl").

-type state() :: #{roots := [string()], cwd := string()}.

%% ============================================================================
%% ssh_sftpd_file_api
%% ============================================================================

close(IoDevice, State) ->
    ssh_sftpd_file:close(IoDevice, State).

delete(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:delete(P, S) end).

del_dir(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:del_dir(P, S) end).

get_cwd(#{cwd := Cwd} = State) ->
    {{ok, Cwd}, State};
get_cwd(State) ->
    ssh_sftpd_file:get_cwd(State).

is_dir(Path, State) ->
    with_allowed_bool(Path, State, fun(P, S) -> ssh_sftpd_file:is_dir(P, S) end).

list_dir(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:list_dir(P, S) end).

make_dir(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:make_dir(P, S) end).

make_symlink(Path2, Path, State) ->
    case {allow_path(Path2, State), allow_path(Path, State)} of
        {{ok, P2}, {ok, P}} ->
            ssh_sftpd_file:make_symlink(P2, P, State);
        _ ->
            {{error, eacces}, State}
    end.

open(Path, Flags, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:open(P, Flags, S) end).

position(IoDevice, Offs, State) ->
    ssh_sftpd_file:position(IoDevice, Offs, State).

read(IoDevice, Len, State) ->
    ssh_sftpd_file:read(IoDevice, Len, State).

read_link(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:read_link(P, S) end).

read_link_info(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:read_link_info(P, S) end).

read_file_info(Path, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:read_file_info(P, S) end).

rename(Path, Path2, State) ->
    case {allow_path(Path, State), allow_path(Path2, State)} of
        {{ok, P}, {ok, P2}} ->
            ssh_sftpd_file:rename(P, P2, State);
        _ ->
            {{error, eacces}, State}
    end.

write(IoDevice, Data, State) ->
    ssh_sftpd_file:write(IoDevice, Data, State).

write_file_info(Path, Info, State) ->
    with_allowed(Path, State, fun(P, S) -> ssh_sftpd_file:write_file_info(P, Info, S) end).

%% ============================================================================
%% Internal
%% ============================================================================

-spec with_allowed(file:name(), state(), fun((file:name(), state()) -> {term(), state()})) -> {term(), state()}.
with_allowed(Path, State, Fun) ->
    case allow_path(Path, State) of
        {ok, Abs} ->
            Fun(Abs, State);
        {error, _} ->
            {{error, eacces}, State}
    end.

-spec with_allowed_bool(file:name(), state(), fun((file:name(), state()) -> {boolean(), state()})) ->
                           {boolean(), state()}.
with_allowed_bool(Path, State, Fun) ->
    case allow_path(Path, State) of
        {ok, Abs} ->
            Fun(Abs, State);
        {error, _} ->
            {false, State}
    end.

-spec allow_path(file:name(), state()) -> {ok, string()} | {error, eacces}.
allow_path(Path0, #{roots := Roots, cwd := Cwd}) ->
    Path =
        case Path0 of
            Bin when is_binary(Bin) ->
                binary_to_list(Bin);
            List when is_list(List) ->
                List
        end,
    Abs = case filename:pathtype(Path) of
              absolute ->
                  filename:absname(Path);
              _ ->
                  filename:absname(Path, Cwd)
          end,
    case lists:any(fun(Root) -> is_within_root(Root, Abs) end, Roots) of
        true ->
            {ok, Abs};
        false ->
            ?LOG_WARN("SFTP path outside allowlist rejected: ~p", [Path]),
            {error, eacces}
    end.

-spec is_within_root(string(), string()) -> boolean().
is_within_root("", _) ->
    false;
is_within_root(Root, File) ->
    lists:prefix(
        filename:split(Root), filename:split(File)).
