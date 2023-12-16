-module(wm_gate_SUITE).

-export([suite/0, all/0, groups/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([list_images/1, get_image/1, list_flavors/1, list_partitions/1, get_partition/1, create_partition/1,
         delete_partition/1, partition_exists/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-include("../src/lib/wm_entity.hrl").

-define(SWM_SPOOL, "/opt/swm/spool/").

%% ============================================================================
%% Common test callbacks
%% ============================================================================

-spec suite() -> list().
suite() ->
    [{timetrap, {seconds, 260}}].

-spec all() -> list().
all() ->
    [{group, common}].

-spec groups() -> list().
groups() ->
    [{common,
      [],
      [list_images,
       get_image,
       list_flavors,
       list_partitions,
       get_partition,
       create_partition,
       delete_partition,
       partition_exists]}].

-spec init_per_suite(list()) -> list().
init_per_suite(Config) ->
    {ok, GateRunnerPid} = wm_ct_helpers:run_gate_system_process(),
    {ok, _} = application:ensure_all_started(gun),
    [{gate_runner_pid, GateRunnerPid} | Config].

-spec end_per_suite(list()) -> list().
end_per_suite(Config) ->
    ok = application:stop(gun),
    wm_ct_helpers:kill_gate_system_process(),
    erlang:exit(
        proplists:get_value(gate_runner_pid, Config), kill),
    Config,
    meck:unload().

-spec init_per_testcase(atom(), [{atom(), term()}]) -> [{atom(), term()}] | {fail, term()} | {skip, term()}.
init_per_testcase(_, Config) ->
    {ok, Pid} = wm_gate:start_link([{spool, ?SWM_SPOOL}]),
    ct:print("Gate has been started: ~p", [Pid]),
    [{wm_gate_pid, Pid} | Config].

-spec end_per_testcase(atom(), [{atom(), term()}]) -> [{atom(), term()}] | {fail, term()} | {skip, term()}.
end_per_testcase(_, Config) ->
    %erlang:exit(proplists:get_value(wm_gate_pid, Config), kill),
    Config.

%% ============================================================================
%% Helpers
%% ============================================================================

-spec get_remote() -> #remote{}.
get_remote() ->
    {ok, Hostname} = inet:gethostname(),
    wm_entity:set([{id, "0b1ee0b0-4db5-11eb-a18a-f7f7d5c0f982"},
                   {name, "local-gate-test"},
                   {kind, openstack},
                   {server, Hostname},
                   {port, 8444},
                   {account_id, "accid123"}],
                  wm_entity:new(remote)).

-spec get_creds() -> #credential{}.
get_creds() ->
    wm_entity:set([{id, "3ad32b68-4dba-11eb-b356-03875fd306d5"},
                   {remote_id, "0b1ee0b0-4db5-11eb-a18a-f7f7d5c0f982"},
                   {username, "demo1"},
                   {password, "demo1"}],
                  wm_entity:new(credential)).

%% ============================================================================
%% Tests
%% ============================================================================

-spec list_images(list()) -> atom().
list_images(_Config) ->
    Remote = get_remote(),
    {ok, Ref} = wm_gate:list_images(self(), Remote, get_creds()),
    ExpectedImages =
        [wm_entity:set([{id, "i1"},
                        {name, "image1"},
                        {status, "creating"},
                        {created, ""},
                        {remote_id, wm_entity:get(id, Remote)},
                        {updated, ""},
                        {kind, cloud}],
                       wm_entity:new(image)),
         wm_entity:set([{id, "i2"},
                        {name, "cirros"},
                        {status, "created"},
                        {remote_id, wm_entity:get(id, Remote)},
                        {created, ""},
                        {updated, ""},
                        {kind, cloud}],
                       wm_entity:new(image))],
    ?assertEqual({list_images, Ref, ExpectedImages}, wm_utils:await(list_images, Ref, 2000)).

-spec get_image(list()) -> atom().
get_image(_Config) ->
    {ok, Ref1} = wm_gate:get_image(self(), get_remote(), get_creds(), "i2"),
    ExpectedImage =
        wm_entity:set([{id, "i2"}, {name, "cirros"}, {status, "created"}, {created, ""}, {updated, ""}, {kind, cloud}],
                      wm_entity:new(image)),
    ?assertEqual({get_image, Ref1, ExpectedImage}, wm_utils:await(get_image, Ref1, 2000)),
    {ok, Ref2} = wm_gate:get_image(self(), get_remote(), get_creds(), "foo"),
    ?assertMatch({error, Ref2, _}, wm_utils:await(get_image, Ref2, 2000)),
    {ok, Ref3} = wm_gate:get_image(self(), get_remote(), get_creds(), ""),
    ?assertMatch({error, Ref3, _}, wm_utils:await(get_image, Ref3, 2000)).

-spec list_flavors(list()) -> atom().
list_flavors(_Config) ->
    {ok, Ref} = wm_gate:list_flavors(self(), get_remote(), get_creds()),
    Result = wm_utils:await(list_flavors, Ref, 2000),
    ?assertMatch({list_flavors, Ref, _}, Result),
    {_, _, FlavorNodes} = Result,
    ?assertEqual(2, length(FlavorNodes)),
    Node1 = lists:nth(1, FlavorNodes),
    Node2 = lists:nth(2, FlavorNodes),
    ?assertEqual("flavor1", wm_entity:get(name, Node1)),
    ?assertEqual("flavor2", wm_entity:get(name, Node2)),
    ?assertEqual(#{"accid123" => 3.0}, wm_entity:get(prices, Node1)),
    ?assertEqual(#{"accid123" => 8.0}, wm_entity:get(prices, Node2)),
    ?assertEqual(3, length(wm_entity:get(resources, Node1))),
    ?assertEqual(3, length(wm_entity:get(resources, Node2))).

-spec list_partitions(list()) -> atom().
list_partitions(_Config) ->
    {ok, Ref} = wm_gate:list_partitions(self(), get_remote(), get_creds()),
    Result = wm_utils:await(list_partitions, Ref, 2000),
    ?assertMatch({list_partitions, Ref, _}, Result),
    {_, _, Partitions} = Result,
    ct:print("Partitions: ~p", [Partitions]),
    ?assertEqual(2, length(Partitions)),
    Part1 = lists:nth(1, Partitions),
    Part2 = lists:nth(2, Partitions),
    ?assertEqual("stack1", wm_entity:get(name, Part1)),
    ?assertEqual("stack2", wm_entity:get(name, Part2)),
    ?assertEqual(creating, wm_entity:get(state, Part1)),
    ?assertEqual(up, wm_entity:get(state, Part2)).

-spec get_partition(list()) -> atom().
get_partition(_Config) ->
    {ok, Ref1} = wm_gate:get_partition(self(), get_remote(), get_creds(), "s2"),
    ExpectedPartition =
        wm_entity:set([{name, "stack2"},
                       {state, up},
                       {external_id, "s2"},
                       {created, "2020-11-12T10:00:00"},
                       {updated, "2021-01-02T11:18:39"},
                       {addresses,
                        #{compute_instances_ips => ["10.0.0.102"],
                          master_private_ip => "10.0.0.101",
                          master_public_ip => "172.28.128.154"}},
                       {comment, "Test stack 2"}],
                      wm_entity:new(partition)),

    % NOTE: partition ID is a new on each run
    RetrievedData = wm_utils:await(partition_fetched, Ref1, 2000),
    ?assertMatch({partition_fetched, Ref1, _}, RetrievedData),

    {_, _, RetrievedPartition} = RetrievedData,
    ExpectedPartitionWithId = ExpectedPartition#partition{id = RetrievedPartition#partition.id},
    ?assertEqual(ExpectedPartitionWithId, RetrievedPartition),

    {ok, Ref2} = wm_gate:get_partition(self(), get_remote(), get_creds(), "foo"),
    ?assertMatch({error, Ref2, _}, wm_utils:await(partition_fetched, Ref2, 2000)),

    {ok, Ref3} = wm_gate:get_partition(self(), get_remote(), get_creds(), ""),
    ?assertMatch({error, Ref3, _}, wm_utils:await(partition_fetched, Ref3, 2000)).

-spec create_partition(list()) -> atom().
create_partition(_Config) ->
    Options =
        #{part_name => "stack42",
          flavor_name => "flavor1",
          image_name => "ubuntu22.04",
          tenant_name => "dude",
          key_name => "key1",
          job_id => "40565124-9c03-11ee-8ca4-633064256ed4",
          count => 1},
    {ok, Ref1} = wm_gate:create_partition(self(), get_remote(), get_creds(), Options),
    ?assertMatch({partition_spawned, Ref1, _}, wm_utils:await(partition_spawned, Ref1, 2000)).

-spec delete_partition(list()) -> atom().
delete_partition(_Config) ->
    {ok, Ref1} = wm_gate:delete_partition(self(), get_remote(), get_creds(), "s2"),
    ?assertMatch({partition_deleted, Ref1, "Deletion started"}, wm_utils:await(partition_deleted, Ref1, 2000)).

-spec partition_exists(list()) -> atom().
partition_exists(_Config) ->
    {ok, Ref1} = wm_gate:partition_exists(self(), get_remote(), get_creds(), "s1"),
    ?assertMatch({partition_exists, Ref1, true}, wm_utils:await(partition_exists, Ref1, 2000)),
    {ok, Ref2} = wm_gate:partition_exists(self(), get_remote(), get_creds(), "foo"),
    ?assertMatch({partition_exists, Ref2, false}, wm_utils:await(partition_exists, Ref2, 2000)).
