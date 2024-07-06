-module(wm_proc).

-behaviour(gen_statem).

-export([start_link/1]).
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([sleeping/3, running/3, finished/3, error/3]).

-include("../../include/wm_timeouts.hrl").
-include("../../include/wm_scheduler.hrl").
-include("wm_entity.hrl").
-include("wm_log.hrl").

-define(SWM_EXEC_METHOD, "docker").
-define(SWM_PORTER_IN_CONTAINER, "/opt/swm/current/bin/swm-porter").

-record(mstate, {task_id :: string(), job_id :: job_id()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_statem:start_link(?MODULE, Args, []).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec callback_mode() -> state_functions.
-spec init(term()) ->
              {ok, atom(), term()} |
              {ok, atom(), term(), hibernate | infinity | non_neg_integer()} |
              {stop, term()} |
              ignore.
-spec code_change(term(), atom(), term(), term()) -> {ok, term()}.
-spec terminate(term(), atom(), term()) -> ok.
callback_mode() ->
    state_functions.

init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("Process manager has been started (~p)", [MState#mstate.task_id]),
    wm_factory:notify_initiated(proc, MState#mstate.task_id),
    {ok, sleeping, MState}.

code_change(_, State, MState, _) ->
    {ok, State, MState}.

terminate(Status, State, #mstate{task_id = TaskId}) ->
    Msg = io_lib:format("proc ~p has been terminated (status=~p, state=~p)", [TaskId, Status, State]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% State machine transitions
%% ============================================================================

-spec sleeping({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
sleeping(cast, activate, #mstate{task_id = TaskId} = MState) ->
    ?LOG_DEBUG("Received 'activate' [sleeping] (~p)", [TaskId]),
    execute(MState),
    {next_state, running, MState};
sleeping(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
sleeping(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec running({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
running(cast, {started, JobId}, #mstate{} = MState) ->
    ?LOG_DEBUG("Job ~p has been started", [JobId]),
    wm_event:announce(proc_started, {JobId, node()}),
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    case wm_utils:get_job_user(Job) of
        {ok, User} ->
            init_porter(User, MState);
        Error ->
            ?LOG_ERROR("Didn't find user for job ~p: ~p", [Job, Error])
    end,
    {next_state, running, MState};
running(cast, {sent, JobId}, #mstate{} = MState) ->
    ?LOG_DEBUG("Message to ~p has been sent", [JobId]),
    {next_state, running, MState};
running(cast, {{process, Process}, _JobId}, #mstate{} = MState) ->
    do_check(Process, MState);
running(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
running(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec finished({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
finished(cast, {{process, Process}, _JobId}, #mstate{} = MState) ->
    do_check(Process, MState);
finished(cast, {completed, Process}, #mstate{} = MState) ->
    do_complete(Process, MState),
    ?LOG_DEBUG("Stopping wm_proc"),
    {stop, normal, MState};
finished(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
finished(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec error({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
error(cast, {{process, Process}, _JobId}, #mstate{} = MState) ->
    do_check(Process, MState);
error(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
error(cast, Msg, MState) ->
    handle_event(Msg, ?FUNCTION_NAME, MState).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{extra, JobId} | T], MState) ->
    parse_args(T, MState#mstate{job_id = JobId});
parse_args([{task_id, TaskId} | T], MState) ->
    parse_args(T, MState#mstate{task_id = TaskId});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec execute(#mstate{}) -> ok.
execute(#mstate{job_id = JobId}) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    case wm_utils:get_job_user(Job) of
        {error, not_found} ->
            ok;
        {ok, User} ->
            Path = wm_entity:get(execution_path, Job),
            ProcEnvs =
                [{"SWM_JOB_SCRIPT", Path},
                 {"SWM_STDIN_PATH", wm_entity:get(job_stdin, Job)},
                 {"SWM_STDOUT_PATH", wm_entity:get(job_stdout, Job)},
                 {"SWM_STDERR_PATH", wm_entity:get(job_stderr, Job)},
                 {"SWM_WORK_DIR", wm_entity:get(workdir, Job)},
                 {"SWM_USER_NAME", wm_entity:get(name, User)}]
                ++ wm_entity:get(env, Job),
            ?LOG_DEBUG("Job environment variables: ~p", [ProcEnvs]),
            Porter = get_porter_path(),
            case wm_conf:g(execution_method, {?SWM_EXEC_METHOD, string}) of
                "native" ->
                    run_native_process(Job, Porter, ProcEnvs, User),
                    ok;
                "docker" ->
                    ok = ensure_workdir_exists(Job),
                    {ok, NewJob} = wm_container:run(Job, Porter, ProcEnvs, self()),
                    1 = wm_conf:update([NewJob]),
                    ok
            end
    end.

-spec ensure_workdir_exists(#job{}) -> ok | error.
ensure_workdir_exists(#job{workdir = Dir}) ->
    ?LOG_DEBUG("Ensure job working directory exists: " ++ Dir),
    case wm_file_utils:ensure_directory_exists(Dir) of
        {error, Error} ->
            ?LOG_ERROR("Can't create job working directory " ++ Dir ++ ":  " ++ Error),
            error;
        _ ->
            ok
    end.

-spec get_porter_path() -> string().
get_porter_path() ->
    Porter1 = os:getenv("SWM_PORTER_IN_CONTAINER", ?SWM_PORTER_IN_CONTAINER),
    Porter2 = wm_conf:g(porter_path, {Porter1, string}),
    wm_utils:unroll_symlink(Porter2).

-spec run_native_process(#job{}, string(), list(), #user{}) -> ok.
run_native_process(#job{id = JobId} = Job, Porter, ProcEnvs, User) ->
    WmPortArgs = [{exec, Porter ++ " -d"}],
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
                    ?LOG_DEBUG("Job ~p has been started for user ~p", [JobId, User]),
                    wm_event:announce(proc_started, {JobId, node()});
                Error ->
                    ?LOG_ERROR("Could not start ~p: ~p", [Porter, Error]),
                    wm_event:announce(proc_failed, {JobId, node()})
            end;
        {error, ErrorMsg} ->
            ?LOG_ERROR("Cannot start wm_port with args ~p: ~p", [WmPortArgs, ErrorMsg])
    end.

-spec prepare_porter_input(#job{}, #user{}) -> binary().
prepare_porter_input(Job, User) ->
    UserBin = erlang:term_to_binary(User),
    UserBinSize = byte_size(UserBin),
    JobBin = erlang:term_to_binary(Job),
    JobBinSize = byte_size(JobBin),
    <<?PORTER_COMMAND_RUN/integer,
      ?PORTER_DATA_TYPES_COUNT/integer,
      ?PORTER_DATA_TYPE_USERS/integer,
      UserBinSize:4/big-integer-unit:8,
      UserBin/binary,
      ?PORTER_DATA_TYPE_JOBS/integer,
      JobBinSize:4/big-integer-unit:8,
      JobBin/binary>>.

-spec do_check(#process{}, #mstate{}) -> #mstate{}.
do_check(Process, #mstate{task_id = TaskId} = MState) ->
    Pid = wm_entity:get(pid, Process),
    State = wm_entity:get(state, Process),
    ExitCode = wm_entity:get(exitcode, Process),
    Signal = wm_entity:get(signal, Process),
    ?LOG_DEBUG("Process update: pid=~p state=~p exit=~p sig=~p [~p]", [Pid, State, ExitCode, Signal, TaskId]),
    case State of
        ?JOB_STATE_RUNNING ->
            {next_state, running, MState};
        ?JOB_STATE_FINISHED ->
            gen_statem:cast(self(), {completed, Process}),
            {next_state, finished, MState};
        ?JOB_STATE_ERROR ->
            gen_statem:cast(self(), {completed, Process}),
            {next_state, error, MState}
    end.

-spec init_porter(#user{}, #mstate{}) -> ok.
init_porter(User, #mstate{job_id = JobId}) ->
    ?LOG_DEBUG("Init porter for ~p", [JobId]),
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    BinIn = prepare_porter_input(Job, User),
    ?LOG_DEBUG("Porter input size for user ~p: ~p", [User, byte_size(BinIn)]),
    wm_container:communicate(Job, BinIn, self()).

-spec do_complete(#process{}, #mstate{}) -> #mstate{}.
do_complete(Process, #mstate{job_id = JobId} = MState) ->
    Exit = wm_entity:get(pid, Process),
    State = wm_entity:get(state, Process),
    Sig = wm_entity:get(signal, Process),
    Comment = wm_entity:get(comment, Process),
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    ?LOG_INFO("Job ~p has finished (~p/~p/~p)", [JobId, State, Exit, Sig]),
    Job2 = wm_entity:set({exitcode, Exit}, Job),
    Job3 = wm_entity:set({signal, Sig}, Job2),
    Job4 = wm_entity:set({comment, Comment}, Job3),
    Job5 = wm_entity:set({state, State}, Job4),
    wm_conf:update([Job5]),
    ok = wm_container:clear(Job5),
    {ok, Node} = wm_self:get_node(),
    wm_conf:set_nodes_state(state_alloc, idle, [Node]),
    do_announce_completed(Process, MState).

-spec do_announce_completed(#process{}, #mstate{}) -> ok.
do_announce_completed(Process, #mstate{job_id = JobId} = MState) ->
    EndTime = wm_utils:now_iso8601(without_ms),
    case wm_entity:get(state, Process) of
        X when X == ?JOB_STATE_FINISHED orelse X == ?JOB_STATE_CANCELED ->
            EventData = {MState#mstate.task_id, {JobId, Process, EndTime, node()}},
            wm_event:announce(wm_proc_done, EventData);
        _ ->
            ok
    end.

-spec handle_event(term(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
handle_event({job_finished, Process}, StateName, #mstate{job_id = JobId} = MState) ->
    ?LOG_DEBUG("Received event that job ~p is finished, process=~p, state=~p", [JobId, Process, StateName]),
    do_complete(Process, MState),
    ?LOG_DEBUG("Job finished => exit"),
    {stop, normal, MState}.

-spec handle_info(atom(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
handle_info({exit_status, ExitCode, _}, State, #mstate{} = MState) ->
    %TODO: get rid of this and use {completed, Exit, Signal}
    ?LOG_INFO("Scheduler exit status: ~p", [ExitCode]),
    {next_state, State, MState};
handle_info({output, BinOut, From}, State, #mstate{} = MState) ->
    Process = erlang:binary_to_term(BinOut),
    ?LOG_DEBUG("Porter output: ~p (from ~p)", [Process, From]),
    do_announce_completed(Process, MState),
    {next_state, State, MState};
handle_info({'EXIT', Proc, normal}, State, #mstate{task_id = TaskId} = MState) ->
    ?LOG_DEBUG("Process ~p has finished normally (~p)", [Proc, TaskId]),
    {next_state, State, MState}.
