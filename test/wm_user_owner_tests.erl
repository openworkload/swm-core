-module(wm_user_owner_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/lib/wm_entity.hrl").
-include("../include/wm_scheduler.hrl").

%% ./rebar3 eunit --module=wm_user_owner_tests

-define(OWNER_ID, "uid-owner").
-define(OTHER_ID, "uid-other").
-define(JOB_ID, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee").
-define(JOB_OTHER, "ffffffff-bbbb-cccc-dddd-eeeeeeeeeeee").
-define(SPOOL, "/tmp/swm-user-owner-eunit-spool").

-spec setup() -> ok.
setup() ->
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
    meck:expect(wm_log, access, fun(_) -> ok end),
    meck:expect(wm_log, access, fun(_, _) -> ok end),

    meck:new(wm_event, [no_link]),
    meck:expect(wm_event, subscribe, fun(_, _, _) -> ok end),
    meck:expect(wm_event, announce, fun(_, _) -> ok end),

    meck:new(wm_checkpoint, [no_link, passthrough]),
    meck:expect(wm_checkpoint, checkpoint_before_cancel, fun(Job) -> Job end),

    meck:new(wm_scheduler, [no_link]),
    meck:expect(wm_scheduler, force_schedule, fun() -> ok end),

    meck:new(wm_conf, [no_link]),
    OwnJob =
        wm_entity:set([{id, ?JOB_ID}, {user_id, ?OWNER_ID}, {state, ?JOB_STATE_QUEUED}], wm_entity:new(job)),
    OtherJob =
        wm_entity:set([{id, ?JOB_OTHER}, {user_id, ?OTHER_ID}, {state, ?JOB_STATE_QUEUED}], wm_entity:new(job)),
    meck:expect(wm_conf,
                select,
                fun (job, {id, ?JOB_ID}) ->
                        {ok, OwnJob};
                    (job, {id, ?JOB_OTHER}) ->
                        {ok, OtherJob};
                    (job, {id, _}) ->
                        {error, not_found};
                    (job, Filter) when is_function(Filter, 1) ->
                        List = lists:filter(Filter, [OwnJob, OtherJob]),
                        case List of
                            [] ->
                                {error, not_found};
                            _ ->
                                {ok, List}
                        end;
                    (Tab, Key) ->
                        error({unexpected_select, Tab, Key})
                end),
    meck:expect(wm_conf, update, fun(_) -> 1 end),

    ok =
        filelib:ensure_dir(
            filename:join(?SPOOL, "dummy")),
    case whereis(wm_user) of
        undefined ->
            ok;
        Old ->
            try
                unlink(Old)
            catch
                _:_ ->
                    ok
            end,
            try
                gen_server:stop(Old, shutdown, 2000)
            catch
                _:_ ->
                    ok
            end
    end,
    {ok, _} = wm_user:start_link([{spool, ?SPOOL}]),
    ok.

-spec cleanup(ok) -> ok.
cleanup(_) ->
    case whereis(wm_user) of
        undefined ->
            ok;
        Pid ->
            try
                unlink(Pid)
            catch
                _:_ ->
                    ok
            end,
            try
                gen_server:stop(Pid, shutdown, 2000)
            catch
                _:_ ->
                    ok
            end
    end,
    meck:unload(),
    ok.

-spec owner_matrix_test_() -> term().
owner_matrix_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
                                           [?_test(owner_can_show()),
                                            ?_test(other_forbidden_show()),
                                            ?_test(other_forbidden_stdout()),
                                            ?_test(other_forbidden_cancel()),
                                            ?_test(other_forbidden_requeue()),
                                            ?_test(missing_job_not_found()),
                                            ?_test(owner_can_cancel()),
                                            ?_test(list_jobs_filtered())]
                                       end}.

-spec owner_can_show() -> ok.
owner_can_show() ->
    ?assertMatch([#job{id = ?JOB_ID}], gen_server:call(wm_user, {show, [?JOB_ID], ?OWNER_ID})).

-spec other_forbidden_show() -> ok.
other_forbidden_show() ->
    ?assertEqual({error, forbidden}, gen_server:call(wm_user, {show, [?JOB_ID], ?OTHER_ID})).

-spec other_forbidden_stdout() -> ok.
other_forbidden_stdout() ->
    ?assertEqual({error, forbidden}, gen_server:call(wm_user, {stdout, ?JOB_ID, ?OTHER_ID})).

-spec other_forbidden_cancel() -> ok.
other_forbidden_cancel() ->
    ?assertEqual({error, forbidden}, gen_server:call(wm_user, {cancel, [?JOB_ID], ?OTHER_ID})).

-spec other_forbidden_requeue() -> ok.
other_forbidden_requeue() ->
    ?assertEqual({error, forbidden}, gen_server:call(wm_user, {requeue, [?JOB_ID], ?OTHER_ID})).

-spec missing_job_not_found() -> ok.
missing_job_not_found() ->
    Missing = "00000000-0000-0000-0000-000000000000",
    ?assertEqual({error, not_found}, gen_server:call(wm_user, {show, [Missing], ?OWNER_ID})).

-spec owner_can_cancel() -> ok.
owner_can_cancel() ->
    ?assertMatch({string, _}, gen_server:call(wm_user, {cancel, [?JOB_ID], ?OWNER_ID})).

-spec list_jobs_filtered() -> ok.
list_jobs_filtered() ->
    OwnerList = gen_server:call(wm_user, {list_jobs, ?OWNER_ID}),
    ?assertEqual(1, length(OwnerList)),
    ?assertEqual(?JOB_ID, wm_entity:get(id, hd(OwnerList))),
    OtherList = gen_server:call(wm_user, {list_jobs, ?OTHER_ID}),
    ?assertEqual(1, length(OtherList)),
    ?assertEqual(?JOB_OTHER, wm_entity:get(id, hd(OtherList))),
    Empty = gen_server:call(wm_user, {list_jobs, "uid-nobody"}),
    ?assertEqual([], Empty).
