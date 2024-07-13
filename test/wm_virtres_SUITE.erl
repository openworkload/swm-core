-module(wm_virtres_SUITE).

-export([suite/0, all/0, groups/0, init_per_suite/1, end_per_suite/1, init_per_group/2, end_per_group/2]).
-export([activate/1, part_absent_create/1, part_spawned/1, part_fetched_not_up/1, part_fetched_up/1,
         uploading_is_about_to_start/1, uploading_started/1, uploading_done/1, downloading_started/1,
         downloading_done/1, part_destraction_in_progress/1, deactivate/1]).
-export([part_exists_detete/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-include("../src/lib/wm_entity.hrl").

%% ============================================================================
%% Common test callbacks
%% ============================================================================

-spec suite() -> list().
suite() ->
    [{timetrap, {seconds, 260}}].

-spec all() -> list().
all() ->
    [{group, create_partition}, {group, delete_partition}].

-spec groups() -> list().
groups() ->
    [{create_partition,
      [],
      [activate,
       part_absent_create,
       part_spawned,
       part_fetched_not_up,
       part_fetched_up,
       uploading_is_about_to_start,
       uploading_started,
       uploading_done,
       downloading_started,
       downloading_done,
       part_destraction_in_progress,
       deactivate]},
     {delete_partition, [], [activate, part_exists_detete, deactivate]}].

-spec init_per_suite(list()) -> list() | {skip, any()}.
init_per_suite(Config) ->
    meck:new(wm_virtres_handler, [no_link]),
    meck:new(wm_conf, [no_link]),
    meck:new(wm_self, [no_link]),
    Config.

-spec end_per_suite(list()) -> term() | {save_config, any()}.
end_per_suite(_Config) ->
    meck:unload().

-spec init_per_group(atom(), list()) -> list() | {skip, list()}.
init_per_group(create_partition, Config) ->
    init_test_group(create, Config);
init_per_group(delete_partition, Config) ->
    init_test_group(destroy, Config).

-spec end_per_group(atom(), list()) -> list().
end_per_group(_, Config) ->
    erlang:exit(
        proplists:get_value(virtres_pid, Config), kill),
    Config.

%% ============================================================================
%% Helpers
%% ============================================================================

-spec init_test_group(atom(), list()) -> list().
init_test_group(Action, Config) ->
    JobId = wm_utils:uuid(v4),
    WaitRef = wm_utils:uuid(v4),
    PartExtId = wm_utils:uuid(v4),
    RemoteId = wm_utils:uuid(v4),
    PartMgrNodeId = wm_utils:uuid(v4),
    TemplateNode = wm_entity:set([{name, "cloud1-flavor1"}, {is_template, true}], wm_entity:new(node)),

    Remote = wm_entity:set([{id, RemoteId}], wm_entity:new(remote)),

    SelectById =
        fun (job, {id, Id}) when Id =:= JobId ->
                Job = wm_entity:set([{id, JobId}, {nodes, [TemplateNode]}], wm_entity:new(job)),
                {ok, Job};
            (node, {id, Id}) when Id =:= PartMgrNodeId ->
                Node = wm_entity:set([{name, "mgr"}, {id, PartMgrNodeId}], wm_entity:new(node)),
                {ok, Node}
        end,
    meck:expect(wm_virtres_handler, get_remote, fun(X) when X == JobId -> {ok, Remote} end),
    meck:expect(wm_virtres_handler, wait_for_partition_fetch, fun() -> erlang:make_ref() end),
    meck:expect(wm_virtres_handler, wait_for_ssh_connection, fun(_) -> erlang:make_ref() end),
    meck:expect(wm_virtres_handler, delete_partition, fun(_, _) -> {ok, WaitRef} end),
    meck:expect(wm_virtres_handler, start_job_data_uploading, fun(_, _, _) -> {ok, WaitRef} end),
    meck:expect(wm_conf, select, SelectById),
    meck:expect(wm_conf, g, fun(_, {X, _}) -> X end),
    meck:expect(wm_self, get_node_id, fun() -> "nodeid" end),

    {ok, VirtResPid} = wm_virtres:start([{extra, {Action, JobId, TemplateNode}}, {task_id, wm_utils:uuid(v4)}]),
    ?assert(is_process_alive(VirtResPid)),
    [{part_ext_id, PartExtId},
     {wait_ref, WaitRef},
     {job_id, JobId},
     {part_mgr_node_id, PartMgrNodeId},
     {virtres_pid, VirtResPid}]
    ++ Config.

%% ============================================================================
%% Tests
%% ============================================================================

-spec activate(list()) -> atom().
activate(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),
    RequestPartitionExistence = fun(_, _) -> {ok, WaitRef} end,
    meck:expect(wm_virtres_handler, request_partition_existence, RequestPartitionExistence),

    ?assertEqual(sleeping, gen_statem:call(Pid, get_current_state)),
    ok = gen_statem:cast(Pid, activate),
    ?assertEqual(validating, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec part_absent_create(list()) -> atom().
part_absent_create(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),
    SpawnPartition = fun(_, _) -> {ok, WaitRef} end,
    meck:expect(wm_virtres_handler, spawn_partition, SpawnPartition),

    ok = gen_statem:cast(Pid, {partition_exists, WaitRef, false}),
    ?assertEqual(creating, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec part_spawned(list()) -> atom().
part_spawned(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    PartExtId = proplists:get_value(part_ext_id, Config),
    JobId = proplists:get_value(job_id, Config),
    WaitRef = proplists:get_value(wait_ref, Config),

    meck:expect(wm_virtres_handler, request_partition, fun(X, _) when X == JobId -> {ok, WaitRef} end),

    ok = gen_statem:cast(Pid, {partition_spawned, WaitRef, PartExtId}),
    ?assertEqual(creating, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec part_fetched_not_up(list()) -> atom().
part_fetched_not_up(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),
    Part = wm_entity:set([{state, creating}, {name, "Foo"}, {id, wm_utils:uuid(v4)}], wm_entity:new(partition)),

    meck:expect(wm_virtres_handler, wait_for_partition_fetch, fun() -> erlang:make_ref() end),

    ok = gen_statem:cast(Pid, {partition_fetched, WaitRef, Part}),
    ?assertEqual(creating, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec part_fetched_up(list()) -> atom().
part_fetched_up(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    PartMgrNodeId = proplists:get_value(part_mgr_node_id, Config),
    WaitRef = proplists:get_value(wait_ref, Config),
    Part = wm_entity:set([{state, up}, {name, "Foo"}, {id, wm_utils:uuid(v4)}], wm_entity:new(partition)),

    meck:expect(wm_virtres_handler, ensure_entities_created, fun(_, X, _) when X == Part -> {ok, PartMgrNodeId} end),
    meck:expect(wm_virtres_handler, wait_for_wm_resources_readiness, fun() -> erlang:make_ref() end),

    ok = gen_statem:cast(Pid, {partition_fetched, WaitRef, Part}),
    ?assertEqual(creating, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec uploading_is_about_to_start(list()) -> atom().
uploading_is_about_to_start(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    JobId = proplists:get_value(job_id, Config),
    meck:expect(wm_virtres_handler, is_job_partition_ready, fun(X) when X == JobId -> false end),

    erlang:send(Pid, readiness_check),
    ?assertEqual(creating, gen_statem:call(Pid, get_current_state)),

    erlang:send(Pid, readiness_check),
    ?assertEqual(creating, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec uploading_started(list()) -> atom().
uploading_started(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),
    JobId = proplists:get_value(job_id, Config),
    PartMgrNodeId = proplists:get_value(part_mgr_node_id, Config),

    meck:expect(wm_virtres_handler, is_job_partition_ready, fun(X) when X == JobId -> true end),
    meck:expect(wm_virtres_handler, update_job, fun(_, X) when X == JobId -> 1 end),

    erlang:send(Pid, part_check),
    ?assertEqual(uploading, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec uploading_done(list()) -> atom().
uploading_done(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    JobId = proplists:get_value(job_id, Config),
    WaitRef = proplists:get_value(wait_ref, Config),

    meck:expect(wm_virtres_handler, update_job, fun(_, X) when X == JobId -> 1 end),

    ok = gen_statem:cast(Pid, {WaitRef, ok}),
    ?assertEqual(running, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec downloading_started(list()) -> atom().
downloading_started(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    PartMgrNodeId = proplists:get_value(part_mgr_node_id, Config),
    WaitRef = proplists:get_value(wait_ref, Config),
    JobId = proplists:get_value(job_id, Config),

    meck:expect(wm_virtres_handler,
                start_job_data_downloading,
                fun(X, Y, _) when X == PartMgrNodeId andalso Y == JobId -> {ok, WaitRef, ["/tmp/f1", "/tmp/f2"]} end),

    ok = gen_statem:cast(Pid, job_finished),
    ?assertEqual(downloading, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec downloading_done(list()) -> atom().
downloading_done(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    JobId = proplists:get_value(job_id, Config),
    WaitRef = proplists:get_value(wait_ref, Config),

    meck:expect(wm_virtres_handler, remove_relocation_entities, fun(X) when X == JobId -> ok end),

    ok = gen_statem:cast(Pid, {WaitRef, ok}),
    ?assertEqual(destroying, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec part_destraction_in_progress(list()) -> atom().
part_destraction_in_progress(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),
    PartExtId = proplists:get_value(part_ext_id, Config),

    ok = gen_statem:cast(Pid, {delete_in_progress, WaitRef, PartExtId}),
    ?assertEqual(destroying, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).

-spec deactivate(list()) -> atom().
deactivate(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),
    PartExtId = proplists:get_value(part_ext_id, Config),

    ok = gen_statem:cast(Pid, {partition_deleted, WaitRef, PartExtId}),
    ?assert(lists:any(fun(_) ->
                         timer:sleep(500),
                         not is_process_alive(Pid)
                      end,
                      lists:seq(1, 10))).

-spec part_exists_detete(list()) -> atom().
part_exists_detete(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assert(is_process_alive(Pid)),

    WaitRef = proplists:get_value(wait_ref, Config),

    ok = gen_statem:cast(Pid, {partition_exists, WaitRef, true}),
    ?assertEqual(destroying, gen_statem:call(Pid, get_current_state)),
    timer:sleep(1000),
    ?assert(is_process_alive(Pid)).
