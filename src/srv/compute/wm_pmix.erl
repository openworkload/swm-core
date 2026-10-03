-module(wm_pmix).

-behaviour(gen_server).

%% @doc PMIx session owner for compute nodes (issue #9).
%% Erlang owns lifecycle and RM policy; C++ swm-pmix links libpmix.
%% Trigger: swm-task via Porter control relay (no submit-time flag).
%% --pmix adds per-node swm-pmix + PMIX_* bootstrap; without it, plain multi-node spawn.

-export([start_link/1, ensure_started/0]).
-export([handle_porter_req/4, reply_porter/3, cancel_job/1, bootstrap_env/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_scheduler.hrl").

-record(task,
        {id :: binary(),
         job_id :: string(),
         pmix = false :: boolean(),
         cmd = [] :: [string()],
         cont_id :: string() | undefined,
         ref :: binary() | undefined,
         rank_expected = 0 :: non_neg_integer(),
         ranks_done = 0 :: non_neg_integer(),
         exitcode = undefined :: integer() | undefined}).
-record(fence_round,
        {expected = 1 :: pos_integer(),
         arrived = #{} :: #{non_neg_integer() => binary()},
         %% Local FENCE_IN ids waiting for FENCE_OUT on this node
         local_ids = [] :: [non_neg_integer()]}).
-record(mstate,
        {helpers = #{} :: map(),
         %% JobId => PMIX_SERVER_URI from local swm-pmix READY line
         server_uris = #{} :: map(),
         %% JobId => [{Key, Val}] from swm-pmix setup_fork ENV lines
         fork_envs = #{} :: map(),
         tasks = #{} :: map(),
         job_tasks = #{} :: map(),
         %% ContID => TaskId for rank container events
         cont_tasks = #{} :: map(),
         %% TaskId => address of the node that owns the swm-task (main)
         rank_reply_to = #{} :: map(),
         %% JobId => fence coordinator address (set on remotes)
         fence_leader = #{} :: map(),
         %% JobId => [Addr] all helpers participating in fence (on leader)
         fence_peers = #{} :: map(),
         %% JobId => expected contributor count
         fence_expected = #{} :: map(),
         %% JobId => #fence_round{} while collecting
         fences = #{} :: map(),
         %% Port => JobId
         helper_jobs = #{} :: map()}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()} | {error, term()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec ensure_started() -> {ok, pid()} | {error, term()}.
ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
            start_link([]);
        Pid when is_pid(Pid) ->
            {ok, Pid}
    end.

-spec handle_porter_req(string(), binary(), atom(), map()) -> ok.
handle_porter_req(JobId, Ref, Method, Args) ->
    ensure_started(),
    gen_server:cast(?MODULE, {porter_req, JobId, Ref, Method, Args}).

%% @doc Deliver a control reply back through wm_container -> Porter stdin.
-spec reply_porter(string(), binary(), term()) -> ok.
reply_porter(ContID, Ref, Msg) ->
    wm_container:send_porter_reply(ContID, Ref, Msg).

-spec cancel_job(string()) -> ok.
cancel_job(JobId) ->
    case whereis(?MODULE) of
        undefined ->
            ok;
        _ ->
            gen_server:cast(?MODULE, {cancel_job, JobId})
    end.

-spec bootstrap_env(map(), non_neg_integer()) -> [{string(), string()}].
bootstrap_env(JobMap, Rank) when is_map(JobMap) ->
    JobId = maps:get(job_id, JobMap, ""),
    Nodes = maps:get(nodes, JobMap, []),
    Nspace = "swm-" ++ JobId,
    Size = max(1, length(Nodes)),
    Uri = maps:get(server_uri, JobMap, ""),
    %% HPC-X Open MPI 4.x defaults to ess_singleton unless a scheduler schizo
    %% declares direct-launch. FLUX_JOB_ID selects schizo_flux -> ess=pmi so
    %% MPI_Init attaches to swm-pmix and runs the collecting fence.
    %% PMIX_MCA_psec=none: TCP has no SO_PEERCRED (native auth hangs/fails).
    Base =
        [{"PMIX_NAMESPACE", Nspace},
         {"PMIX_RANK", integer_to_list(Rank)},
         {"PMIX_JOB_SIZE", integer_to_list(Size)},
         {"PMIX_LOCAL_SIZE", "1"},
         {"PMIX_SECURITY_MODE", "none"},
         {"PMIX_MCA_psec", "none"},
         {"SWM_PMIX_NSPACE", Nspace},
         {"SWM_PMIX_RANK", integer_to_list(Rank)},
         {"OMPI_COMM_WORLD_RANK", integer_to_list(Rank)},
         {"OMPI_COMM_WORLD_SIZE", integer_to_list(Size)},
         {"OMPI_COMM_WORLD_LOCAL_RANK", "0"},
         {"OMPI_COMM_WORLD_LOCAL_SIZE", "1"},
         {"OMPI_UNIVERSE_SIZE", integer_to_list(Size)},
         {"OMPI_APP_CTX_NUM_PROCS", integer_to_list(Size)},
         {"OMPI_MCA_ess", "pmi"},
         {"OMPI_MCA_orte_ess_num_procs", integer_to_list(Size)},
         {"OMPI_MCA_plm", "^rsh"},
         {"OMPI_MCA_hwloc_base_binding_policy", "none"},
         {"FLUX_JOB_ID", "swm-" ++ JobId}],
    case Uri of
        "" ->
            Base;
        _ ->
            [{"PMIX_SERVER_URI", Uri} | Base]
    end.

%% ============================================================================
%% gen_server
%% ============================================================================

-spec init(term()) -> {ok, #mstate{}}.
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
init(_Args) ->
    process_flag(trap_exit, true),
    ?LOG_INFO("PMIx session service started"),
    {ok, #mstate{}}.

handle_call(_Msg, _From, MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast({porter_req, JobId, Ref, Method, Args}, MState) ->
    {noreply, do_porter_req(JobId, Ref, Method, Args, MState)};
handle_cast({cancel_job, JobId}, MState) ->
    {noreply, do_cancel_job(JobId, MState)};
%% Remote nodes receive this via wm_api:cast_self/2 (module = caller = wm_pmix).
%% Job + ReplyTo are included so compute nodes can finish ranks without a local task.
handle_cast({pmix_start_rank, JobId, TaskId, Rank, Cmd, PmixEnv, Job, ReplyTo}, MState) ->
    MS1 = remember_rank_reply_to(TaskId, ReplyTo, MState),
    MS2 = MS1#mstate{fence_leader = maps:put(JobId, ReplyTo, MS1#mstate.fence_leader)},
    {noreply, do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, Job, MS2)};
handle_cast({pmix_start_rank, JobId, TaskId, Rank, Cmd, PmixEnv, Job}, MState) ->
    {noreply, do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, Job, MState)};
%% Older 6-tuple casts (no Job): resolve from local DB if present.
handle_cast({pmix_start_rank, JobId, TaskId, Rank, Cmd, PmixEnv}, MState) ->
    {noreply, do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, undefined, MState)};
handle_cast({start_rank_local, JobId, TaskId, Rank, Cmd, PmixEnv}, MState) ->
    {noreply, do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, undefined, MState)};
handle_cast({rank_done, TaskId, ExitCode}, MState) ->
    {noreply, rank_finished(TaskId, ExitCode, MState)};
%% Cross-node fence: remotes forward contribs to the leader; leader broadcasts result.
handle_cast({pmix_fence_contrib, JobId, ContribId, Data, FromAddr}, MState) ->
    {noreply, on_fence_contrib(JobId, ContribId, Data, FromAddr, false, undefined, MState)};
handle_cast({pmix_fence_result, JobId, Status, Aggregated}, MState) ->
    {noreply, apply_fence_result(JobId, Status, Aggregated, MState)};
handle_cast({started, JobId}, MState) ->
    ?LOG_DEBUG("Rank container started for job ~p", [JobId]),
    {noreply, MState};
handle_cast({sent, JobId}, MState) ->
    ?LOG_DEBUG("Rank Porter input sent for job ~p", [JobId]),
    {noreply, MState};
handle_cast({{process, Process}, JobId}, MState) ->
    {noreply, on_rank_process(JobId, Process, MState)};
handle_cast({{porter_metrics, Map}, JobId}, MState) when is_map(Map) ->
    deliver_job_metrics(JobId, Map, MState),
    {noreply, MState};
handle_cast({job_metrics, JobId, Map, Node}, MState) ->
    %% Forwarded from a helper node to the job main (same pattern as rank_done).
    gen_server:cast(wm_compute, {job_metrics, JobId, Map, Node}),
    {noreply, MState};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("wm_pmix unhandled cast: ~p", [Msg]),
    {noreply, MState}.

handle_info({'EXIT', Port, Reason},
            #mstate{helpers = Helpers,
                    server_uris = Uris,
                    fork_envs = ForkEnvs,
                    helper_jobs = HelperJobs,
                    fences = Fences,
                    fence_expected = FenceExp,
                    fence_peers = FencePeers,
                    fence_leader = FenceLeader} =
                MState)
    when is_port(Port) ->
    ?LOG_DEBUG("swm-pmix helper port exited: ~p", [Reason]),
    JobIds = [J || {J, P} <- maps:to_list(Helpers), P =:= Port],
    Helpers2 = maps:filter(fun(_, P) -> P =/= Port end, Helpers),
    HelperJobs2 = maps:filter(fun(P, _) -> P =/= Port end, HelperJobs),
    Uris2 = lists:foldl(fun(J, Acc) -> maps:remove(J, Acc) end, Uris, JobIds),
    Fork2 = lists:foldl(fun(J, Acc) -> maps:remove(J, Acc) end, ForkEnvs, JobIds),
    Fences2 = lists:foldl(fun(J, Acc) -> maps:remove(J, Acc) end, Fences, JobIds),
    FenceExp2 = lists:foldl(fun(J, Acc) -> maps:remove(J, Acc) end, FenceExp, JobIds),
    FencePeers2 = lists:foldl(fun(J, Acc) -> maps:remove(J, Acc) end, FencePeers, JobIds),
    FenceLeader2 = lists:foldl(fun(J, Acc) -> maps:remove(J, Acc) end, FenceLeader, JobIds),
    {noreply,
     MState#mstate{helpers = Helpers2,
                   helper_jobs = HelperJobs2,
                   server_uris = Uris2,
                   fork_envs = Fork2,
                   fences = Fences2,
                   fence_expected = FenceExp2,
                   fence_peers = FencePeers2,
                   fence_leader = FenceLeader2}};
handle_info({Port, {data, {eol, Line}}}, #mstate{} = MState) when is_port(Port) ->
    {noreply, on_helper_line(Port, line_to_list(Line), MState)};
handle_info({Port, {data, {noeol, Line}}}, #mstate{} = MState) when is_port(Port) ->
    {noreply, on_helper_line(Port, line_to_list(Line), MState)};
handle_info({Port, {data, Data}}, #mstate{} = MState) when is_port(Port) ->
    {noreply, on_helper_line(Port, line_to_list(Data), MState)};
handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, #mstate{helpers = Helpers}) ->
    maps:foreach(fun (_, Port) when is_port(Port) ->
                         safe_port_cmd(Port, <<"STOP\n">>),
                         safe_port_close(Port);
                     (_, _) ->
                         ok
                 end,
                 Helpers),
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Internal
%% ============================================================================

-spec safe_port_cmd(port(), iodata()) -> ok.
safe_port_cmd(Port, Data) ->
    try
        port_command(Port, Data),
        ok
    catch
        _:_ ->
            ok
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

-spec do_porter_req(string(), binary(), atom(), map(), #mstate{}) -> #mstate{}.
do_porter_req(JobId, Ref, spawn_task, Args, MState) ->
    ContID = maps:get(cont_id, Args, "swmjob-" ++ JobId),
    Pmix = truthy(maps:get(pmix, Args, false)),
    Cmd = normalize_cmd(maps:get(cmd, Args, [])),
    TaskId = list_to_binary(wm_utils:uuid(v4)),
    reply_porter(ContID, Ref, {ok, TaskId}),
    Task =
        #task{id = TaskId,
              job_id = JobId,
              pmix = Pmix,
              cmd = Cmd,
              cont_id = ContID,
              ref = Ref},
    MState1 = store_task(Task, MState),
    case Pmix of
        true ->
            spawn_pmix_task(Task, MState1);
        false ->
            %% Plain SPAWN (swm-task without --pmix): one container per node, no PMIx.
            spawn_plain_task(Task, MState1)
    end;
do_porter_req(_JobId, Ref, task_status, Args, MState) ->
    ContID = maps:get(cont_id, Args, ""),
    TaskId = maps:get(task_id, Args, <<>>),
    Msg = case maps:get(TaskId, MState#mstate.tasks, undefined) of
              undefined ->
                  {error, not_found};
              #task{exitcode = undefined} ->
                  {ok, running};
              #task{exitcode = Code} ->
                  {ok, {done, Code}}
          end,
    reply_porter(ContID, Ref, Msg),
    MState;
do_porter_req(JobId, Ref, cancel_task, Args, MState) ->
    ContID = maps:get(cont_id, Args, ""),
    TaskId = maps:get(task_id, Args, <<>>),
    MState2 = do_cancel_task(JobId, TaskId, MState),
    reply_porter(ContID, Ref, {ok, canceled}),
    MState2;
do_porter_req(_JobId, Ref, Method, Args, MState) ->
    ContID = maps:get(cont_id, Args, ""),
    reply_porter(ContID, Ref, {error, {unknown_method, Method}}),
    MState.

-spec truthy(term()) -> boolean().
truthy(true) ->
    true;
truthy(<<"true">>) ->
    true;
truthy("true") ->
    true;
truthy(_) ->
    false.

-spec normalize_cmd(term()) -> [string()].
normalize_cmd(Cmd) when is_list(Cmd) ->
    case Cmd of
        [] ->
            [];
        [H | _] when is_integer(H) ->
            [Cmd];
        _ ->
            [case C of
                 B when is_binary(B) ->
                     binary_to_list(B);
                 L when is_list(L) ->
                     L;
                 O ->
                     lists:flatten(
                         io_lib:format("~p", [O]))
             end
             || C <- Cmd]
    end;
normalize_cmd(Bin) when is_binary(Bin) ->
    [binary_to_list(Bin)];
normalize_cmd(_) ->
    [].

-spec store_task(#task{}, #mstate{}) -> #mstate{}.
store_task(#task{id = TaskId, job_id = JobId} = Task, #mstate{tasks = Tasks, job_tasks = JT} = MState) ->
    Tasks2 = maps:put(TaskId, Task, Tasks),
    Ids = maps:get(JobId, JT, []),
    JT2 = maps:put(JobId, [TaskId | Ids], JT),
    MState#mstate{tasks = Tasks2, job_tasks = JT2}.

-spec spawn_pmix_task(#task{}, #mstate{}) -> #mstate{}.
spawn_pmix_task(#task{job_id = JobId} = Task, MState) ->
    MState1 = ensure_helper(JobId, MState),
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            NodeIds =
                wm_utils:order_node_ids_main_first(
                    wm_entity:get(nodes, Job)),
            N = length(NodeIds),
            %% Main-node helper: register job size with local rank 0.
            MState2 = maybe_register_nspace(JobId, N, 0, MState1),
            launch_ranks(Task#task{rank_expected = N}, NodeIds, true, Job, MState2);
        _ ->
            finish_task(Task#task.id, 1, "job not found", MState1)
    end.

-spec spawn_plain_task(#task{}, #mstate{}) -> #mstate{}.
spawn_plain_task(#task{job_id = JobId} = Task, MState) ->
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            NodeIds =
                wm_utils:order_node_ids_main_first(
                    wm_entity:get(nodes, Job)),
            launch_ranks(Task#task{rank_expected = length(NodeIds)}, NodeIds, false, Job, MState);
        _ ->
            finish_task(Task#task.id, 1, "job not found", MState)
    end.

-spec ensure_helper(string(), #mstate{}) -> #mstate{}.
ensure_helper(JobId,
              #mstate{helpers = Helpers,
                      server_uris = Uris,
                      fork_envs = ForkEnvs,
                      helper_jobs = HelperJobs} =
                  MState) ->
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            MState;
        _ ->
            case start_swm_pmix(JobId) of
                {ok, Port, Uri, ForkEnv} ->
                    ?LOG_INFO("swm-pmix ready for job ~p uri=~s (~b fork env vars)", [JobId, Uri, length(ForkEnv)]),
                    MState#mstate{helpers = maps:put(JobId, Port, Helpers),
                                  helper_jobs = maps:put(Port, JobId, HelperJobs),
                                  server_uris = maps:put(JobId, Uri, Uris),
                                  fork_envs = maps:put(JobId, ForkEnv, ForkEnvs)};
                {error, Reason} ->
                    ?LOG_ERROR("Failed to start swm-pmix for job ~p: ~p", [JobId, Reason]),
                    MState
            end
    end.

-spec maybe_register_nspace(string(), non_neg_integer(), non_neg_integer(), #mstate{}) -> #mstate{}.
maybe_register_nspace(JobId, N, Rank, #mstate{helpers = Helpers, fence_expected = FE} = MState) ->
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            %% 1 rank/node: REGISTER <job_size> 1 <rank>
            Cmd = list_to_binary(io_lib:format("REGISTER ~b 1 ~b~n", [max(1, N), Rank])),
            safe_port_cmd(Port, Cmd),
            MState#mstate{fence_expected = maps:put(JobId, max(1, N), FE)};
        _ ->
            MState
    end.

-spec start_swm_pmix(string()) -> {ok, port(), string(), [{string(), string()}]} | {error, term()}.
start_swm_pmix(JobId) ->
    Exec = get_swm_pmix_path(),
    case filelib:is_file(Exec) of
        false ->
            {error, {not_found, Exec}};
        true ->
            try
                Port =
                    open_port({spawn_executable, Exec},
                              [{args, ["--job-id", JobId]},
                               {env, pmix_port_env(JobId)},
                               binary,
                               exit_status,
                               use_stdio,
                               stderr_to_stdout,
                               %% Fence modex blobs are base64 on one line.
                               {line, 262144}]),
                case wait_pmix_ready(Port, 10000) of
                    {ok, Uri, ForkEnv} ->
                        {ok, Port, Uri, ForkEnv};
                    {error, Reason} ->
                        safe_port_close(Port),
                        {error, Reason}
                end
            catch
                E:R ->
                    {error, {E, R}}
            end
    end.

%% Job user name for swm-pmix register_client (root helper, app runs as user).
-spec job_user_name(string()) -> string().
job_user_name(JobId) ->
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            case wm_utils:get_job_user(Job) of
                {ok, User} ->
                    wm_entity:get(name, User);
                _ ->
                    ""
            end;
        _ ->
            ""
    end.

%% Prefer release-bundled libpmix.so.2 (see c_src/pmix/Makefile / rebar overlay).
%% Note: swm-pmix uses DT_RPATH=$ORIGIN/../lib, so the bundled lib wins over
%% LD_LIBRARY_PATH; keep the release lib ABI-matched to the binary (OpenPMIx 4.2+).
-spec pmix_port_env(string()) -> [{string(), string()}].
pmix_port_env(JobId) ->
    ReleaseLib =
        filename:join(
            filename:dirname(
                filename:dirname(get_swm_pmix_path())),
            "lib"),
    Candidates =
        ["/opt/pmix/4.2.9/lib",
         "/opt/pmix/lib",
         case filelib:is_dir(ReleaseLib) of
             true ->
                 filename:absname(ReleaseLib);
             false ->
                 ""
         end],
    LibDirs =
        [D
         || D <- Candidates,
            is_list(D),
            D =/= "",
            filelib:is_file(
                filename:join(D, "libpmix.so.2"))],
    Prefix = string:join(LibDirs, ":"),
    Ld = case {Prefix, os:getenv("LD_LIBRARY_PATH")} of
             {"", false} ->
                 [];
             {"", Old} ->
                 [{"LD_LIBRARY_PATH", Old}];
             {Dir, false} ->
                 [{"LD_LIBRARY_PATH", Dir}];
             {Dir, Old} ->
                 [{"LD_LIBRARY_PATH", Dir ++ ":" ++ Old}]
         end,
    Psec = [{"PMIX_MCA_psec", "none"}],
    PmixPrefix =
        case filelib:is_dir("/opt/pmix/4.2.9") of
            true ->
                [{"PMIX_PREFIX", "/opt/pmix/4.2.9"}];
            false ->
                []
        end,
    JobUser =
        case job_user_name(JobId) of
            "" ->
                [];
            Name ->
                [{"SWM_JOB_USER", Name}]
        end,
    [{"SWM_JOB_ID", JobId} | JobUser ++ Psec ++ PmixPrefix ++ Ld].

-spec wait_pmix_ready(port(), non_neg_integer()) -> {ok, string(), [{string(), string()}]} | {error, term()}.
wait_pmix_ready(Port, Timeout) ->
    case recv_port_line(Port, Timeout) of
        {ok, Line} ->
            case parse_ready_line(Line) of
                {ok, Uri} ->
                    case collect_fork_env(Port, Timeout, []) of
                        {ok, ForkEnv} ->
                            {ok, Uri, ForkEnv};
                        {error, _} = Err ->
                            Err
                    end;
                skip ->
                    wait_pmix_ready(Port, Timeout)
            end;
        {error, _} = Err ->
            Err
    end.

-spec collect_fork_env(port(), non_neg_integer(), [{string(), string()}]) ->
                          {ok, [{string(), string()}]} | {error, term()}.
collect_fork_env(Port, Timeout, Acc) ->
    case recv_port_line(Port, Timeout) of
        {ok, Line} ->
            case Line of
                "FORK_ENV_DONE" ++ _ ->
                    {ok, lists:reverse(Acc)};
                "ENV " ++ Rest ->
                    collect_fork_env(Port, Timeout, [split_env_kv(Rest) | Acc]);
                _ ->
                    %% Ignore non-ENV chatter between READY and FORK_ENV_DONE.
                    collect_fork_env(Port, Timeout, Acc)
            end;
        {error, _} = Err ->
            Err
    end.

-spec recv_port_line(port(), non_neg_integer()) -> {ok, string()} | {error, term()}.
recv_port_line(Port, Timeout) ->
    receive
        {Port, {data, {eol, Line}}} ->
            {ok, line_to_list(Line)};
        {Port, {data, {noeol, Line}}} ->
            {ok, line_to_list(Line)};
        {Port, {data, Data}} ->
            {ok, line_to_list(Data)};
        {Port, {exit_status, Status}} ->
            {error, {exit_status, Status}}
    after Timeout ->
        {error, timeout}
    end.

-spec line_to_list(term()) -> string().
line_to_list(Line) when is_binary(Line) ->
    binary_to_list(Line);
line_to_list(Line) when is_list(Line) ->
    Line;
line_to_list(Other) ->
    lists:flatten(
        io_lib:format("~p", [Other])).

-spec split_env_kv(string()) -> {string(), string()}.
split_env_kv(S) ->
    case lists:splitwith(fun(C) -> C =/= $= end, S) of
        {K, [$= | V]} ->
            {K, V};
        {K, _} ->
            {K, ""}
    end.

-spec parse_ready_line(term()) -> {ok, string()} | skip.
parse_ready_line(Line) when is_binary(Line) ->
    parse_ready_line(binary_to_list(Line));
parse_ready_line(Line) when is_list(Line) ->
    case string:find(Line, "READY ") of
        nomatch ->
            skip;
        _ ->
            {ok, extract_uri_token(Line)}
    end;
parse_ready_line(_) ->
    skip.

-spec extract_uri_token(string()) -> string().
extract_uri_token(Line) ->
    case re:run(Line, "uri=(\\S+)", [{capture, [1], list}]) of
        {match, [Uri]} ->
            Uri;
        _ ->
            ""
    end.

-spec get_swm_pmix_path() -> string().
get_swm_pmix_path() ->
    case os:getenv("SWM_PMIX_PATH") of
        false ->
            case wm_utils:get_env("SWM_ROOT") of
                undefined ->
                    "/opt/swm/current/bin/swm-pmix";
                Root ->
                    filename:join([Root, "current", "bin", "swm-pmix"])
            end;
        Path ->
            Path
    end.

-spec launch_ranks(#task{}, [string()], boolean(), #job{}, #mstate{}) -> #mstate{}.
launch_ranks(#task{id = TaskId,
                   job_id = JobId,
                   cmd = Cmd} =
                 Task,
             NodeIds,
             Pmix,
             Job,
             MState) ->
    case NodeIds of
        [] ->
            finish_task(TaskId, 1, "no nodes", MState);
        _ ->
            SelfId = wm_self:get_node_id(),
            {ok, MyNode} = wm_self:get_node(),
            N = length(NodeIds),
            {MState1, PeerAddrs} =
                lists:foldl(fun(NodeId, {MS, Acc}) ->
                               case NodeId of
                                   SelfId ->
                                       case wm_conf:get_my_address() of
                                           not_found ->
                                               {MS, Acc};
                                           {error, _} ->
                                               {MS, Acc};
                                           MyAddr ->
                                               {MS, [MyAddr | Acc]}
                                       end;
                                   _ ->
                                       case wm_conf:select(node, {id, NodeId}) of
                                           {ok, Node} ->
                                               Addr = wm_conf:get_relative_address(Node, MyNode),
                                               {MS, [Addr | Acc]};
                                           _ ->
                                               {MS, Acc}
                                       end
                               end
                            end,
                            {MState, []},
                            NodeIds),
            Peers = lists:reverse(PeerAddrs),
            MState2 =
                MState1#mstate{fence_peers = maps:put(JobId, Peers, MState1#mstate.fence_peers),
                               fence_expected = maps:put(JobId, max(1, N), MState1#mstate.fence_expected),
                               tasks = maps:put(TaskId, Task, MState1#mstate.tasks)},
            {MState3, _} =
                lists:foldl(fun(NodeId, {MS, Rank}) ->
                               PmixEnv =
                                   case Pmix of
                                       true ->
                                           do_bootstrap_env(JobId, Rank, MS);
                                       false ->
                                           []
                                   end,
                               MS2 = case NodeId of
                                         SelfId ->
                                             do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, Job, MS);
                                         _ ->
                                             case wm_conf:select(node, {id, NodeId}) of
                                                 {ok, Node} ->
                                                     Addr = wm_conf:get_relative_address(Node, MyNode),
                                                     ReplyTo = wm_conf:get_my_relative_address(Addr),
                                                     wm_api:cast_self({pmix_start_rank,
                                                                       JobId,
                                                                       TaskId,
                                                                       Rank,
                                                                       Cmd,
                                                                       PmixEnv,
                                                                       Job,
                                                                       ReplyTo},
                                                                      [Addr]),
                                                     MS;
                                                 _ ->
                                                     MS
                                             end
                                     end,
                               {MS2, Rank + 1}
                            end,
                            {MState2, 0},
                            NodeIds),
            MState3
    end.

-spec do_bootstrap_env(string(), non_neg_integer(), #mstate{}) -> [{string(), string()}].
do_bootstrap_env(JobId, Rank, #mstate{}) ->
    %% Rank/nspace/size only. Per-node setup_fork env (URI, dstore paths) is
    %% applied in do_start_rank_local so remotes never inherit the main node's URI.
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            NodeIds = wm_entity:get(nodes, Job),
            Names =
                [begin
                     case wm_conf:select(node, {id, Id}) of
                         {ok, N} ->
                             wm_entity:get(name, N);
                         _ ->
                             Id
                     end
                 end
                 || Id <- NodeIds],
            bootstrap_env(#{job_id => JobId, nodes => Names}, Rank);
        _ ->
            bootstrap_env(#{job_id => JobId, nodes => []}, Rank)
    end.

-spec merge_env([{string(), string()}], [{string(), string()}]) -> [{string(), string()}].
merge_env(Base, Overlay) ->
    lists:foldl(fun({K, V}, Acc) -> lists:keystore(K, 1, Acc, {K, V}) end, Base, Overlay).

%% setup_fork(rank=0) at helper start emits PMIX_RANK=0; never let that clobber the real rank.
-spec fork_env_without_rank([{string(), string()}]) -> [{string(), string()}].
fork_env_without_rank(Fork) ->
    [KV
     || {K, _} = KV <- Fork,
        K =/= "PMIX_RANK",
        K =/= "PMIX_NAMESPACE",
        K =/= "PMIX_JOB_SIZE",
        K =/= "PMIX_LOCAL_SIZE",
        K =/= "SWM_PMIX_RANK",
        K =/= "SWM_PMIX_NSPACE"].

-spec apply_rank_env([{string(), string()}], non_neg_integer()) -> [{string(), string()}].
apply_rank_env(Env, Rank) ->
    RankStr = integer_to_list(Rank),
    lists:foldl(fun({K, V}, Acc) -> lists:keystore(K, 1, Acc, {K, V}) end,
                Env,
                [{"PMIX_RANK", RankStr},
                 {"SWM_PMIX_RANK", RankStr},
                 {"OMPI_COMM_WORLD_RANK", RankStr},
                 {"OMPI_COMM_WORLD_LOCAL_RANK", "0"}]).

-spec remember_rank_reply_to(binary(), term(), #mstate{}) -> #mstate{}.
remember_rank_reply_to(_TaskId, undefined, MState) ->
    MState;
remember_rank_reply_to(_TaskId, {error, _}, MState) ->
    MState;
remember_rank_reply_to(TaskId, ReplyTo, #mstate{rank_reply_to = Map} = MState) ->
    MState#mstate{rank_reply_to = maps:put(TaskId, ReplyTo, Map)}.

%% OpenPMIx clients prefer versioned PMIX_SERVER_URI* (e.g. URI41); keep them in sync.
-spec apply_server_uri([{string(), string()}], string()) -> [{string(), string()}].
apply_server_uri(Env, "") ->
    Env;
apply_server_uri(Env, Uri) ->
    Updated =
        lists:map(fun({K, V}) ->
                     case K =:= "PMIX_SERVER_URI" orelse lists:prefix("PMIX_SERVER_URI", K) of
                         true ->
                             {K, Uri};
                         false ->
                             {K, V}
                     end
                  end,
                  Env),
    lists:keystore("PMIX_SERVER_URI", 1, Updated, {"PMIX_SERVER_URI", Uri}).

-spec do_start_rank_local(string(),
                          binary(),
                          non_neg_integer(),
                          [string()],
                          [{string(), string()}],
                          #job{} | undefined,
                          #mstate{}) ->
                             #mstate{}.
do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv0, JobIn, MState0) ->
    %% Each allocated node runs its own swm-pmix; inject that node's fork env/URI.
    {MState, PmixEnv} =
        case PmixEnv0 of
            [] ->
                {MState0, []};
            _ ->
                MS1 = ensure_helper(JobId, MState0),
                N = case lists:keyfind("PMIX_JOB_SIZE", 1, PmixEnv0) of
                        {_, SizeStr} ->
                            try
                                list_to_integer(SizeStr)
                            catch
                                _:_ ->
                                    1
                            end;
                        false ->
                            1
                    end,
                MS2 = maybe_register_nspace(JobId, N, Rank, MS1),
                send_contrib_id(JobId, Rank, MS2),
                Fork = fork_env_without_rank(maps:get(JobId, MS2#mstate.fork_envs, [])),
                Uri = maps:get(JobId, MS2#mstate.server_uris, ""),
                %% Local fork env must win for URI/tmpdir; rank identity stays from bootstrap.
                %% Keep psec=none: TCP cannot use native SO_PEERCRED auth.
                EnvMerged0 = apply_rank_env(apply_server_uri(merge_env(PmixEnv0, Fork), Uri), Rank),
                EnvMerged =
                    lists:foldl(fun({K, V}, Acc) -> lists:keystore(K, 1, Acc, {K, V}) end,
                                EnvMerged0,
                                [{"PMIX_SECURITY_MODE", "none"}, {"PMIX_MCA_psec", "none"}]),
                {MS2, EnvMerged}
        end,
    Job0 =
        case JobIn of
            #job{} = J ->
                J;
            _ ->
                case wm_conf:select(job, {id, JobId}) of
                    {ok, J} ->
                        J;
                    _ ->
                        undefined
                end
        end,
    case Job0 of
        #job{} ->
            Script = shell_join(Cmd),
            ContName = "swmrank-" ++ short_id(JobId) ++ "-" ++ integer_to_list(Rank),
            JobEnv0 = wm_entity:get(env, Job0),
            RankEnv =
                JobEnv0
                ++ PmixEnv
                ++ [{"SWM_TASK_ID", binary_to_list(TaskId)}, {"SWM_PMIX_RANK", integer_to_list(Rank)}],
            Job1 = wm_entity:set([{script_content, Script}, {container, ContName}, {env, RankEnv}], Job0),
            Porter = porter_path(),
            case wm_container:run(Job1, Porter, maps:from_list(RankEnv), self()) of
                {ok, NewJob} ->
                    ?LOG_DEBUG("Started rank ~p container ~p for task ~p", [Rank, ContName, TaskId]),
                    ContID = wm_entity:get(container, NewJob),
                    Owner = self(),
                    spawn(fun() -> feed_rank_porter(NewJob, Owner) end),
                    MState#mstate{cont_tasks = maps:put(ContID, TaskId, MState#mstate.cont_tasks)};
                {error, Msg} ->
                    ?LOG_ERROR("Rank ~p start failed: ~p", [Rank, Msg]),
                    finish_task(TaskId,
                                1,
                                lists:flatten(
                                    io_lib:format("~p", [Msg])),
                                MState)
            end;
        _ ->
            ?LOG_ERROR("Rank ~p start failed: job ~p not found locally and not provided in cast", [Rank, JobId]),
            finish_task(TaskId, 1, "job not found", MState)
    end.

-spec short_id(string()) -> string().
short_id(JobId) when length(JobId) >= 8 ->
    lists:sublist(JobId, 8);
short_id(JobId) ->
    JobId.

-spec feed_rank_porter(#job{}, pid()) -> ok.
feed_rank_porter(Job, Owner) ->
    timer:sleep(500),
    case wm_utils:get_job_user(Job) of
        {ok, User} ->
            Bin = wm_porter_protocol:prepare_run_input(Job, User),
            %% Owner must stay wm_pmix: communicate() replaces the container owner
            %% map entry; using spawn self() dropped {process,F} on a dead pid.
            case wm_container:communicate(Job, Bin, Owner) of
                ok ->
                    ok;
                {error, E} ->
                    ?LOG_ERROR("Rank communicate failed: ~p", [E])
            end;
        _ ->
            ?LOG_ERROR("No user for rank job ~p", [wm_entity:get(id, Job)])
    end,
    ok.

-spec porter_path() -> string().
porter_path() ->
    case os:getenv("SWM_PORTER_IN_CONTAINER") of
        false ->
            "/opt/swm/current/bin/swm-porter";
        P ->
            P
    end.

-spec shell_join([string()]) -> string().
shell_join([]) ->
    "true";
shell_join(Parts) ->
    string:join([shell_quote(P) || P <- Parts], " ").

-spec shell_quote(string()) -> string().
shell_quote(S) ->
    "'"
    ++ lists:flatten(
           string:replace(S, "'", "'\"'\"'", all))
    ++ "'".

-spec deliver_job_metrics(string(), map(), #mstate{}) -> ok.
deliver_job_metrics(JobId, Map, #mstate{fence_leader = FenceLeader}) ->
    case maps:get(JobId, FenceLeader, undefined) of
        undefined ->
            gen_server:cast(wm_compute, {job_metrics, JobId, Map, node()});
        ReplyTo ->
            ?LOG_DEBUG("Forward job_metrics for ~p to main ~p", [JobId, ReplyTo]),
            wm_api:cast_self({job_metrics, JobId, Map, node()}, [ReplyTo])
    end,
    ok.

-spec on_rank_process(string(), #process{}, #mstate{}) -> #mstate{}.
on_rank_process(JobId, Process, #mstate{cont_tasks = CT} = MState) ->
    State = wm_entity:get(state, Process),
    case State of
        S when S =:= ?JOB_STATE_FINISHED; S =:= ?JOB_STATE_ERROR ->
            Exit = wm_entity:get(exitcode, Process),
            TaskId =
                case maps:get(JobId, MState#mstate.job_tasks, []) of
                    [Tid | _] ->
                        Tid;
                    _ ->
                        case maps:values(CT) of
                            [Tid | _] ->
                                Tid;
                            _ ->
                                undefined
                        end
                end,
            case TaskId of
                undefined ->
                    ?LOG_DEBUG("Rank process finished for job ~p but no task id", [JobId]),
                    MState;
                _ ->
                    report_rank_done(TaskId, Exit, MState)
            end;
        _ ->
            MState
    end.

-spec report_rank_done(binary(), integer(), #mstate{}) -> #mstate{}.
report_rank_done(TaskId, ExitCode, #mstate{tasks = Tasks, rank_reply_to = Origins} = MState) ->
    case maps:get(TaskId, Tasks, undefined) of
        #task{} ->
            rank_finished(TaskId, ExitCode, MState);
        undefined ->
            case maps:get(TaskId, Origins, undefined) of
                undefined ->
                    ?LOG_ERROR("rank_done for unknown task ~p (no local task, no ReplyTo)", [TaskId]),
                    MState;
                ReplyTo ->
                    ?LOG_DEBUG("Forward rank_done for task ~p to ~p exit=~p", [TaskId, ReplyTo, ExitCode]),
                    wm_api:cast_self({rank_done, TaskId, ExitCode}, [ReplyTo]),
                    MState#mstate{rank_reply_to = maps:remove(TaskId, Origins)}
            end
    end.

-spec rank_finished(binary(), integer(), #mstate{}) -> #mstate{}.
rank_finished(TaskId, ExitCode, #mstate{tasks = Tasks} = MState) ->
    case maps:get(TaskId, Tasks, undefined) of
        undefined ->
            MState;
        #task{rank_expected = Exp, ranks_done = Done} = Task ->
            Done2 = Done + 1,
            Task2 = Task#task{ranks_done = Done2},
            MState2 = MState#mstate{tasks = maps:put(TaskId, Task2, Tasks)},
            Code =
                case ExitCode of
                    N when is_integer(N), N >= 0 ->
                        N;
                    _ ->
                        1
                end,
            if Done2 >= max(1, Exp) ->
                   finish_task(TaskId, Code, "", MState2);
               true ->
                   %% Keep worst (non-zero) exit code on the task while ranks remain.
                   Task3 =
                       case {Task2#task.exitcode, Code} of
                           {undefined, _} ->
                               Task2#task{exitcode = Code};
                           {_, C} when C =/= 0 ->
                               Task2#task{exitcode = C};
                           _ ->
                               Task2
                       end,
                   MState2#mstate{tasks = maps:put(TaskId, Task3, Tasks)}
            end
    end.

-spec finish_task(binary(), integer(), string(), #mstate{}) -> #mstate{}.
finish_task(TaskId, ExitCode, Comment, #mstate{tasks = Tasks} = MState) ->
    case maps:get(TaskId, Tasks, undefined) of
        undefined ->
            MState;
        #task{cont_id = ContID, ref = Ref} = Task ->
            Task2 = Task#task{exitcode = ExitCode},
            Tasks2 = maps:put(TaskId, Task2, Tasks),
            Msg = case Comment of
                      "" ->
                          {done, ExitCode};
                      _ ->
                          {error, Comment}
                  end,
            case ContID of
                undefined ->
                    ok;
                _ ->
                    reply_porter(ContID, Ref, Msg)
            end,
            MState#mstate{tasks = Tasks2}
    end.

-spec send_contrib_id(string(), non_neg_integer(), #mstate{}) -> ok.
send_contrib_id(JobId, Rank, #mstate{helpers = Helpers}) ->
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            safe_port_cmd(Port, list_to_binary(io_lib:format("CONTRIB_ID ~b~n", [Rank])));
        _ ->
            ok
    end.

-spec on_helper_line(port(), string(), #mstate{}) -> #mstate{}.
on_helper_line(Port, Line, #mstate{helper_jobs = HJ} = MState) ->
    case Line of
        "FENCE_IN " ++ _ ->
            case maps:get(Port, HJ, undefined) of
                undefined ->
                    ?LOG_ERROR("FENCE_IN from unknown helper port"),
                    MState;
                JobId ->
                    on_local_fence_in(JobId, Line, MState)
            end;
        _ ->
            ?LOG_DEBUG("swm-pmix: ~s", [Line]),
            MState
    end.

-spec on_local_fence_in(string(), string(), #mstate{}) -> #mstate{}.
on_local_fence_in(JobId, Line, MState) ->
    case parse_fence_in(Line) of
        {ok, FenceId, ContribId, Data} ->
            case maps:get(JobId, MState#mstate.fence_leader, undefined) of
                undefined ->
                    %% Leader (or single-node): accumulate locally.
                    on_fence_contrib(JobId, ContribId, Data, local, true, FenceId, MState);
                Leader ->
                    %% Remote helper: remember local id, forward blob to leader.
                    MS1 = remember_local_fence_id(JobId, FenceId, MState),
                    MyAddr =
                        case wm_conf:get_my_relative_address(Leader) of
                            {error, _} ->
                                wm_conf:get_my_address();
                            Addr ->
                                Addr
                        end,
                    wm_api:cast_self({pmix_fence_contrib, JobId, ContribId, Data, MyAddr}, [Leader]),
                    MS1
            end;
        {error, Reason} ->
            ?LOG_ERROR("Bad FENCE_IN for job ~p: ~p (~s)", [JobId, Reason, Line]),
            MState
    end.

-spec remember_local_fence_id(string(), non_neg_integer(), #mstate{}) -> #mstate{}.
remember_local_fence_id(JobId, FenceId, #mstate{fences = Fences} = MState) ->
    Round =
        case maps:get(JobId, Fences, undefined) of
            undefined ->
                Exp = maps:get(JobId, MState#mstate.fence_expected, 1),
                #fence_round{expected = Exp, local_ids = [FenceId]};
            #fence_round{local_ids = Ids} = R ->
                R#fence_round{local_ids = [FenceId | Ids]}
        end,
    MState#mstate{fences = maps:put(JobId, Round, Fences)}.

-spec on_fence_contrib(string(),
                       non_neg_integer(),
                       binary(),
                       term(),
                       boolean(),
                       non_neg_integer() | undefined,
                       #mstate{}) ->
                          #mstate{}.
on_fence_contrib(JobId, ContribId, Data, _FromAddr, IsLocal, LocalFenceId, #mstate{fences = Fences} = MState) ->
    Exp = maps:get(JobId, MState#mstate.fence_expected, 1),
    Round0 =
        case maps:get(JobId, Fences, undefined) of
            undefined ->
                #fence_round{expected = Exp};
            R ->
                R
        end,
    Round1 =
        case IsLocal andalso LocalFenceId =/= undefined of
            true ->
                Round0#fence_round{local_ids = [LocalFenceId | Round0#fence_round.local_ids]};
            false ->
                Round0
        end,
    Arrived = maps:put(ContribId, Data, Round1#fence_round.arrived),
    Round2 = Round1#fence_round{arrived = Arrived},
    MState1 = MState#mstate{fences = maps:put(JobId, Round2, Fences)},
    case maps:size(Arrived) >= Round2#fence_round.expected of
        true ->
            complete_fence_round(JobId, Round2, MState1);
        false ->
            ?LOG_DEBUG("Fence job ~p contrib ~p (~b/~b)",
                       [JobId, ContribId, maps:size(Arrived), Round2#fence_round.expected]),
            MState1
    end.

-spec complete_fence_round(string(), #fence_round{}, #mstate{}) -> #mstate{}.
complete_fence_round(JobId, #fence_round{arrived = Arrived} = Round, MState) ->
    %% Concatenate contributions in contrib-id order (OpenPMIx host allgather).
    Sorted = lists:keysort(1, maps:to_list(Arrived)),
    Aggregated = iolist_to_binary([D || {_, D} <- Sorted]),
    ?LOG_INFO("Fence complete for job ~p: ~b contribs, ~b bytes", [JobId, maps:size(Arrived), byte_size(Aggregated)]),
    Peers = maps:get(JobId, MState#mstate.fence_peers, []),
    lists:foreach(fun(Addr) ->
                     case is_local_fence_peer(Addr) of
                         true ->
                             ok;
                         false ->
                             wm_api:cast_self({pmix_fence_result, JobId, 0, Aggregated}, [Addr])
                     end
                  end,
                  Peers),
    apply_fence_result(JobId,
                       0,
                       Aggregated,
                       MState#mstate{fences = maps:put(JobId, Round#fence_round{arrived = #{}}, MState#mstate.fences)}).

-spec is_local_fence_peer(term()) -> boolean().
is_local_fence_peer(Addr) ->
    case wm_conf:get_my_address() of
        Addr ->
            true;
        _ ->
            wm_conf:is_my_address(Addr)
    end.

-spec apply_fence_result(string(), integer(), binary(), #mstate{}) -> #mstate{}.
apply_fence_result(JobId, Status, Aggregated, #mstate{helpers = Helpers, fences = Fences} = MState) ->
    LocalIds =
        case maps:get(JobId, Fences, undefined) of
            #fence_round{local_ids = Ids} ->
                lists:reverse(Ids);
            _ ->
                []
        end,
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            B64 = base64:encode_to_string(Aggregated),
            lists:foreach(fun(FenceId) ->
                             Cmd = list_to_binary(io_lib:format("FENCE_OUT id=~b status=~b nbytes=~b b64=~s~n",
                                                                [FenceId, Status, byte_size(Aggregated), B64])),
                             safe_port_cmd(Port, Cmd)
                          end,
                          LocalIds);
        _ ->
            ?LOG_ERROR("No helper for fence result job ~p", [JobId])
    end,
    %% Clear round but keep expected/peers for a later fence.
    MState#mstate{fences = maps:remove(JobId, Fences)}.

-spec parse_fence_in(string()) -> {ok, non_neg_integer(), non_neg_integer(), binary()} | {error, term()}.
parse_fence_in(Line) ->
    try
        Id = list_to_integer(fence_token(Line, "id=")),
        Contrib = list_to_integer(fence_token(Line, "contrib=")),
        B64 = fence_token_rest(Line, "b64="),
        Data =
            case B64 of
                "" ->
                    <<>>;
                _ ->
                    base64:decode(B64)
            end,
        {ok, Id, Contrib, Data}
    catch
        E:R ->
            {error, {E, R}}
    end.

-spec fence_token(string(), string()) -> string().
fence_token(Line, Key) ->
    case string:find(Line, Key) of
        nomatch ->
            error({missing, Key});
        Rest0 ->
            Rest = lists:nthtail(length(Key), Rest0),
            case lists:splitwith(fun(C) -> C =/= $  end, Rest) of
                {Tok, _} ->
                    Tok
            end
    end.

-spec fence_token_rest(string(), string()) -> string().
fence_token_rest(Line, Key) ->
    case string:find(Line, Key) of
        nomatch ->
            "";
        Rest0 ->
            lists:nthtail(length(Key), Rest0)
    end.

-spec do_cancel_job(string(), #mstate{}) -> #mstate{}.
do_cancel_job(JobId,
              #mstate{job_tasks = JT,
                      helpers = Helpers,
                      helper_jobs = HelperJobs,
                      server_uris = Uris,
                      fork_envs = ForkEnvs,
                      fences = Fences,
                      fence_expected = FenceExp,
                      fence_peers = FencePeers,
                      fence_leader = FenceLeader} =
                  MState) ->
    Ids = maps:get(JobId, JT, []),
    MState1 = lists:foldl(fun(Tid, MS) -> do_cancel_task(JobId, Tid, MS) end, MState, Ids),
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            safe_port_cmd(Port, <<"STOP\n">>),
            safe_port_close(Port),
            MState1#mstate{helpers = maps:remove(JobId, Helpers),
                           helper_jobs = maps:remove(Port, HelperJobs),
                           server_uris = maps:remove(JobId, Uris),
                           fork_envs = maps:remove(JobId, ForkEnvs),
                           fences = maps:remove(JobId, Fences),
                           fence_expected = maps:remove(JobId, FenceExp),
                           fence_peers = maps:remove(JobId, FencePeers),
                           fence_leader = maps:remove(JobId, FenceLeader)};
        _ ->
            MState1#mstate{server_uris = maps:remove(JobId, Uris),
                           fork_envs = maps:remove(JobId, ForkEnvs),
                           fences = maps:remove(JobId, Fences),
                           fence_expected = maps:remove(JobId, FenceExp),
                           fence_peers = maps:remove(JobId, FencePeers),
                           fence_leader = maps:remove(JobId, FenceLeader)}
    end.

-spec do_cancel_task(string(), binary(), #mstate{}) -> #mstate{}.
do_cancel_task(JobId, TaskId, #mstate{tasks = Tasks} = MState) ->
    case maps:get(TaskId, Tasks, undefined) of
        #task{rank_expected = Exp} = Task ->
            lists:foreach(fun(Rank) ->
                             ContName = "swmrank-" ++ short_id(JobId) ++ "-" ++ integer_to_list(Rank),
                             FakeJob = wm_entity:set([{id, JobId}, {container, ContName}], wm_entity:new(job)),
                             try
                                 wm_container:clear(FakeJob)
                             catch
                                 _:_ ->
                                     ok
                             end
                          end,
                          lists:seq(0, max(0, Exp - 1))),
            finish_task(TaskId, 143, "canceled", MState#mstate{tasks = maps:put(TaskId, Task, Tasks)});
        _ ->
            MState
    end.
