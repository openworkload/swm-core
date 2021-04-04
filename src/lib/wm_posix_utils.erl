-module(wm_posix_utils).

-export([get_system_uid/1, get_system_gid/1, get_current_user/0, errno/1]).

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

%% @doc Get system UID as a string by username
-spec get_system_uid(list()) -> list().
get_system_uid(Username) when is_list(Username) ->
    UID = os:cmd("id -u " ++ Username),
    string:strip(UID, right, $\n).

%% @doc Get system GID as a string by username
-spec get_system_gid(list()) -> list().
get_system_gid(Username) when is_list(Username) ->
    GID = os:cmd("id -g " ++ Username),
    string:strip(GID, right, $\n).

%% @doc Get current username
-spec get_current_user() -> list().
get_current_user() ->
    Username = os:cmd("id -n -u"),
    string:strip(Username, right, $\n).

%% @doc Convert posix error atom to human readable statement
-spec errno(atom()) -> string().
errno(Name) ->
    maps:get(Name, ?ERRNO, io_lib:format("Unkown error (POSIX.1-2001) '~p'", [Name])).
