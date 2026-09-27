-module(wm_pmix).

-behaviour(gen_server).

%% @doc PMIx session owner for compute nodes (issue #9).
%% Erlang owns lifecycle and RM policy; C++ swm-pmix links libpmix.
%% Trigger: swm-task --pmix via Porter control relay (no submit-time flag).

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
-record(mstate,
        {helpers = #{} :: map(),
         tasks = #{} :: map(),
         job_tasks = #{} :: map(),
         %% ContID => TaskId for rank container events
         cont_tasks = #{} :: map()}).

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
    Base =
        [{"PMIX_NAMESPACE", Nspace},
         {"PMIX_RANK", integer_to_list(Rank)},
         {"PMIX_JOB_SIZE", integer_to_list(Size)},
         {"PMIX_LOCAL_SIZE", "1"},
         {"SWM_PMIX_NSPACE", Nspace},
         {"SWM_PMIX_RANK", integer_to_list(Rank)}],
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
handle_cast({start_rank_local, JobId, TaskId, Rank, Cmd, PmixEnv}, MState) ->
    {noreply, do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, MState)};
handle_cast({started, JobId}, MState) ->
    ?LOG_DEBUG("Rank container started for job ~p", [JobId]),
    {noreply, MState};
handle_cast({sent, JobId}, MState) ->
    ?LOG_DEBUG("Rank Porter input sent for job ~p", [JobId]),
    {noreply, MState};
handle_cast({{process, Process}, JobId}, MState) ->
    {noreply, on_rank_process(JobId, Process, MState)};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("wm_pmix unhandled cast: ~p", [Msg]),
    {noreply, MState}.

handle_info({'EXIT', Port, Reason}, #mstate{helpers = Helpers} = MState) when is_port(Port) ->
    ?LOG_DEBUG("swm-pmix helper port exited: ~p", [Reason]),
    Helpers2 = maps:filter(fun(_, P) -> P =/= Port end, Helpers),
    {noreply, MState#mstate{helpers = Helpers2}};
handle_info({Port, {data, Data}}, #mstate{helpers = Helpers} = MState) when is_port(Port) ->
    ?LOG_DEBUG("swm-pmix: ~s", [Data]),
    _ = Helpers,
    {noreply, MState};
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
            %% Without --pmix, swm-task execs locally; SPAWN without pmix is multi-node plain.
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
            maybe_register_nspace(JobId, N, MState1),
            launch_ranks(Task#task{rank_expected = N}, NodeIds, true, MState1);
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
            launch_ranks(Task#task{rank_expected = length(NodeIds)}, NodeIds, false, MState);
        _ ->
            finish_task(Task#task.id, 1, "job not found", MState)
    end.

-spec ensure_helper(string(), #mstate{}) -> #mstate{}.
ensure_helper(JobId, #mstate{helpers = Helpers} = MState) ->
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            MState;
        _ ->
            case start_swm_pmix(JobId) of
                {ok, Port} ->
                    MState#mstate{helpers = maps:put(JobId, Port, Helpers)};
                {error, Reason} ->
                    ?LOG_ERROR("Failed to start swm-pmix for job ~p: ~p", [JobId, Reason]),
                    MState
            end
    end.

-spec maybe_register_nspace(string(), non_neg_integer(), #mstate{}) -> ok.
maybe_register_nspace(JobId, N, #mstate{helpers = Helpers}) ->
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            Cmd = list_to_binary(io_lib:format("REGISTER ~b~n", [max(1, N)])),
            safe_port_cmd(Port, Cmd),
            ok;
        _ ->
            ok
    end.

-spec start_swm_pmix(string()) -> {ok, port()} | {error, term()}.
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
                               {env, [{"SWM_JOB_ID", JobId}]},
                               binary,
                               exit_status,
                               use_stdio,
                               stderr_to_stdout,
                               {line, 1024}]),
                {ok, Port}
            catch
                E:R ->
                    {error, {E, R}}
            end
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

-spec launch_ranks(#task{}, [string()], boolean(), #mstate{}) -> #mstate{}.
launch_ranks(#task{id = TaskId,
                   job_id = JobId,
                   cmd = Cmd} =
                 Task,
             NodeIds,
             Pmix,
             MState) ->
    case NodeIds of
        [] ->
            finish_task(TaskId, 1, "no nodes", MState);
        _ ->
            SelfId = wm_self:get_node_id(),
            {ok, MyNode} = wm_self:get_node(),
            {MState2, _} =
                lists:foldl(fun(NodeId, {MS, Rank}) ->
                               PmixEnv =
                                   case Pmix of
                                       true ->
                                           do_bootstrap_env(JobId, Rank);
                                       false ->
                                           []
                                   end,
                               MS2 = case NodeId of
                                         SelfId ->
                                             do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, MS);
                                         _ ->
                                             case wm_conf:select(node, {id, NodeId}) of
                                                 {ok, Node} ->
                                                     Addr = wm_conf:get_relative_address(Node, MyNode),
                                                     wm_api:cast_self({pmix_start_rank,
                                                                       JobId,
                                                                       TaskId,
                                                                       Rank,
                                                                       Cmd,
                                                                       PmixEnv},
                                                                      [Addr]),
                                                     MS;
                                                 _ ->
                                                     MS
                                             end
                                     end,
                               {MS2, Rank + 1}
                            end,
                            {MState#mstate{tasks = maps:put(TaskId, Task, MState#mstate.tasks)}, 0},
                            NodeIds),
            MState2
    end.

-spec do_bootstrap_env(string(), non_neg_integer()) -> [{string(), string()}].
do_bootstrap_env(JobId, Rank) ->
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

-spec do_start_rank_local(string(), binary(), non_neg_integer(), [string()], [{string(), string()}], #mstate{}) ->
                             #mstate{}.
do_start_rank_local(JobId, TaskId, Rank, Cmd, PmixEnv, #mstate{cont_tasks = CT} = MState) ->
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job0} ->
            Script = shell_join(Cmd),
            ContName = "swmrank-" ++ short_id(JobId) ++ "-" ++ integer_to_list(Rank),
            Env0 = wm_entity:get(env, Job0),
            Env1 =
                Env0 ++ PmixEnv ++ [{"SWM_TASK_ID", binary_to_list(TaskId)}, {"SWM_PMIX_RANK", integer_to_list(Rank)}],
            Job1 = wm_entity:set([{script_content, Script}, {container, ContName}, {env, Env1}], Job0),
            Porter = porter_path(),
            case wm_container:run(Job1, Porter, maps:from_list(Env1), self()) of
                {ok, NewJob} ->
                    ?LOG_DEBUG("Started rank ~p container ~p for task ~p", [Rank, ContName, TaskId]),
                    ContID = wm_entity:get(container, NewJob),
                    spawn(fun() -> feed_rank_porter(NewJob) end),
                    MState#mstate{cont_tasks = maps:put(ContID, TaskId, CT)};
                {error, Msg} ->
                    ?LOG_ERROR("Rank ~p start failed: ~p", [Rank, Msg]),
                    finish_task(TaskId,
                                1,
                                lists:flatten(
                                    io_lib:format("~p", [Msg])),
                                MState)
            end;
        _ ->
            finish_task(TaskId, 1, "job not found", MState)
    end.

-spec short_id(string()) -> string().
short_id(JobId) when length(JobId) >= 8 ->
    lists:sublist(JobId, 8);
short_id(JobId) ->
    JobId.

-spec feed_rank_porter(#job{}) -> ok.
feed_rank_porter(Job) ->
    timer:sleep(500),
    case wm_utils:get_job_user(Job) of
        {ok, User} ->
            Bin = wm_porter_protocol:prepare_run_input(Job, User),
            case wm_container:communicate(Job, Bin, self()) of
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

-spec on_rank_process(string(), #process{}, #mstate{}) -> #mstate{}.
on_rank_process(JobId, Process, #mstate{cont_tasks = CT} = MState) ->
    State = wm_entity:get(state, Process),
    case State of
        S when S =:= ?JOB_STATE_FINISHED; S =:= ?JOB_STATE_ERROR ->
            Exit = wm_entity:get(exitcode, Process),
            Ids = maps:get(JobId, MState#mstate.job_tasks, []),
            case Ids of
                [TaskId | _] ->
                    rank_finished(TaskId, Exit, MState);
                _ ->
                    case maps:values(CT) of
                        [TaskId | _] ->
                            rank_finished(TaskId, Exit, MState);
                        _ ->
                            MState
                    end
            end;
        _ ->
            MState
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

-spec do_cancel_job(string(), #mstate{}) -> #mstate{}.
do_cancel_job(JobId, #mstate{job_tasks = JT, helpers = Helpers} = MState) ->
    Ids = maps:get(JobId, JT, []),
    MState1 = lists:foldl(fun(Tid, MS) -> do_cancel_task(JobId, Tid, MS) end, MState, Ids),
    case maps:get(JobId, Helpers, undefined) of
        Port when is_port(Port) ->
            safe_port_cmd(Port, <<"STOP\n">>),
            safe_port_close(Port),
            MState1#mstate{helpers = maps:remove(JobId, Helpers)};
        _ ->
            MState1
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
