-module(wm_log).

-behaviour(gen_server).

-export([start_link/1]).
-export([info/1, info/2, debug/1, debug/2, note/1, note/2, warn/1, warn/2, err/1, err/2, fatal/1, fatal/2]).
-export([switch/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_log.hrl").

-define(NICE(Reason), lists:flatten(atom_to_list(?MODULE) ++ ": " ++ Reason)).

-record(mstate, {spool = "" :: string(), fd :: atom(), logf :: fun(), logfile = "" :: string()}).

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

%% @doc forward all log messages to stdout or to file
-spec switch(atom()) -> ok.
switch(Dest) ->
    gen_server:call(?MODULE, {switch, Dest}).

%% ============================================================================
%% Callbacks
%% ============================================================================

init(MState) ->
    {ok, MState}.

handle_call({switch, Printer}, _From, MState) ->
    {reply, ok, set_printer(Printer, MState)};
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
    disk_log:close(MState#mstate.fd).

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], MState) ->
    MState;
parse_args([{spool, SpoolDir} | T], MState) ->
    parse_args(T, MState#mstate{spool = SpoolDir});
parse_args([{printer, PrinterName} | T], MState) ->
    parse_args(T, set_printer(PrinterName, MState));
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

make_dirs(MState) ->
    {Year, _, _} = erlang:date(),
    YStr =
        lists:flatten(
            io_lib:format("~p", [Year])),
    LogDir = filename:join([MState#mstate.spool, atom_to_list(node()), "log"]),
    MainLogFile = filename:join([LogDir, YStr]),
    SaslLogFile = filename:join([LogDir, "sasl", "sasl.log"]),
    filelib:ensure_dir(MainLogFile),
    filelib:ensure_dir(SaslLogFile),
    MState#mstate{logfile = MainLogFile}.

open_disk_log(MState) ->
    DiskOpts = [{name, node()}, {file, MState#mstate.logfile}, {format, external}],
    case disk_log:open(DiskOpts) of
        {ok, Fd} ->
            {ok, MState#mstate{fd = Fd}};
        {error, Reason} ->
            {error,
             ?NICE("Can't create "
                   ++ MState#mstate.logfile
                   ++ lists:flatten(
                          io_lib:format(", ~p", [Reason])))};
        _ ->
            {error, ?NICE("Can't create " ++ MState#mstate.logfile)}
    end.

set_printer(none, MState) ->
    MState#mstate{logf = fun(_, _) -> ok end};
set_printer(stdout, MState) ->
    MState#mstate{logf = fun(_, Msg) -> io:format(Msg) end};
set_printer(file, MState) ->
    MState2 = make_dirs(MState),
    case open_disk_log(MState2) of
        {ok, MState3} ->
            MState3#mstate{logf = fun(Fd, Msg) -> disk_log:blog(Fd, Msg) end};
        {error, Error} ->
            io:format("ERROR: ~p~n", [Error]),
            MState2
    end.

log_intro(MState) ->
    case MState#mstate.logfile of
        [] ->
            ok;
        _ ->
            info(""),
            info("---------------------------------------------"
                 "--------------------"),
            info("                    The logger has been "
                 "started                  "),
            info("---------------------------------------------"
                 "--------------------")
    end.
