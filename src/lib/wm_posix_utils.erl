-module(wm_posix_utils).

-export([get_system_uid_gid/1, get_current_user/0, get_user_home/1, errno/1, validate_username/1]).

-define(ERRNO,
        #{eacces => "Permission denied (POSIX.1-2001).",
          eagain =>
              "Resource temporarily unavailable (may "
              "be the same value as EWOULDBLOCK) (POSIX.1-20"
              "01).",
          ebadf => "Bad file descriptor (POSIX.1-2001).",
          ebadfd => "File descriptor in bad state.",
          ebusy => "Device or resource busy (POSIX.1-2001).",
          edquot => "Disk quota exceeded (POSIX.1-2001).",
          eexist => "File exists (POSIX.1-2001).",
          efault => "Bad address (POSIX.1-2001).",
          efbig => "File too large (POSIX.1-2001).",
          eintr =>
              "Interrupted function call (POSIX.1-2001); "
              "see signal(7).",
          einval => "Invalid argument (POSIX.1-2001).",
          eio => "Input/output error (POSIX.1-2001).",
          eisdir => "Is a directory (POSIX.1-2001).",
          eloop =>
              "Too many levels of symbolic links (POSIX.1-20"
              "01).",
          emfile =>
              "Too many open files (POSIX.1-2001). "
              "Commonly caused by exceeding the RLIMIT_NOFIL"
              "E resource limit described in getrlimit(2).",
          emlink => "Too many links (POSIX.1-2001).",
          enametoolong => "Filename too long (POSIX.1-2001).",
          enfile =>
              "Too many open files in system (POSIX.1-2001). "
              "On Linux, this is probably a result "
              "of encountering the /proc/sys/fs/file-max "
              "limit (see proc(5)).",
          enodev => "No such device (POSIX.1-2001).",
          enoent =>
              "No such file or directory (POSIX.1-2001). "
              "Typically, this error results when a "
              "specified pathname does not exist, or "
              "one of the components in the directory "
              "prefix of a pathname does not exist, "
              "or the specified pathname is a dangling "
              "symbolic link.",
          enomem => "Not enough space (POSIX.1-2001).",
          enospc => "No space left on device (POSIX.1-2001).",
          enotblk => "Block device required.",
          enotdir => "Not a directory (POSIX.1-2001).",
          enotsup => "Operation not supported (POSIX.1-2001).",
          enxio => "No such device or address (POSIX.1-2001).",
          eperm => "Operation not permitted (POSIX.1-2001).",
          epipe => "Broken pipe (POSIX.1-2001).",
          eremoteio => "Remote I/O error.",
          erofs => "Read-only filesystem (POSIX.1-2001).",
          espipe => "Invalid seek (POSIX.1-2001).",
          esrch => "No such process (POSIX.1-2001).",
          estale =>
              "Stale file handle (POSIX.1-2001). This "
              "error can occur for NFS and for other "
              "filesystems.",
          exdev => "Improper link (POSIX.1-2001)."}).

%% Portable POSIX username: letter/underscore start; alnum, underscore, dot, hyphen.
-define(USERNAME_RE, "^[A-Za-z_][A-Za-z0-9_.-]*$").

%% @doc Reject empty names and shell metacharacters before any lookup.
-spec validate_username(term()) -> ok | {error, bad_username}.
validate_username(Username) when is_list(Username), Username =/= "" ->
    case re:run(Username, ?USERNAME_RE, [{capture, none}]) of
        match ->
            ok;
        nomatch ->
            {error, bad_username}
    end;
validate_username(_) ->
    {error, bad_username}.

%% @doc Get system UID and GID by username (no shell).
-spec get_system_uid_gid(list()) -> {ok, list(), list()} | {error, not_found}.
get_system_uid_gid(Username) when is_list(Username) ->
    case validate_username(Username) of
        {error, bad_username} ->
            {error, not_found};
        ok ->
            case run_argv("id", ["-u", Username]) of
                {ok, UidOut, 0} ->
                    case run_argv("id", ["-g", Username]) of
                        {ok, GidOut, 0} ->
                            UID = string:trim(UidOut, trailing, "\n"),
                            GID = string:trim(GidOut, trailing, "\n"),
                            case UID =/= "" andalso GID =/= "" of
                                true ->
                                    {ok, UID, GID};
                                false ->
                                    {error, not_found}
                            end;
                        _ ->
                            {error, not_found}
                    end;
                _ ->
                    {error, not_found}
            end
    end;
get_system_uid_gid(_) ->
    {error, not_found}.

%% @doc Get current username (fixed argv; no user-controlled input).
-spec get_current_user() -> list().
get_current_user() ->
    case run_argv("id", ["-n", "-u"]) of
        {ok, Out, 0} ->
            string:trim(Out, trailing, "\n");
        _ ->
            ""
    end.

%% @doc Resolve the home directory for an OS user (getent/passwd; no shell).
-spec get_user_home(string()) -> {ok, string()} | {error, term()}.
get_user_home(Username) when is_list(Username) ->
    case validate_username(Username) of
        {error, bad_username} = Err ->
            Err;
        ok ->
            case run_argv("getent", ["passwd", Username]) of
                {ok, Line0, 0} ->
                    Line = string:trim(Line0),
                    case string:split(Line, ":", all) of
                        [_, _, _, _, _, Home | _] when Home =/= "" ->
                            {ok, string:trim(Home, trailing, "/")};
                        _ ->
                            {error, {no_home, Username}}
                    end;
                _ ->
                    {error, {no_home, Username}}
            end
    end;
get_user_home(_) ->
    {error, bad_username}.

%% @doc Convert posix error atom to human readable statement
-spec errno(atom()) -> string().
errno(Name) ->
    maps:get(Name, ?ERRNO, io_lib:format("Unkown error (POSIX.1-2001): ~s", [Name])).

%% ============================================================================
%% Internal: argv spawn (never /bin/sh -c)
%% ============================================================================

-spec run_argv(string(), [string()]) -> {ok, string(), integer()} | {error, term()}.
run_argv(ExeName, Args) when is_list(ExeName), is_list(Args) ->
    case os:find_executable(ExeName) of
        false ->
            {error, {not_found, ExeName}};
        Exe ->
            try
                Port =
                    open_port({spawn_executable, Exe},
                              [{args, Args},
                               eof,
                               exit_status,
                               use_stdio,
                               stderr_to_stdout]),
                collect_port(Port, [])
            catch
                E:R ->
                    {error, {E, R}}
            end
    end.

-spec collect_port(port(), [string() | binary()]) -> {ok, string(), integer()} | {error, term()}.
collect_port(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_port(Port, [Data | Acc]);
        {Port, eof} ->
            Out = flatten_port_data(lists:reverse(Acc)),
            receive
                {Port, {exit_status, Status}} ->
                    safe_port_close(Port),
                    {ok, Out, Status}
            after 2000 ->
                safe_port_close(Port),
                {ok, Out, -1}
            end;
        {Port, {exit_status, Status}} ->
            Out = flatten_port_data(lists:reverse(Acc)),
            receive
                {Port, eof} ->
                    safe_port_close(Port),
                    {ok, Out, Status}
            after 2000 ->
                safe_port_close(Port),
                {ok, Out, Status}
            end
    after 10000 ->
        safe_port_close(Port),
        {error, timeout}
    end.

-spec safe_port_close(port()) -> ok.
safe_port_close(Port) ->
    try
        port_close(Port),
        ok
    catch
        _:_ ->
            ok
    end.

-spec flatten_port_data([string() | binary()]) -> string().
flatten_port_data(Chunks) ->
    lists:flatten(
        lists:map(fun (B) when is_binary(B) ->
                          binary_to_list(B);
                      (L) when is_list(L) ->
                          L
                  end,
                  Chunks)).
