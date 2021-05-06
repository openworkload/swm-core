-module(wm_port).

-behaviour(gen_server).

-export([start_link/1, call/3, cast/2, subscribe/1, run/5, close/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_log.hrl").

-record(mstate, {port, exec, requestor, verbosity = debug}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

-spec run(pid(), list(), list(), list(), number()) -> ok | error.
run(WmPortPid, Args, Envs, PortOpts, Timeout) ->
    wm_utils:protected_call(WmPortPid, {run, Args, Envs, PortOpts}, Timeout).

%% @doc Subscribe to output messages from port
-spec subscribe(pid()) -> term().
subscribe(WmPortPid) ->
    gen_server:cast(WmPortPid, {subscribe, self()}).

%% @doc Send message to port and wait for a single answer
-spec call(pid(), term(), number()) -> term().
call(WmPortPid, Msg, Timeout) ->
    catch gen_server:call(WmPortPid, {call_port, self(), Msg}, Timeout),
    receive
        {output, PortOutput} ->
            {ok, PortOutput};
        {port_error, Error} ->
            {error, Error};
        Timeout ->
            {error, timeout}
    end.

%% @doc Send message to port asynchronously
-spec cast(pid(), term()) -> term().
cast(WmPortPid, Msg) ->
    gen_server:cast(WmPortPid, {cast_port, Msg}).

%% @doc Close the port
-spec close(pid()) -> term().
close(WmPortPid) ->
    gen_server:cast(WmPortPid, close_port).

%% ============================================================================
%% Server callbacks
%% ============================================================================

init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_DEBUG("Port manager has been started (~p)", [MState]),
    {ok, MState}.

handle_call({run, Args, Envs, PortOpts}, _, MState) ->
    case do_run(Args, Envs, PortOpts, MState) of
        {ok, MStateNew} ->
            {reply, ok, MStateNew};
        Error ->
            {reply, Error, MState}
    end;
handle_call({call_port, Rr, Msg}, _, #mstate{port = Port} = MState) when is_port(Port) ->
    ?LOG_DEBUG("Call port ~p", [Port]),
    {reply, port_command(Port, Msg), MState#mstate{requestor = Rr}};
handle_call({call_port, Requestor, _}, _, MState) ->
    ?LOG_ERROR("Communication from ~p failed (port is "
               "closed)",
               [Requestor]),
    Requestor ! {port_error, "Port is closed"},
    {reply, true, MState};
handle_call(Msg, From, MState) ->
    ?LOG_ERROR("Received unknown call from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast(close_port, #mstate{port = Port} = MState) ->
    true = erlang:port_close(Port),
    {noreply, MState};
handle_cast({subscribe, Subscriber}, #mstate{} = MState) ->
    {noreply, MState#mstate{requestor = Subscriber}};
handle_cast({cast_port, Msg}, #mstate{port = Port} = MState) ->
    ?LOG_DEBUG("Cast port ~p", [Port]),
    Port ! {self(), {command, Msg}},
    %true = port_command(Port, Msg),
    {noreply, MState};
handle_cast(enable, MState) ->
    ?LOG_DEBUG("Enable heavy tasks execution"),
    {noreply, MState}.

handle_info({'EXIT', Port, ExitState}, #mstate{port = Port} = MState) ->
    ?LOG_DEBUG("Port ~p has finished with status ~p", [Port, ExitState]),
    MState#mstate.requestor ! {exit_status, ExitState, self()},
    {noreply, MState};
handle_info({Port, {exit_status, ExitCode}}, #mstate{port = Port} = MState) ->
    ?LOG_DEBUG("Port ~p exit status: ~p", [Port, ExitCode]),
    MState#mstate.requestor ! {exit_status, ExitCode, self()},
    {stop, normal, MState};
handle_info({Port, {data, Data}}, #mstate{port = Port} = MState) ->
    ?LOG_DEBUG("Received message from port: ~P", [Data, 4]),
    MState#mstate.requestor ! {output, Data, self()},
    {noreply, MState}.

terminate(Reason, #mstate{port = Port} = _MState) ->
    Msg = io_lib:format("Port manager has been terminated (~w, "
                        "~p)",
                        [Reason, Port]),
    wm_utils:terminate_msg(?MODULE, Msg),
    catch port_close(Port).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation
%% ============================================================================

parse_args([], MState) ->
    MState;
parse_args([{exec, Executable} | T], MState) ->
    parse_args(T, MState#mstate{exec = Executable});
parse_args([{verbosity, V} | T], MState) ->
    parse_args(T, MState#mstate{verbosity = V});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

get_port_opts([], [], PortOpts) ->
    PortOpts;
get_port_opts([], Envs, PortOpts) ->
    [{env, Envs} | get_port_opts([], [], PortOpts)];
get_port_opts(Args, Envs, PortOpts) ->
    [{args, Args} | get_port_opts([], Envs, PortOpts)].

do_run(Args, Envs, PortOpts, MState) ->
    Executable = MState#mstate.exec,
    Opts = get_port_opts(Args, Envs, PortOpts),
    ?LOG_DEBUG("Spawn system process: ~p, opts=~w", [Executable, Opts]),
    try
        case open_port({spawn, Executable}, Opts) of
            Port when is_port(Port) ->
                {ok, MState#mstate{port = Port}};
            Error ->
                Error
        end
    catch
        error:ErrorCode ->
            Reason =
                case ErrorCode of
                    eacces ->
                        "permission denied";
                    eagain ->
                        "resource temporarily unavailable";
                    ebadf ->
                        "bad file number";
                    ebusy ->
                        "file busy";
                    edquot ->
                        "disk quota exceeded";
                    eexist ->
                        "file already exists";
                    efault ->
                        "bad address in system call argument";
                    efbig ->
                        "file too large";
                    eintr ->
                        "interrupted system call";
                    einval ->
                        "invalid argument";
                    eio ->
                        "IO error";
                    eisdir ->
                        "illegal operation on a directory";
                    eloop ->
                        "too many levels of symbolic links";
                    emfile ->
                        "too many open files";
                    emlink ->
                        "too many links";
                    enametoolong ->
                        "file name too long";
                    enfile ->
                        "file table overflow";
                    enodev ->
                        "no such device";
                    enoent ->
                        "no such file or directory";
                    enomem ->
                        "not enough memory";
                    enospc ->
                        "no space left on device";
                    enotblk ->
                        "block device required";
                    enotdir ->
                        "not a directory";
                    enotsup ->
                        "operation not supported";
                    enxio ->
                        "no such device or address";
                    eperm ->
                        "not owner";
                    epipe ->
                        "broken pipe";
                    erofs ->
                        "read-only file system";
                    espipe ->
                        "invalid seek";
                    esrch ->
                        "no such process";
                    estale ->
                        "stale remote file handle";
                    exdev ->
                        "cross-domain link";
                    Other ->
                        Other
                end,
            ?LOG_ERROR("Could not open port: ~p", [Reason]),
            ?LOG_DEBUG("Failed port args: ~p", [Args]),
            ?LOG_DEBUG("Failed port envs: ~p", [Envs]),
            ?LOG_DEBUG("Failed port opts: ~p", [Opts]),
            ?LOG_DEBUG("Failed port exec: ~s", [Executable]),
            {error, MState#mstate{port = undefined}}
    end.
