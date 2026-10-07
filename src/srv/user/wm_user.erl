-module(wm_user).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_scheduler.hrl").
-include("../../../include/wm_general.hrl").

-record(mstate, {spool = "" :: string}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

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
    ?LOG_INFO("Load user management service"),
    process_flag(trap_exit, true),
    wm_event:subscribe(http_started, node(), ?MODULE),
    %% http_started may already have been announced while this service was
    %% still starting (suspended) — register routes if the web server is up.
    case whereis(wm_http) of
        undefined ->
            ok;
        _ ->
            handle_event(http_started, [])
    end,
    MState = parse_args(Args, #mstate{}),
    {ok, MState}.

handle_call({show, JIDs}, _From, MState) ->
    {reply, handle_request(show, JIDs, MState), MState};
handle_call({requeue, JIDs}, _From, MState) ->
    {reply, handle_request(requeue, JIDs, MState), MState};
handle_call({cancel, JIDs}, _From, MState) ->
    {reply, handle_request(cancel, JIDs, MState), MState};
handle_call({purge, Username}, _From, MState) ->
    {reply, handle_request(purge, Username, MState), MState};
handle_call({submit, JobScriptContent, Filename, Username, IpStr}, _From, MState) ->
    {reply, handle_request(submit, {JobScriptContent, Filename, Username, IpStr}, MState), MState};
handle_call({list, TabList}, _From, MState) ->
    {reply, handle_request(list, TabList, MState), MState};
handle_call({list, TabList, Limit}, _From, MState) ->
    {reply, handle_request(list, {TabList, Limit}, MState), MState};
handle_call({stdout, JobId}, _From, MState) ->
    {reply, handle_request({output, job_stdout}, JobId, MState), MState};
handle_call({stderr, JobId}, _From, MState) ->
    {reply, handle_request({output, job_stderr}, JobId, MState), MState};
handle_call(Msg, From, MState) ->
    ?LOG_DEBUG("Unknown call message from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast({event, EventType, EventData}, MState) ->
    handle_event(EventType, EventData),
    {noreply, MState};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Unknown cast message: ~p", [Msg]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason),
    wm_tcp_server:terminate(Reason, ?MODULE).

handle_info(_Info, Data) ->
    {noreply, Data}.

code_change(_OldVsn, Data, _Extra) ->
    {ok, Data}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

handle_event(http_started, _) ->
    ?LOG_INFO("Initialize user REST API resources"),
    wm_http:add_route({api, wm_user_rest}, "/user"),
    wm_http:add_route({api, wm_user_rest}, "/user/node"),
    wm_http:add_route({api, wm_user_rest}, "/user/flavor"),
    wm_http:add_route({api, wm_user_rest}, "/user/image"),
    wm_http:add_route({api, wm_user_rest}, "/user/remote"),
    wm_http:add_route({api, wm_user_rest}, "/user/job"),
    wm_http:add_route({api, wm_user_rest}, "/user/job/:id"),
    wm_http:add_route({api, wm_user_rest}, "/user/job/:id/stdout"),
    wm_http:add_route({api, wm_user_rest}, "/user/job/:id/stderr"),
    wm_http:add_route({api, wm_user_rest}, "/user/job/:id/metrics").

-spec handle_request(atom(), any(), #mstate{}) -> any().
handle_request({output, OutputType}, JobId, #mstate{spool = Spool})
    when OutputType =:= job_stdout; OutputType =:= job_stderr ->
    ?LOG_ACCESS("Job ~p has been requested: ~p", [OutputType, JobId]),
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            FullPath = job_log_path(Job, Spool, JobId, OutputType),
            Dir = filename:dirname(FullPath),
            FileName = filename:basename(FullPath),
            Stream =
                case OutputType of
                    job_stdout ->
                        stdout;
                    job_stderr ->
                        stderr
                end,
            read_output_with_tasks(Dir, FileName, FullPath, Stream);
        _ ->
            {error, "job not found"}
    end;
handle_request({output, OutputType}, JobId, #mstate{spool = Spool}) ->
    ?LOG_ACCESS("Job ~p has been requested: ~p", [OutputType, JobId]),
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            FullPath = job_log_path(Job, Spool, JobId, OutputType),
            wm_utils:read_file(FullPath, [binary]);
        _ ->
            {error, "job not found"}
    end;
handle_request(submit, Args, #mstate{spool = Spool}) ->
    ?LOG_ACCESS("Job submission has been requested: ~n~p", [Args]),
    {JobScriptContent, Filename, Username, IpStr} = Args,
    case wm_conf:select(user, {name, Username}) of
        {error, not_found} ->
            ?LOG_ERROR("User ~p not found, job submission failed", [Username]),
            R = io_lib:format("User ~p is not registred in the workload manager", [Username]),
            {string, [R]};
        {ok, User} ->
            % TODO verify user credentials using provided certificate
            JobId = wm_utils:uuid(v4),
            Cluster = wm_topology:get_subdiv(cluster),
            Job1 = wm_jobscript:parse(JobScriptContent),
            Job2 = wm_jobscript:ensure_submission_address(IpStr, Job1),
            Job3 =
                wm_entity:set([{cluster_id, wm_entity:get(id, Cluster)},
                               {state, ?JOB_STATE_QUEUED},
                               {state_details, "Submitted"},
                               {execution_path, Filename},
                               {script_content, JobScriptContent},
                               {user_id, wm_entity:get(id, User)},
                               {id, JobId},
                               {submit_time, wm_utils:now_iso8601(without_ms)},
                               {duration, 3600}],
                              Job2),
            Job4 = set_defaults(Job3, Spool),
            Job5 = ensure_request_is_full(Job4),
            1 = wm_conf:update(Job5),
            wm_scheduler:force_schedule(),
            {string, JobId}
    end;
handle_request(requeue, Args, _) ->
    ?LOG_ACCESS("Jobs requeue has been requested: ~p", [Args]),
    Results = requeue_jobs(Args, []),
    RequeuedFiltered =
        lists:filter(fun ({requeued, _}) ->
                             true;
                         (_) ->
                             false
                     end,
                     Results),
    RequeuedIds = lists:map(fun({_, ID}) -> ID end, RequeuedFiltered),
    NotFoundFiltered =
        lists:filter(fun ({not_found, _}) ->
                             true;
                         (_) ->
                             false
                     end,
                     Results),
    NotFoundIds = lists:map(fun({_, ID}) -> ID end, NotFoundFiltered),
    Msg = "Requeued: " ++ lists:join(", ", RequeuedIds) ++ "\n" ++ "Not found: " ++ lists:join(", ", NotFoundIds),
    {string, Msg};
handle_request(cancel, Args, _) ->
    ?LOG_ACCESS("Jobs cancellation has been requested: ~p", [Args]),
    Results = cancel_jobs(Args, []),
    CanceledFiltered =
        lists:filter(fun ({canceled, _}) ->
                             true;
                         (_) ->
                             false
                     end,
                     Results),
    CanceledIds = lists:map(fun({_, ID}) -> ID end, CanceledFiltered),
    NotFoundFiltered =
        lists:filter(fun ({not_found, _}) ->
                             true;
                         (_) ->
                             false
                     end,
                     Results),
    NotFoundIds = lists:map(fun({_, ID}) -> ID end, NotFoundFiltered),
    Msg = "Canceled: " ++ lists:join(", ", CanceledIds) ++ "\n" ++ "Not found: " ++ lists:join(", ", NotFoundIds),
    {string, Msg};
handle_request(purge, Username, _) ->
    ?LOG_ACCESS("Jobs purge has been requested by user ~p", [Username]),
    case wm_conf:select(user, {name, Username}) of
        {error, not_found} ->
            {string, io_lib:format("User ~s is not registered", [Username])};
        {ok, User} ->
            UserId = wm_entity:get(id, User),
            Filter =
                fun (#job{user_id = Uid, state = State}) when Uid == UserId ->
                        %% Keep running jobs; purge queued and all other non-running states.
                        State =/= ?JOB_STATE_RUNNING;
                    (_) ->
                        false
                end,
            Jobs =
                case wm_conf:select(job, Filter) of
                    {ok, List} when is_list(List) ->
                        List;
                    {error, not_found} ->
                        [];
                    Other when is_list(Other) ->
                        Other;
                    _ ->
                        []
                end,
            Results = lists:map(fun purge_one_job/1, Jobs),
            PurgedIds = [Id || {purged, Id} <- Results],
            case PurgedIds of
                [] ->
                    ok;
                _ ->
                    try
                        wm_topology:reload()
                    catch
                        _:_ ->
                            ok
                    end
            end,
            Msg = io_lib:format("Purged ~p job(s): ~s", [length(PurgedIds), string:join(PurgedIds, ", ")]),
            {string, lists:flatten(Msg)}
    end;
handle_request(list, {[flavor], Limit}, _) ->
    Nodes = wm_conf:select(node, {all, Limit}),
    lists:filter(fun(X) -> wm_entity:get(is_template, X) == true end, Nodes);
handle_request(list, {Args, Limit}, _) ->
    ?LOG_ACCESS("List of ~p entities with limit ~p has been requested", [Args, Limit]),
    F = fun(X) -> wm_conf:select(X, {all, Limit}) end,
    lists:flatten([F(X) || X <- Args]);
handle_request(list, Args, _) ->
    ?LOG_ACCESS("List of ~p entities has been requested", [Args]),
    F = fun(X) -> wm_conf:select(X, all) end,
    lists:flatten([F(X) || X <- Args]);
handle_request(show, Args, _) ->
    ?LOG_ACCESS("Job show has been requested: ~p", [Args]),
    wm_conf:select(job, Args).

-spec ensure_request_is_full(#job{}) -> #job{}.
ensure_request_is_full(Job) ->
    ResourcesOld = wm_entity:get(request, Job),
    ResourcesNew = add_missed_mandatory_request_resources(ResourcesOld),
    wm_entity:set({request, ResourcesNew}, Job).

-spec add_missed_mandatory_request_resources([#resource{}]) -> [#resource{}].
add_missed_mandatory_request_resources(Resources) ->
    Names = lists:foldl(fun(R, Acc) -> [wm_entity:get(name, R) | Acc] end, [], Resources),

    AddIfMissed =
        fun(Name, ResList, AddFun) ->
           case lists:member(Name, Names) of
               false ->
                   [AddFun() | ResList];
               true ->
                   ResList
           end
        end,

    Resources2 =
        AddIfMissed("node",
                    Resources,
                    fun() ->
                       ResNode1 = wm_entity:new(resource),
                       ResNode2 = wm_entity:set({name, "node"}, ResNode1),
                       wm_entity:set({count, 1}, ResNode2)
                    end),
    Resources3 =
        AddIfMissed("cpus",
                    Resources2,
                    fun() ->
                       ResCpu1 = wm_entity:new(resource),
                       ResCpu2 = wm_entity:set({name, "cpus"}, ResCpu1),
                       wm_entity:set({count, 1}, ResCpu2)
                    end),
    Resources3.

-spec requeue_jobs([job_id()], [{atom(), job_id()}]) -> [{atom(), job_id()}].
requeue_jobs([], Results) ->
    Results;
requeue_jobs([JobId | T], Results) ->
    Result =
        case wm_conf:select(job, {id, JobId}) of
            {ok, Job} ->
                UpdatedJob = wm_entity:set({state, ?JOB_STATE_QUEUED}, Job),
                1 = wm_conf:update([UpdatedJob]),
                wm_scheduler:force_schedule(),
                {requeued, JobId};
            _ ->
                {not_found, JobId}
        end,
    requeue_jobs(T, [Result | Results]).

-spec cancel_jobs([job_id()], [{canceled | not_found, job_id()}]) -> [{canceled | not_found, job_id()}].
cancel_jobs([], Results) ->
    Results;
cancel_jobs([JobId | T], Results) ->
    Result =
        case wm_conf:select(job, {id, JobId}) of
            {ok, Job} ->
                %% Final DMTCP/MANA checkpoint before teardown (no-op if disabled).
                JobCkpt = wm_checkpoint:checkpoint_before_cancel(Job),
                UpdatedJob = wm_entity:set({state, ?JOB_STATE_CANCELED}, JobCkpt),
                1 = wm_conf:update([UpdatedJob]),
                Process = wm_entity:set([{state, ?JOB_STATE_CANCELED}], wm_entity:new(process)),
                EndTime = wm_utils:now_iso8601(without_ms),
                wm_event:announce(job_canceled, {JobId, Process, EndTime, node()}),
                {canceled, JobId};
            _ ->
                {not_found, JobId}
        end,
    cancel_jobs(T, [Result | Results]).

-spec purge_one_job(#job{}) -> {purged, job_id()}.
purge_one_job(#job{} = Job) ->
    JobId = wm_entity:get(id, Job),
    ?LOG_DEBUG("Purge job ~p from configuration database", [JobId]),
    %% Kick off remote destroy without waiting (gate RPC must not block purge).
    case {wm_entity:get(relocatable, Job), wm_entity:get(state, Job)} of
        {true, State} when State =/= ?JOB_STATE_FINISHED, State =/= ?JOB_STATE_ERROR, State =/= ?JOB_STATE_CANCELED ->
            try
                wm_factory:new(virtres, {destroy, JobId, undefined}, [])
            catch
                _:_ ->
                    ok
            end;
        _ ->
            ok
    end,
    delete_job_timetable(JobId),
    case wm_conf:select(relocation, {job_id, JobId}) of
        {ok, Relocation} ->
            wm_conf:delete(Relocation);
        _ ->
            ok
    end,
    %% Skip per-job topology reload (~15s+ each); caller reloads once.
    try
        wm_relocator:remove_relocation_entities(Job, false)
    catch
        _:_ ->
            ok
    end,
    wm_conf:delete(Job),
    {purged, JobId}.

-spec delete_job_timetable(job_id()) -> ok.
delete_job_timetable(JobId) ->
    Filter =
        fun (#timetable{job_id = Jid}) when Jid == JobId ->
                true;
            (_) ->
                false
        end,
    case wm_conf:select(timetable, Filter) of
        {ok, Rows} when is_list(Rows) ->
            lists:foreach(fun(Row) -> wm_conf:delete(Row) end, Rows);
        List when is_list(List) ->
            lists:foreach(fun(Row) -> wm_conf:delete(Row) end, List);
        _ ->
            ok
    end.

%% Compose job-script stdout.log/stderr.log with per-task *-taskN.log files so
%% clients (swm-console) can show each task stream separately.
%% An existing empty base log (common for stderr) is success with empty body.
-spec read_output_with_tasks(string(), string(), string(), stdout | stderr) -> {ok, binary()} | {error, term()}.
read_output_with_tasks(Dir, FileName, FullPath, Stream) ->
    {BaseExists, Base} =
        case wm_utils:read_file(FullPath, [binary]) of
            {ok, Bin} when is_binary(Bin) ->
                {true, Bin};
            {ok, List} when is_list(List) ->
                {true, list_to_binary(List)};
            _ ->
                {false, <<>>}
        end,
    TaskParts = read_task_output_parts(Dir, FileName, Stream),
    case {BaseExists, Base, TaskParts} of
        {false, <<>>, []} ->
            {error, enoent};
        _ ->
            {ok, iolist_to_binary([ensure_trailing_nl(Base), TaskParts])}
    end.

-spec read_task_output_parts(string(), string(), stdout | stderr) -> iodata().
read_task_output_parts(Dir, FileName, Stream) ->
    Pattern = filename:join(Dir, task_output_glob(FileName)),
    Files = lists:sort(fun compare_task_log_files/2, filelib:wildcard(Pattern)),
    [format_task_output_section(F, Stream) || F <- Files].

-spec task_output_glob(string()) -> string().
task_output_glob(FileName) ->
    case string:split(FileName, ".", trailing) of
        [Name, Ext] ->
            Name ++ "-task*." ++ Ext;
        [Name] ->
            Name ++ "-task*"
    end.

-spec compare_task_log_files(string(), string()) -> boolean().
compare_task_log_files(A, B) ->
    task_num_from_path(A) =< task_num_from_path(B).

-spec task_num_from_path(string()) -> integer().
task_num_from_path(Path) ->
    Base = filename:basename(Path),
    case re:run(Base, "-task([0-9]+)", [{capture, all_but_first, list}]) of
        {match, [NumStr]} ->
            list_to_integer(NumStr);
        _ ->
            0
    end.

-spec format_task_output_section(string(), stdout | stderr) -> iodata().
format_task_output_section(Path, Stream) ->
    N = task_num_from_path(Path),
    Body =
        case wm_utils:read_file(Path, [binary]) of
            {ok, Bin} when is_binary(Bin) ->
                Bin;
            {ok, List} when is_list(List) ->
                list_to_binary(List);
            _ ->
                <<>>
        end,
    Label =
        case Stream of
            stdout ->
                "stdout";
            stderr ->
                "stderr"
        end,
    [<<"\n--------------------------------------------------------------------------------\n">>,
     io_lib:format("Task ~b ~s:\n", [N, Label]),
     ensure_trailing_nl(Body)].

-spec ensure_trailing_nl(binary()) -> binary().
ensure_trailing_nl(<<>>) ->
    <<>>;
ensure_trailing_nl(Bin) ->
    case binary:last(Bin) of
        $\n ->
            Bin;
        _ ->
            <<Bin/binary, $\n>>
    end.

-spec set_defaults(#job{}, string()) -> #job{}.
set_defaults(#job{workdir = []} = Job, Spool) ->
    WorkDir = default_workdir(Job),
    set_defaults(wm_entity:set({workdir, WorkDir}, Job), Spool);
set_defaults(#job{account_id = [], user_id = UserId} = Job, Spool) ->
    % If account is not specified by user during job submission then use the user's main account
    AccountId =
        case wm_conf:select(account, {admins, [UserId]}) of
            {ok, Accounts} when is_list(Accounts) ->
                %TODO Handle case: multiple accounts are administrated by same user
                wm_entity:get(id, hd(Accounts));
            {ok, Account} ->
                wm_entity:get(id, Account)
        end,
    set_defaults(wm_entity:set({account_id, AccountId}, Job), Spool);
set_defaults(Job, Spool) ->
    ensure_job_log_paths(Job, Spool).

%% Default workdir: job owner's $HOME (SFTP allowlist includes home).
-spec default_workdir(#job{}) -> string().
default_workdir(Job) ->
    case wm_utils:get_job_user(Job) of
        {ok, User} ->
            Name = wm_entity:get(name, User),
            case wm_posix_utils:get_user_home(Name) of
                {ok, Home} ->
                    Home;
                {error, _} ->
                    os:getenv("HOME", "/tmp")
            end;
        {error, _} ->
            os:getenv("HOME", "/tmp")
    end.

%% Default stdout/stderr under $SWM_SPOOL/job/<JobId>/ (absolute paths).
-spec ensure_job_log_paths(#job{}, string()) -> #job{}.
ensure_job_log_paths(#job{id = JobId} = Job, Spool) ->
    LogDir = job_log_dir(Spool, JobId),
    case wm_file_utils:ensure_directory_exists(LogDir) of
        {error, Error} ->
            ?LOG_ERROR("Can't create job log directory ~s: ~p", [LogDir, Error]);
        _ ->
            ok
    end,
    Out = abs_log_path(LogDir, wm_entity:get(job_stdout, Job), "stdout.log"),
    Err = abs_log_path(LogDir, wm_entity:get(job_stderr, Job), "stderr.log"),
    wm_entity:set([{job_stdout, Out}, {job_stderr, Err}], Job).

-spec abs_log_path(string(), string(), string()) -> string().
abs_log_path(LogDir, [], DefaultName) ->
    filename:join(LogDir, DefaultName);
abs_log_path(LogDir, Path, _DefaultName) ->
    case filename:pathtype(Path) of
        absolute ->
            Path;
        _ ->
            filename:join(LogDir, Path)
    end.

-spec job_log_dir(string(), job_id()) -> string().
job_log_dir(Spool, JobId) ->
    filename:join([string:trim(Spool, trailing, "/"), ?REMOTE_USER_DIR_NAME, JobId]).

-spec job_log_path(#job{}, string(), job_id(), job_stdout | job_stderr) -> string().
job_log_path(Job, Spool, JobId, OutputType) ->
    Path = wm_entity:get(OutputType, Job),
    LogDir = job_log_dir(Spool, JobId),
    Default =
        case OutputType of
            job_stdout ->
                "stdout.log";
            job_stderr ->
                "stderr.log"
        end,
    abs_log_path(LogDir, Path, Default).
