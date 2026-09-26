-module(wm_log).

-behaviour(gen_server).

-export([start_link/1]).
-export([info/1, info/2, debug/1, debug/2, note/1, note/2, warn/1, warn/2, err/1, err/2, fatal/1, fatal/2]).
-export([access/1, access/2]).
-export([switch/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_log.hrl").

-define(NICE(Reason), lists:flatten(atom_to_list(?MODULE) ++ ": " ++ Reason)).

-record(mstate,
        {spool = "" :: string(),
         fd :: atom() | undefined,
         access_fd :: atom() | undefined,
         logf :: fun(),
         accessf :: fun(),
         logfile = "" :: string(),
         access_logfile = "" :: string()}).

%% ============================================================================
%% API functions
%% ============================================================================

%% @doc start logging server
-spec start_link([{term(), term()}]) -> {ok, pid()}.
start_link(Args) when is_list(Args) ->
    MState = parse_args(Args, #mstate{}),
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, MState, []),
    log_intro(MState),
    {ok, Pid}.

%% @doc Log formatted info message
-spec info(string(), [term()]) -> ok.
info(Format, MsgParts) ->
    info(wm_utils:format(Format, MsgParts)).

%% @doc Log info message
-spec info(string()) -> ok.
info(Msg) ->
    gen_server:call(?MODULE, {info, Msg}).

%% @doc Log formatted debug message
-spec debug(string(), [term()]) -> ok.
debug(Format, MsgParts) ->
    debug(wm_utils:format(Format, MsgParts)).

%% @doc Log debug message
-spec debug(string()) -> ok.
debug(Msg) ->
    gen_server:call(?MODULE, {debug, Msg}).

%% @doc Log formatted notification
-spec note(string(), [term()]) -> ok.
note(Format, MsgParts) ->
    note(wm_utils:format(Format, MsgParts)).

%% @doc Log notification
-spec note(string()) -> ok.
note(Msg) ->
    gen_server:call(?MODULE, {note, Msg}).

%% @doc Log formatted warning
-spec warn(string(), [term()]) -> ok.
warn(Format, MsgParts) ->
    warn(wm_utils:format(Format, MsgParts)).

%% @doc Log warning
-spec warn(string()) -> ok.
warn(Msg) ->
    gen_server:call(?MODULE, {warn, Msg}).

%% @doc Log formatted error message
-spec err(string(), [term()]) -> ok.
err(Format, MsgParts) ->
    err(wm_utils:format(Format, MsgParts)).

%% @doc Log error message
-spec err(string()) -> ok.
err(Msg) ->
    gen_server:call(?MODULE, {err, Msg}).

%% @doc Log formatted fatal error message
-spec fatal(string(), [term()]) -> ok.
fatal(Format, MsgParts) ->
    fatal(wm_utils:format(Format, MsgParts)).

%% @doc Log fatal error message
-spec fatal(string()) -> ok.
fatal(Msg) ->
    gen_server:call(?MODULE, {fatal, Msg}).

%% @doc Log formatted API access message
-spec access(string(), [term()]) -> ok.
access(Format, MsgParts) ->
    access(wm_utils:format(Format, MsgParts)).

%% @doc Log API access message to access.log
-spec access(string()) -> ok.
access(Msg) ->
    gen_server:call(?MODULE, {access, Msg}).

%% @doc forward all log messages to stdout or to file
-spec switch(atom()) -> ok.
switch(Dest) ->
    gen_server:call(?MODULE, {switch, Dest}).

%% ============================================================================
%% Callbacks
%% ============================================================================

-spec init(term()) -> {ok, term()} | {ok, term(), hibernate | infinity | non_neg_integer()} | {stop, term()} | ignore.
-spec handle_call(term(), term(), term()) ->
                     {reply, term(), term()} |
                     {reply, term(), term(), hibernate | infinity | non_neg_integer()} |
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()} |
                     {stop, term(), term(), term()}.
-spec handle_cast(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec handle_info(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec terminate(term(), term()) -> ok.
-spec code_change(term(), term(), term()) -> {ok, term()}.
init(MState) ->
    {ok, MState}.

handle_call({switch, Printer}, _From, MState) ->
    {reply, ok, set_printer(Printer, MState)};
handle_call({access, Msg}, _From, MState) ->
    Date = wm_utils:now_iso8601(with_ms),
    FMsg = [Date, "|", "ACCESS", "|", Msg, io_lib:nl()],
    Fun = MState#mstate.accessf,
    {reply, Fun(MState#mstate.access_fd, FMsg), MState};
handle_call({LogLevel, Msg}, _From, MState) ->
    Date = wm_utils:now_iso8601(with_ms),
    TypeMsg =
        case LogLevel of
            info ->
                "INFO";
            debug ->
                "DEBUG";
            note ->
                "NOTICE";
            warn ->
                "WARNING";
            err ->
                "ERROR";
            fatal ->
                "FATAL"
        end,
    FMsg = [Date, "|", TypeMsg, "|", Msg, io_lib:nl()],
    Fun = MState#mstate.logf,
    {reply, Fun(MState#mstate.fd, FMsg), MState}.

handle_cast(_Msg, MState) ->
    {noreply, MState}.

handle_info(_Info, MState) ->
    {noreply, MState}.

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

terminate(Reason, MState) ->
    ?LOG_INFO("Terminating with reason: ~p", [Reason]),
    close_disk_log(MState#mstate.fd),
    close_disk_log(MState#mstate.access_fd).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{spool, SpoolDir} | T], MState) ->
    parse_args(T, MState#mstate{spool = SpoolDir});
parse_args([{printer, PrinterName} | T], MState) ->
    parse_args(T, set_printer(PrinterName, MState));
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec make_dirs(#mstate{}) -> #mstate{}.
make_dirs(MState) ->
    {Year, _, _} = erlang:date(),
    YStr =
        lists:flatten(
            io_lib:format("~p", [Year])),
    LogDir = wm_utils:get_env("SWM_LOG_DIR"),
    MainLogFile = filename:join([LogDir, YStr]),
    SaslLogFile = filename:join([LogDir, "sasl", "sasl.log"]),
    AccessLogFile = filename:join([LogDir, "access.log"]),
    filelib:ensure_dir(MainLogFile),
    filelib:ensure_dir(SaslLogFile),
    filelib:ensure_dir(AccessLogFile),
    MState#mstate{logfile = MainLogFile, access_logfile = AccessLogFile}.

-spec open_disk_log(atom(), string()) -> {ok, atom()} | {error, string()}.
open_disk_log(Name, File) ->
    DiskOpts = [{name, Name}, {file, File}, {format, external}],
    case disk_log:open(DiskOpts) of
        {ok, Fd} ->
            {ok, Fd};
        {error, Reason} ->
            {error,
             ?NICE("Can't create "
                   ++ File
                   ++ lists:flatten(
                          io_lib:format(", ~p", [Reason])))};
        _ ->
            {error, ?NICE("Can't create " ++ File)}
    end.

-spec close_disk_log(atom() | undefined) -> ok | {error, term()}.
close_disk_log(undefined) ->
    ok;
close_disk_log(Fd) ->
    disk_log:close(Fd).

-spec access_log_name() -> atom().
access_log_name() ->
    list_to_atom(atom_to_list(node()) ++ "_access").

-spec set_printer(atom(), #mstate{}) -> #mstate{}.
set_printer(none, MState) ->
    MState#mstate{logf = fun(_, _) -> ok end, accessf = fun(_, _) -> ok end};
set_printer(stdout, MState) ->
    Out = fun(_, Msg) -> io:format(Msg) end,
    MState#mstate{logf = Out, accessf = Out};
set_printer(file, MState) ->
    MState2 = make_dirs(MState),
    case open_disk_log(node(), MState2#mstate.logfile) of
        {ok, Fd} ->
            case open_disk_log(access_log_name(), MState2#mstate.access_logfile) of
                {ok, AccessFd} ->
                    Blog = fun(LogFd, Msg) -> disk_log:blog(LogFd, Msg) end,
                    MState2#mstate{fd = Fd,
                                   access_fd = AccessFd,
                                   logf = Blog,
                                   accessf = Blog};
                {error, AccessError} ->
                    io:format("ERROR: ~p~n", [AccessError]),
                    close_disk_log(Fd),
                    MState2#mstate{logf = fun(_, _) -> ok end, accessf = fun(_, _) -> ok end}
            end;
        {error, Error} ->
            io:format("ERROR: ~p~n", [Error]),
            MState2#mstate{logf = fun(_, _) -> ok end, accessf = fun(_, _) -> ok end}
    end.

-spec log_intro(#mstate{}) -> ok.
log_intro(MState) ->
    case MState#mstate.logfile of
        [] ->
            ok;
        _ ->
            info(""),
            info("-----------------------------------------------------------------"),
            info("                    The logger has been started                  "),
            info("-----------------------------------------------------------------")
    end.
