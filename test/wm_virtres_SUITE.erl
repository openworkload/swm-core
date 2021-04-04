-module(wm_virtres_SUITE).

-export([suite/0, all/0, groups/0, init_per_group/2, end_per_group/2]).
-export([add_mocks/0]). % for debug
-export([activate/1, part_absent_create/1, part_exists_detete/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-include("../src/lib/wm_entity.hrl").

%% ============================================================================
%% Common test callbacks
%% ============================================================================

suite() ->
    [{timetrap, {seconds, 260}}].

all() ->
    [{group, create_partition}, {group, delete_partition}].

groups() ->
    [{create_partition, [], [activate, part_absent_create]}, {delete_partition, [], [activate, part_exists_detete]}].

-spec init_per_group(atom(), list()) -> list() | {skip, term()}.
init_per_group(create_partition, Config) ->
    init_test_group(create, Config);
init_per_group(delete_partition, Config) ->
    {skip, "Not implemented"}.

  %init_test_group(destroy, Config).

-spec end_per_group(atom(), list()) -> list().
end_per_group(_, Config) ->
    ok = application:stop(gun),
    wm_ct_helpers:kill_gate_system_process(),
    erlang:exit(
        proplists:get_value(virtres_pid, Config), kill),
    erlang:exit(
        proplists:get_value(gate_pid, Config), kill),
    erlang:exit(
        proplists:get_value(gate_runner_pid, Config), kill),
    Config.

%% ============================================================================
%% Helpers
%% ============================================================================

init_test_group(Action, Config) ->
    {ok, GateRunnerPid} = wm_ct_helpers:run_gate_system_process(),
    {ok, _} = application:ensure_all_started(gun),
    {ok, GatePid} = wm_gate:start([{spool, "/opt/swm/spool/"}]),
    JobId = wm_utils:uuid(v4),
    TemplateNode = wm_entity:set_attr([{name, "cloud1-flavor1"}, {is_template, true}], wm_entity:new(node)),
    add_mocks(),
    {ok, VirtResPid} = wm_virtres:start([{extra, {Action, JobId, TemplateNode}}, {task_id, wm_utils:uuid(v4)}]),
    [{gate_runner_pid, GateRunnerPid}, {gate_pid, GatePid}, {virtres_pid, VirtResPid}] ++ Config.

add_mocks() ->
    meck:new(wm_conf, [no_link]),
    Select =
        fun (job, {id, JOB_ID}) ->
                {ok, wm_entity:set_attr([{account_id, "123"}, {id, JOB_ID}], wm_entity:new(job))};
            (remote, {account_id, ACC_ID}) ->
                {ok, wm_entity:set_attr([{id, wm_utils:uuid(v4)}, {account_id, ACC_ID}], wm_entity:new(remote))};
            (credential, {remote_id, REMOTE_ID}) ->
                {ok, wm_entity:set_attr([{id, wm_utils:uuid(v4)}, {remote_id, REMOTE_ID}], wm_entity:new(credential))};
            (_, _) ->
                {error, not_found_ct}
        end,
    meck:expect(wm_conf, select, Select).

%% ============================================================================
%% Tests
%% ============================================================================

-spec activate(list()) -> atom().
activate(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ?assertEqual(sleeping, wm_ct_helpers:get_fsm_state_name(Pid)),
    ok = gen_fsm:send_event(Pid, activate),
    ?assertEqual(validating, wm_ct_helpers:get_fsm_state_name(Pid)).

-spec part_absent_create(list()) -> atom().
part_absent_create(Config) ->
    Pid = proplists:get_value(virtres_pid, Config),
    ok = gen_fsm:send_event(Pid, {partition_exists, wm_utils:uuid(v4), false}),
    ?assertEqual(creating, wm_ct_helpers:get_fsm_state_name(Pid)).

-spec part_exists_detete(list()) -> atom().
part_exists_detete(Config) ->
    todo.
