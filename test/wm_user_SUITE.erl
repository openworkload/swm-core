-module(wm_user_SUITE).

-export([suite/0, all/0, groups/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2,
         end_per_testcase/2]).
-export([parse_local_jobscript/1, submit_local_job/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-include("../src/lib/wm_entity.hrl").
-include("../include/wm_scheduler.hrl").

-define(USER_NAME, "tester").
-define(USER_ID, "uid-tester").
-define(ACCOUNT_NAME, "localhost").
-define(ACCOUNT_ID, "acc-localhost").
-define(CLUSTER_ID, "cluster-local").
-define(SPOOL, "/tmp/swm-user-ct-spool").

%% Minimal local job script (same directives as priv/examples/jobscripts/local.sh).
-define(LOCAL_JOB_SCRIPT,
        "#!/bin/sh\n"
        "#SWM name Local Container Job\n"
        "#SWM comment Container on the SkyPort host\n"
        "#SWM nodes 1\n"
        "#SWM account localhost\n"
        "#SWM flavor localhost\n"
        "#SWM container-image ubuntu:24.04\n"
        "echo hello\n").

%% ============================================================================
%% Common test callbacks
%% ============================================================================

-spec suite() -> list().
suite() ->
    [{timetrap, {seconds, 30}}].

-spec all() -> list().
all() ->
    [{group, local_submit}].

-spec groups() -> list().
groups() ->
    [{local_submit, [], [parse_local_jobscript, submit_local_job]}].

-spec init_per_suite(list()) -> list().
init_per_suite(Config) ->
    meck:new(wm_log, [no_link, passthrough]),
    meck:expect(wm_log, debug, fun(_) -> ok end),
    meck:expect(wm_log, debug, fun(_, _) -> ok end),
    meck:expect(wm_log, info, fun(_) -> ok end),
    meck:expect(wm_log, info, fun(_, _) -> ok end),
    meck:expect(wm_log, note, fun(_) -> ok end),
    meck:expect(wm_log, note, fun(_, _) -> ok end),
    meck:expect(wm_log, warn, fun(_) -> ok end),
    meck:expect(wm_log, warn, fun(_, _) -> ok end),
    meck:expect(wm_log, err, fun(_) -> ok end),
    meck:expect(wm_log, err, fun(_, _) -> ok end),
    meck:expect(wm_log, fatal, fun(_) -> ok end),
    meck:expect(wm_log, fatal, fun(_, _) -> ok end),

    meck:new(wm_event, [no_link]),
    meck:expect(wm_event, subscribe, fun(_, _, _) -> ok end),

    meck:new(wm_conf, [no_link]),
    meck:new(wm_topology, [no_link]),
    meck:expect(wm_topology, get_subdiv, fun(cluster) ->
                                            wm_entity:set([{id, ?CLUSTER_ID}], wm_entity:new(cluster))
                                         end),

    ok = filelib:ensure_dir(filename:join(?SPOOL, "dummy")),
    Config.

-spec end_per_suite(list()) -> list().
end_per_suite(Config) ->
    meck:unload(),
    Config.

-spec init_per_testcase(atom(), list()) -> list().
init_per_testcase(_, Config) ->
    User = wm_entity:set([{id, ?USER_ID}, {name, ?USER_NAME}], wm_entity:new(user)),
    Account = wm_entity:set([{id, ?ACCOUNT_ID}, {name, ?ACCOUNT_NAME}], wm_entity:new(account)),
    meck:expect(wm_conf,
                select,
                fun (user, {name, ?USER_NAME}) ->
                        {ok, User};
                    (account, {name, ?ACCOUNT_NAME}) ->
                        {ok, Account};
                    (Tab, Key) ->
                        ct:fail({unexpected_select, Tab, Key})
                end),
    meck:expect(wm_conf, update, fun(_) -> 1 end),

    %% Start per testcase: gen_server exits when its start_link parent dies, and
    %% init_per_suite's process does not outlive the suite setup.
    case whereis(wm_user) of
        undefined ->
            ok;
        OldPid ->
            try
                unlink(OldPid)
            catch
                _:_ ->
                    ok
            end,
            try
                gen_server:stop(OldPid, shutdown, 5000)
            catch
                _:_ ->
                    ok
            end
    end,
    {ok, Pid} = wm_user:start_link([{spool, ?SPOOL}]),
    ct:print("wm_user started: ~p", [Pid]),
    [{wm_user_pid, Pid} | Config].

-spec end_per_testcase(atom(), list()) -> list().
end_per_testcase(_, Config) ->
    case proplists:get_value(wm_user_pid, Config) of
        Pid when is_pid(Pid) ->
            try
                unlink(Pid)
            catch
                _:_ ->
                    ok
            end,
            try
                gen_server:stop(Pid, shutdown, 5000)
            catch
                _:_ ->
                    ok
            end;
        _ ->
            ok
    end,
    Config.

%% ============================================================================
%% Tests
%% ============================================================================

-spec parse_local_jobscript(list()) -> ok.
parse_local_jobscript(_Config) ->
    Job = wm_jobscript:parse(?LOCAL_JOB_SCRIPT),
    ?assertEqual("Local Container Job", wm_entity:get(name, Job)),
    ?assertEqual(?ACCOUNT_ID, wm_entity:get(account_id, Job)),
    Request = wm_entity:get(request, Job),
    ?assertMatch(#resource{name = "node", count = 1}, lists:keyfind("node", 2, Request)),
    ?assertEqual({ok, "localhost"}, wm_utils:find_property_in_resource("flavor", value, Request)),
    ?assertEqual({ok, "ubuntu:24.04"},
                 wm_utils:find_property_in_resource("container-image", value, Request)),
    ?assertEqual(false, lists:keyfind("cloud-image", 2, Request)),
    ok.

-spec submit_local_job(list()) -> ok.
submit_local_job(_Config) ->
    Self = self(),
    meck:expect(wm_conf,
                update,
                fun (#job{} = Job) ->
                        Self ! {job_saved, Job},
                        1;
                    (Other) ->
                        ct:fail({unexpected_update, Other})
                end),

    {string, JobId} =
        gen_server:call(wm_user, {submit, ?LOCAL_JOB_SCRIPT, "/tmp/local.sh", ?USER_NAME, "127.0.0.1"}),
    ?assert(is_list(JobId) andalso length(JobId) > 0),

    Job =
        receive
            {job_saved, Saved} ->
                Saved
        after 5000 ->
            ct:fail(job_not_saved)
        end,

    ?assertEqual(JobId, wm_entity:get(id, Job)),
    ?assertEqual(?JOB_STATE_QUEUED, wm_entity:get(state, Job)),
    ?assertEqual("Submitted", wm_entity:get(state_details, Job)),
    ?assertEqual(?USER_ID, wm_entity:get(user_id, Job)),
    ?assertEqual(?ACCOUNT_ID, wm_entity:get(account_id, Job)),
    ?assertEqual(?CLUSTER_ID, wm_entity:get(cluster_id, Job)),
    ?assertEqual("Local Container Job", wm_entity:get(name, Job)),

    Request = wm_entity:get(request, Job),
    ?assertMatch(#resource{name = "node", count = 1}, lists:keyfind("node", 2, Request)),
    ?assertMatch(#resource{name = "cpus", count = 1}, lists:keyfind("cpus", 2, Request)),
    ?assertEqual({ok, "localhost"}, wm_utils:find_property_in_resource("flavor", value, Request)),
    ?assertEqual({ok, "ubuntu:24.04"},
                 wm_utils:find_property_in_resource("container-image", value, Request)),
    ?assertEqual({ok, "127.0.0.1"},
                 wm_utils:find_property_in_resource("submission-address", value, Request)),
    %% Local jobs must not request a cloud VM image (that path uses the gate).
    ?assertEqual(false, lists:keyfind("cloud-image", 2, Request)),
    ok.
