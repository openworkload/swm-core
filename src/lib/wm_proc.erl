-module(wm_proc).

-behaviour(gen_fsm).

-export([start_link/1]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, code_change/4, terminate/3]).
-export([sleeping/2, running/2, finished/2, error/2]).

-include("../../include/wm_timeouts.hrl").
-include("../../include/wm_scheduler.hrl").
-include("wm_log.hrl").

-define(SWM_EXEC_METHOD, "docker").
-define(SWM_PORTER_IN_CONTAINER, "/opt/swm/current/bin/swm-porter").

-record(mstate, {sys_pid, job, nodes = [], root, spool}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_fsm:start_link(?MODULE, Args, []).

%% ============================================================================
%% Server callbacks
%% ============================================================================

handle_sync_event(_Event, _From, State, MState) ->
    {reply, State, State, MState}.

handle_event(_Event, State, MState) ->
    {next_state, State, MState}.

handle_info({exit_status, ExitCode, _}, State, #mstate{} = MState) ->
    %TODO: get rid of this and use {completed, Exit, Signal}
    ?LOG_INFO("Scheduler exit status: ~p", [ExitCode]),
    {next_state, State, MState};
handle_info({output, BinOut, From}, State, #mstate{} = MState) ->
    Process = erlang:binary_to_term(BinOut),
    ?LOG_DEBUG("Porter output: ~p (from ~p)", [Process, From]),
    do_announce_completed(Process, MState),
    {next_state, State, MState};
handle_info({'EXIT', Proc, normal}, State, #mstate{} = MState) ->
    ?LOG_DEBUG("Process ~p has finished normally (~p)", [Proc, get_id(MState)]),
    {next_state, State, MState}.

code_change(_, State, MState, _) ->
    {ok, State, MState}.

terminate(Status, State, MState) ->
    Msg = io_lib:format("proc ~p has been terminated (status=~p, state=~p)", [get_id(MState), Status, State]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% FSM state transitions
%% ============================================================================

sleeping(activate, MState) ->
    ?LOG_DEBUG("Received 'activate' [sleeping] (~p)", [get_id(MState)]),
    MState2 = execute(MState),
    {next_state, running, MState2}.

running({started, JobID}, #mstate{} = MState) ->
    ?LOG_DEBUG("Job ~p has been started", [JobID]),
    wm_event:announce(proc_started, {JobID, node()}),
    case wm_utils:get_job_user(MState#mstate.job) of
        {ok, User} ->
            init_porter(User, MState);
        Error ->
            ?LOG_ERROR("Didn't find user for job ~p: ~p", [MState#mstate.job, Error])
    end,
    {next_state, running, MState};
running({sent, JobID}, #mstate{} = MState) ->
    ?LOG_DEBUG("Message to ~p has been sent", [JobID]),
    {next_state, running, MState};
running({{process, Process}, JobID}, #mstate{} = MState) ->
    do_check(Process, MState).

finished({{process, Process}, JobID}, #mstate{} = MState) ->
    do_check(Process, MState);
finished({completed, Process}, #mstate{} = MState) ->
    do_complete(Process, MState),
    ?LOG_DEBUG("Stopping wm_proc"),
    {stop, normal, MState}.

error({{process, Process}, JobID}, #mstate{} = MState) ->
    do_check(Process, MState).

%% ============================================================================
%% Implementation functions
%% ============================================================================

init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("Process manager has been started (~p)", [get_id(MState)]),
    wm_factory:notify_initiated(proc, get_id(MState)),
    {ok, sleeping, MState}.

parse_args([], MState) ->
    MState;
parse_args([{extra, Job} | T], MState) ->
    parse_args(T, MState#mstate{job = Job});
parse_args([{nodes, Nodes} | T], MState) ->
    parse_args(T, MState#mstate{nodes = Nodes});
parse_args([{task_id, ID} | T], MState) ->
    parse_args(T, MState#mstate{sys_pid = ID});
parse_args([{root, Root} | T], MState) ->
    parse_args(T, MState#mstate{root = Root});
parse_args([{spool, Spool} | T], MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

execute(MState) ->
    Job = MState#mstate.job,
    case wm_utils:get_job_user(Job) of
        {error, not_found} ->
            MState;
        {ok, User} ->
            Path = wm_entity:get_attr(execution_path, Job),
            ProcEnvs =
                [{"SWM_JOB_SCRIPT", Path},
                 {"SWM_STDIN_PATH", wm_entity:get_attr(job_stdin, Job)},
                 {"SWM_STDOUT_PATH", wm_entity:get_attr(job_stdout, Job)},
                 {"SWM_STDERR_PATH", wm_entity:get_attr(job_stderr, Job)},
                 {"SWM_WORK_DIR", wm_entity:get_attr(workdir, Job)},
                 {"SWM_USER_NAME", wm_entity:get_attr(name, User)}]
                ++ wm_entity:get_attr(env, Job),
            ?LOG_DEBUG("Job environment variables: ~p", [ProcEnvs]),
            Porter = get_porter_path(),
            case wm_conf:g(execution_method, {?SWM_EXEC_METHOD, string}) of
                "native" ->
                    run_native_process(Job, Porter, ProcEnvs, User),
                    MState;
                "docker" ->
                    {ok, NewJob} = wm_container:run(Job, Porter, ProcEnvs, self()),
                    MState#mstate{job = NewJob}
            end
    end.

get_porter_path() ->
    Porter1 = os:getenv("SWM_PORTER_IN_CONTAINER", ?SWM_PORTER_IN_CONTAINER),
    Porter2 = wm_conf:g(porter_path, {Porter1, string}),
    wm_utils:unroll_symlink(Porter2).

run_native_process(Job, Porter, ProcEnvs, User) ->
    WmPortArgs = [{exec, Porter ++ " -d"}],
    JobID = wm_entity:get_attr(id, Job),
    case wm_port:start_link(WmPortArgs) of
        {ok, Pid} ->
            T = wm_conf:g(proc_start_timeout, {?SWM_PROC_START_TIMEOUT, integer}),
            ProcArgs = [],
            PortOpts = [{parallelism, true}, use_stdio, exit_status, stream, binary],
            case wm_port:run(Pid, ProcArgs, ProcEnvs, PortOpts, T) of
                ok ->
                    wm_port:subscribe(Pid),
                    BinIn = prepare_porter_input(Job, User),
                    wm_port:cast(Pid, BinIn),
                    ?LOG_DEBUG("Job ~p has been started for user ~p", [JobID, User]),
                    wm_event:announce(proc_started, {JobID, node()});
                Error ->
                    ?LOG_ERROR("Could not start ~p: ~p", [Porter, Error]),
                    wm_event:announce(proc_failed, {JobID, node()})
            end;
        {error, ErrorMsg} ->
            ?LOG_ERROR("Cannot start wm_port with args ~p: ~p", [WmPortArgs, ErrorMsg])
    end.

prepare_porter_input(Job, User) ->
    UserBin = erlang:term_to_binary(User),
    UserBinSize = byte_size(UserBin),
    [Job2] = wm_utils:make_jobs_c_decodable([Job]),
    JobBin = erlang:term_to_binary(Job2),
    JobBinSize = byte_size(JobBin),
    <<?PORTER_COMMAND_RUN/integer,
      ?PORTER_DATA_TYPES_COUNT/integer,
      ?PORTER_DATA_TYPE_USERS/integer,
      UserBinSize:4/big-integer-unit:8,
      UserBin/binary,
      ?PORTER_DATA_TYPE_JOBS/integer,
      JobBinSize:4/big-integer-unit:8,
      JobBin/binary>>.

do_check(Process, MState) ->
    Pid = wm_entity:get_attr(pid, Process),
    State = wm_entity:get_attr(state, Process),
    ExitCode = wm_entity:get_attr(exitcode, Process),
    Signal = wm_entity:get_attr(signal, Process),
    ?LOG_DEBUG("Process update: pid=~p state=~p exit=~p sig=~p [~p]", [Pid, State, ExitCode, Signal, get_id(MState)]),
    case State of
        ?JOB_STATE_RUNNING ->
            {next_state, running, MState};
        ?JOB_STATE_FINISHED ->
            gen_fsm:send_event(self(), {completed, Process}),
            {next_state, finished, MState};
        ?JOB_STATE_ERROR ->
            gen_fsm:send_event(self(), {completed, Process}),
            {next_state, error, MState}
    end.

get_id(MState) ->
    MState#mstate.sys_pid.

init_porter(User, MState) ->
    JobID = wm_entity:get_attr(id, MState#mstate.job),
    ?LOG_DEBUG("Init porter for ~p", [JobID]),
    BinIn = prepare_porter_input(MState#mstate.job, User),
    ?LOG_DEBUG("Porter input size for user ~p: ~p", [User, byte_size(BinIn)]),
    wm_container:communicate(MState#mstate.job, BinIn, self()).

do_clean(Job) ->
    %TODO clean container stuff (see wm_docker:delete/3)
    ok.

do_complete(Process, MState) ->
    Exit = wm_entity:get_attr(pid, Process),
    State = wm_entity:get_attr(state, Process),
    Sig = wm_entity:get_attr(signal, Process),
    Comment = wm_entity:get_attr(comment, Process),
    JobID = wm_entity:get_attr(id, MState#mstate.job),
    ?LOG_INFO("Job ~p has finished (~p/~p/~p)", [JobID, State, Exit, Sig]),
    Job2 = wm_entity:set_attr({exitcode, Exit}, MState#mstate.job),
    Job3 = wm_entity:set_attr({signal, Sig}, Job2),
    Job4 = wm_entity:set_attr({comment, Comment}, Job3),
    Job5 = wm_entity:set_attr({state, State}, Job4),
    wm_conf:update([Job5]),
    do_announce_completed(Process, MState),
    do_clean(Job5).

do_announce_completed(Process, MState) ->
    EndTime = wm_utils:now_iso8601(without_ms),
    JobID = wm_entity:get_attr(id, MState#mstate.job),
    case wm_entity:get_attr(state, Process) of
        ?JOB_STATE_FINISHED ->
            EventData = {MState#mstate.sys_pid, {JobID, Process, EndTime, node()}},
            wm_event:announce(wm_proc_done, EventData);
        _ ->
            ok
    end.
