-module(wm_container_log).

-behaviour(gen_server).

-export([start_link/1, print/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").

-record(mstate, {spool = "" :: string(),
                 fd :: atom(),
                 logfile = "" :: string(),
                 job_id = "" :: job_id()
                }).


%% ============================================================================
%% API functions
%% ============================================================================

-spec start_link([{term(), term()}]) -> {ok, pid()} | ignore | {error, {already_started, pid()} | term()}.
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

-spec print(pid(), string()) -> ok.
print(Pid, Msg) ->
    gen_server:call(Pid, {info, Msg}).

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
init(Args) ->
    MState1 = parse_args(Args, #mstate{}),
    MState2 = make_dirs(MState1),
    MState3 = case open_disk_log(MState2) of
        {ok, MStateNew} ->
            MStateNew;
        {error, _} ->
            MState2
    end,
    {ok, MState3}.

handle_call({print, Msg}, _From, MState) ->
    {reply, disk_log:balog(MState#mstate.fd, [Msg, io_lib:nl()]), MState}.

handle_cast(_Msg, MState) ->
    {noreply, MState}.

handle_info(_Info, MState) ->
    {noreply, MState}.

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

terminate(_Reason, MState) ->
    disk_log:close(MState#mstate.fd).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{spool, SpoolDir} | T], MState) ->
    parse_args(T, MState#mstate{spool = SpoolDir});
parse_args([{job_id, JobID} | T], MState) ->
    parse_args(T, MState#mstate{job_id = JobID});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec make_dirs(#mstate{}) -> #mstate{}.
make_dirs(#mstate{job_id = JobID} = MState) ->
    LogFile = filename:join([MState#mstate.spool, "output", JobID, "container.log"]),
    filelib:ensure_dir(LogFile),
    MState#mstate{logfile = LogFile}.

-spec open_disk_log(#mstate{}) -> {ok, #mstate{}} | {error, string()}.
open_disk_log(#mstate{logfile = File, job_id = JobID} = MState) ->
    DiskOpts = [{name, JobID}, {file, File}, {format, external}],
    case disk_log:open(DiskOpts) of
        {ok, Fd} ->
            {ok, MState#mstate{fd = Fd}};
        {error, Reason} ->
            ?LOG_ERROR("Can't create ~s, ~p", [File, Reason]),
            {error, Reason};
        Error ->
            {error, Error}
    end.
