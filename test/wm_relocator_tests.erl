-module(wm_relocator_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/lib/wm_entity.hrl").
-include("../include/wm_scheduler.hrl").

%% ./rebar3 eunit --module=wm_relocator_tests

-spec make_job(string(), string(), [node_id()], string()) -> #job{}.
make_job(Id, State, Nodes, SubmitTime) ->
    wm_entity:set([{id, Id},
                   {state, State},
                   {nodes, Nodes},
                   {submit_time, SubmitTime},
                   {relocatable, true},
                   {revision, 1}],
                  wm_entity:new(job)).

-spec select_jobs_waiting_for_relocation_test_() -> term().
select_jobs_waiting_for_relocation_test_() ->
    {setup,
     fun() ->
        meck:new(wm_conf, [passthrough]),
        JobActive = make_job("active", ?JOB_STATE_WAITING, ["tpl1"], "2020-01-01T00:00:00"),
        JobWait1 = make_job("wait-1", ?JOB_STATE_QUEUED, ["tpl1"], "2020-01-01T00:00:02"),
        JobWait2 = make_job("wait-2", ?JOB_STATE_WAITING, ["tpl1"], "2020-01-01T00:00:01"),
        JobNoNodes = make_job("no-nodes", ?JOB_STATE_QUEUED, [], "2020-01-01T00:00:00"),
        JobRunning = make_job("running", ?JOB_STATE_RUNNING, ["tpl1"], "2020-01-01T00:00:00"),
        AllJobs = [JobActive, JobWait1, JobWait2, JobNoNodes, JobRunning],
        meck:expect(wm_conf,
                    select,
                    fun (job, Filter) when is_function(Filter) ->
                            {ok, lists:filter(Filter, AllJobs)};
                        (node, {id, "tpl1"}) ->
                            {ok, wm_entity:set([{id, "tpl1"}, {is_template, true}], wm_entity:new(node))};
                        (relocation, {job_id, "active"}) ->
                            {ok, wm_entity:set([{id, 1}, {job_id, "active"}], wm_entity:new(relocation))};
                        (relocation, {job_id, _}) ->
                            {error, not_found};
                        (Tab, Key) ->
                            meck:passthrough([Tab, Key])
                    end),
        ok
     end,
     fun(_) -> meck:unload(wm_conf) end,
     fun(_) ->
        [{"empty limit", ?_assertEqual([], wm_relocator:select_jobs_waiting_for_relocation(0))},
         {"oldest waiting job first",
          fun() ->
             Selected = wm_relocator:select_jobs_waiting_for_relocation(1),
             ?assertEqual(["wait-2"], [wm_entity:get(id, J) || J <- Selected])
          end},
         {"respects limit and skips active relocation",
          fun() ->
             Selected = wm_relocator:select_jobs_waiting_for_relocation(10),
             ?assertEqual(["wait-2", "wait-1"], [wm_entity:get(id, J) || J <- Selected])
          end}]
     end}.
