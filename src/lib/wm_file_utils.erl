-module(wm_file_utils).

-export([create_tar_gz/2, extract_tar_gz/2]).
-export([md5sum/1, async_md5sum/1]).
-export([create_symlink/2]).
-export([open_file/1, close_file/1, delete_file/1]).
-export([create_directory/1, list_directory/1, list_directory/2, delete_directory/1, ensure_directory_exists/1]).
-export([get_file_info/1, set_file_info/2]).
-export([get_size/1]).

-include_lib("kernel/include/file.hrl").

-spec create_tar_gz(file:filename(), [file:filename()]) -> ok | {error, file:filename(), nonempty_string()}.
create_tar_gz(File, Files) ->
    try erl_tar:open(File, [write, compressed]) of
        {ok, Td} ->
            try create_tar_gz_ll(Td, Files) of
                ok ->
                    ok;
                {error, {Filename, Reason}} ->
                    catch ok = file:delete(File),
                    {error, Filename, wm_posix_utils:errno(Reason)}
            catch
                C:R ->
                    Stacktrace = erlang:get_stacktrace(),
                    catch ok = file:delete(File),
                    erlang:raise(C, R, Stacktrace)
            after
                erl_tar:close(Td)
            end;
        {error, {Filename, Reason}} ->
            catch ok = file:delete(File),
            {error, Filename, wm_posix_utils:errno(Reason)}
    catch
        C:R ->
            Stacktrace = erlang:get_stacktrace(),
            catch ok = file:delete(File),
            erlang:raise(C, R, Stacktrace)
    end.

-spec create_tar_gz_ll(term(), [file:filename()]) -> ok | {error, {file:filename(), atom()}}.
create_tar_gz_ll(_, []) ->
    ok;
create_tar_gz_ll(Td, [File | Files]) ->
    case erl_tar:add(Td, File, filename:basename(File), []) of
        ok ->
            create_tar_gz_ll(Td, Files);
        Otherwise ->
            Otherwise
    end.

-spec extract_tar_gz(file:filename() | file:io_device(), file:filename()) ->
                        ok | {error, file:filename(), nonempty_string()}.
extract_tar_gz(File, Destination) when is_pid(File) ->
    extract_tar_gz_ll({file, File}, Destination);
extract_tar_gz(File, Destination) when is_list(File) ->
    extract_tar_gz_ll(File, Destination).

-spec extract_tar_gz_ll(file:filename() | {file, file:io_device()}, file:filename()) ->
                           ok | {error, file:filename(), nonempty_string()}.
extract_tar_gz_ll(File, Destination) ->
    case erl_tar:extract(File, [{cwd, Destination}, compressed, cooked]) of
        ok ->
            ok;
        {error, {Name, Reason}} ->
            {error, Name, wm_posix_utils:errno(Reason)}
    end.

-spec md5sum(file:filename() | file:io_device()) -> {ok, binary()} | {error, file:filename(), nonempty_string()}.
md5sum(File) when is_pid(File) ->
    {ok, 0} = file:position(File, 0),
    Stream =
        fun Loop(MD5Context) ->
                case file:read(File, 1024 * 1024) of
                    eof ->
                        crypto:hash_final(MD5Context);
                    {ok, Chunk} ->
                        Loop(crypto:hash_update(MD5Context, Chunk))
                end
        end,
    Digest = Stream(crypto:hash_init(md5)),
    {ok, list_to_binary([C || <<N:8/integer>> <= Digest, C <- io_lib:format("~.16b", [N])])};
md5sum(File) when is_list(File) ->
    case file:open(File, [read, binary, read_ahead]) of
        {ok, Fd} ->
            Hash = md5sum(Fd),
            ok = file:close(Fd),
            Hash;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec async_md5sum(file:filename() | file:io_device()) -> pid() | {error, file:filename(), nonempty_string()}.
async_md5sum(File) when is_list(File) ->
    case file:open(File, [read, binary, read_ahead]) of
        {ok, Fd} ->
            Pid = async_md5sum(Fd),
            Pid;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
async_md5sum(File) when is_pid(File) ->
    {ok, 0} = file:position(File, 0),
    Stream =
        fun Loop0(Pid, FilePid) ->
                case file:read(FilePid, 1024 * 1024) of
                    eof ->
                        Pid ! eof,
                        exit(normal);
                    {ok, Chunk} ->
                        Pid ! Chunk;
                    {error, terminated} ->
                        %% file descriptor File is terminated, nothing to do
                        terminate_without_reply
                end,
                Loop0(Pid, FilePid)
        end,
    Hasher =
        fun Loop1(Pid, MD5Context) ->
                receive
                    eof ->
                        Digest = crypto:hash_final(MD5Context),
                        List = [C || <<N:8/integer>> <= Digest, C <- io_lib:format("~.16b", [N])],
                        Pid ! {ok, list_to_binary(List)},
                        exit(normal);
                    Chunk ->
                        Pid ! yield,
                        Loop1(Pid, crypto:hash_update(MD5Context, Chunk))
                after 15000 ->
                    %% silently timeout
                    %% let final receiver decide to do
                    terminate_without_reply
                end
        end,
    Self = self(),
    HasherPid = spawn(fun() -> Hasher(Self, crypto:hash_init(md5)) end),
    spawn(fun() -> Stream(HasherPid, File) end).

-spec create_symlink(file:filename(), file:filename()) ->
                        ok | {error, {file:filename(), file:filename()}, nonempty_string()}.
create_symlink(Src, Dst) ->
    case file:make_symlink(Dst, Src) of
        ok ->
            ok;
        {error, Reason} ->
            {error, {Src, Dst}, wm_posix_utils:errno(Reason)}
    end.

-spec open_file(file:filename()) -> {ok, file:io_device()} | {error, file:filename(), nonempty_string()}.
open_file(File) ->
    case file:open(File, [read, write, binary]) of
        {ok, Fd} ->
            {ok, Fd};
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec close_file(file:io_device()) -> ok.
close_file(Fd) ->
    try
        file:sync(Fd),
        file:close(Fd)
    catch
        _:_ ->
            ignore
    end,
    ok.

-spec delete_file(file:filename()) -> ok | {error, file:filename(), nonempty_string()}.
delete_file(File) ->
    case file:delete(File) of
        ok ->
            ok;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec create_directory(file:filename()) -> ok | exist | {error, file:filename(), nonempty_string()}.
create_directory(File) ->
    case file:make_dir(File) of
        ok ->
            ok;
        {error, eexist} ->
            exist;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec ensure_directory_exists(file:filename()) -> ok | {error, nonempty_string()}.
ensure_directory_exists(Dir) ->
    case filelib:ensure_dir(Dir) of
        ok ->
            case create_directory(Dir) of
                {error, _, Msg} ->
                    {error, Msg};
                _ ->
                    ok
            end;
        {error, Reason} ->
            {error, wm_posix_utils:errno(Reason)}
    end.

-spec list_directory(file:filename()) -> {ok, [file:filename()]} | {error, file:filename(), nonempty_string()}.
list_directory(File) ->
    case file:list_dir(File) of
        {ok, Xs} ->
            {ok, Xs};
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec list_directory(file:filename(), boolean()) -> [file:filename()].
list_directory(File, false) ->
    list_directory(File);
list_directory(File, true) ->
    list_directory_ll([File], []).

-spec list_directory_ll([file:filename()], [file:filename()]) -> [file:filename()].
list_directory_ll([], Acc) ->
    Acc;
list_directory_ll([X | Xs], Acc) ->
    case filelib:is_dir(X) of
        true ->
            case file:list_dir(X) of
                {ok, Ys} ->
                    Ks = lists:foldl(fun(Y, Acc2) -> [filename:join(X, Y) | Acc2] end, [], Ys),
                    list_directory_ll(Xs, [[X | list_directory_ll(Ks, [])] | Acc]);
                {error, _Reason} ->
                    list_directory_ll(Xs, [[X] | Acc])
            end;
        false ->
            list_directory_ll(Xs, [X | Acc])
    end.

-spec delete_directory(file:filename()) -> ok | {error, file:filename(), nonempty_string()}.
delete_directory(File) ->
    delete_directory_ll([File]).

-spec delete_directory_ll([file:filename()]) -> ok | {error, file:filename(), nonempty_string()}.
delete_directory_ll([]) ->
    ok;
delete_directory_ll([X | Xs]) ->
    case filelib:is_file(X) of
        true ->
            case filelib:is_regular(X) of
                true ->
                    case file:delete(X) of
                        ok ->
                            delete_directory_ll(Xs);
                        {error, Reason} ->
                            {error, X, wm_posix_utils:errno(Reason)}
                    end;
                false ->
                    case filelib:is_dir(X) of
                        true ->
                            case file:del_dir(X) of
                                ok ->
                                    delete_directory_ll(Xs);
                                {error, eexist} ->
                                    case file:list_dir(X) of
                                        {ok, Ys} ->
                                            Ks = lists:foldl(fun(Y, Acc) -> [filename:join(X, Y) | Acc] end,
                                                             [X | Xs],
                                                             Ys),
                                            delete_directory_ll(Ks);
                                        {error, Reason} ->
                                            {error, X, wm_posix_utils:errno(Reason)}
                                    end;
                                {error, Reason} ->
                                    {error, X, wm_posix_utils:errno(Reason)}
                            end;
                        false ->
                            {error, X, wm_posix_utils:errno(eperm)}
                    end
            end;
        false ->
            {error, X, wm_posix_utils:errno(eperm)}
    end.

-spec get_file_info(file:filename()) -> {ok, #file_info{}} | {error, file:filename(), nonempty_string()}.
get_file_info(File) ->
    case file:read_link_info(File) of
        {ok, Info} ->
            {ok, Info};
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec set_file_info(file:filename(), #file_info{}) -> ok | {error, file:filename(), nonempty_string()}.
set_file_info(File, Info) ->
    case file:write_file_info(File, Info) of
        ok ->
            ok;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end.

-spec get_size(file:filename() | list()) -> {ok, pos_integer()} | {error, file:filename(), nonempty_string()}.
get_size(Files) when is_list(Files) ->
    get_size_ll(Files, 0);
get_size(File) ->
    get_size_ll([File], 0).

-spec get_size_ll([file:filename()], pos_integer()) ->
                     {ok, pos_integer()} | {error, file:filename(), nonempty_string()}.
get_size_ll([], Acc) ->
    {ok, Acc};
get_size_ll([X | Xs], Acc) ->
    case filelib:is_file(X) of
        true ->
            case filelib:is_dir(X) of
                true ->
                    case file:list_dir(X) of
                        {ok, Ys} ->
                            Ks = lists:foldl(fun(Y, Acc2) -> [filename:join(X, Y) | Acc2] end, Xs, Ys),
                            get_size_ll(Ks, Acc);
                        {error, Reason} ->
                            {error, X, wm_posix_utils:errno(Reason)}
                    end;
                false ->
                    case get_file_info(X) of
                        {ok, #file_info{size = Size}} ->
                            get_size_ll(Xs, Acc + Size);
                        Otherwise ->
                            Otherwise
                    end
            end;
        false ->
            {error, X, wm_posix_utils:errno(eperm)}
    end.
