-module(wm_job_metrics_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_job_metrics_tests

-define(JOB_ID, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee").

-spec metrics_test_() -> term().
metrics_test_() ->
    {setup,
     fun() ->
        {ok, _} = application:ensure_all_started(prometheus),
        ok = wm_job_metrics:declare()
     end,
     fun(_) -> ok end,
     [fun observe_sets_gauges/0, fun scrape_contains_metric_names/0]}.

-spec promql_test_() -> term().
promql_test_() ->
    {setup,
     fun() ->
        ok = meck:new(wm_conf, [passthrough, no_link]),
        ok = meck:new(gun, [passthrough, no_link]),
        meck:expect(wm_conf,
                    g,
                    fun (prometheus_url, _) ->
                            "http://127.0.0.1:9090";
                        (K, D) ->
                            meck:passthrough([K, D])
                    end),
        ok
     end,
     fun(_) ->
        meck:unload(gun),
        meck:unload(wm_conf)
     end,
     [fun promql_parses_vector_value/0,
      fun promql_empty_result_is_null/0,
      fun query_job_stats_builds_map/0,
      fun query_job_stats_unknown_job/0]}.

-spec observe_sets_gauges() -> ok.
observe_sets_gauges() ->
    ok =
        wm_job_metrics:observe(<<"job-abc">>,
                               <<"node1">>,
                               #{cpu_percent => 12.5,
                                 cpu_percent_max => 40.0,
                                 mem_bytes => 1024,
                                 mem_bytes_max => 2048}),
    Text = binary_to_list(wm_job_metrics:scrape_reply()),
    ?assertNotEqual(nomatch, string:find(Text, "swm_job_cpu_percent{")),
    ?assertNotEqual(nomatch, string:find(Text, "job_id=\"job-abc\"")),
    ?assertNotEqual(nomatch, string:find(Text, "node=\"node1\"")),
    ?assertNotEqual(nomatch, string:find(Text, "swm_job_mem_bytes_max{")).

-spec scrape_contains_metric_names() -> ok.
scrape_contains_metric_names() ->
    Text = binary_to_list(wm_job_metrics:scrape_reply()),
    lists:foreach(fun(Name) -> ?assertNotEqual(nomatch, string:find(Text, Name)) end,
                  ["swm_job_cpu_percent",
                   "swm_job_cpu_percent_max",
                   "swm_job_mem_bytes",
                   "swm_job_mem_bytes_max",
                   "swm_job_gpu_util_percent",
                   "swm_job_gpu_mem_bytes"]).

-spec promql_parses_vector_value() -> ok.
promql_parses_vector_value() ->
    Body =
        <<"{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[",
          "{\"metric\":{},\"value\":[1,\"42.5\"]}]}}">>,
    mock_gun_ok(Body),
    ?assertEqual({ok, 42.5}, wm_job_metrics:promql_query("swm_job_cpu_percent")).

-spec promql_empty_result_is_null() -> ok.
promql_empty_result_is_null() ->
    Body = <<"{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[]}}">>,
    mock_gun_ok(Body),
    ?assertEqual({ok, null}, wm_job_metrics:promql_query("swm_job_cpu_percent")).

-spec query_job_stats_builds_map() -> ok.
query_job_stats_builds_map() ->
    %% Return a distinct numeric for each PromQL call (8 queries).
    Counter = counters:new(1, []),
    Values = [10.0, 20.0, 100.0, 200.0, 1.0, 2.0, 3.0, 4.0],
    meck:expect(gun, open, fun(_, _, _) -> {ok, self()} end),
    meck:expect(gun, await_up, fun(_, _) -> {ok, http} end),
    meck:expect(gun, get, fun(_, _) -> make_ref() end),
    meck:expect(gun, await, fun(_, _, _) -> {response, nofin, 200, []} end),
    meck:expect(gun,
                await_body,
                fun(_, _, _) ->
                   I = counters:get(Counter, 1),
                   counters:add(Counter, 1, 1),
                   N = lists:nth(I + 1, Values),
                   Val = list_to_binary(io_lib:format("~p", [N])),
                   Body =
                       iolist_to_binary([<<"{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[",
                                           "{\"metric\":{},\"value\":[1,\"">>,
                                         Val,
                                         <<"\"]}]}}">>]),
                   {ok, Body}
                end),
    meck:expect(gun, close, fun(_) -> ok end),
    Job = wm_entity:set([{id, ?JOB_ID}, {start_time, "2026-01-01T00:00:00"}, {end_time, "2026-01-01T00:10:00"}],
                        wm_entity:new(job)),
    {ok, Stats} = wm_job_metrics:query_job_stats(Job),
    ?assertEqual(list_to_binary(?JOB_ID), maps:get(<<"job_id">>, Stats)),
    ?assertEqual(#{<<"avg">> => 10.0, <<"max">> => 20.0}, maps:get(<<"cpu_percent">>, Stats)),
    ?assertEqual(#{<<"avg">> => 100.0, <<"max">> => 200.0}, maps:get(<<"mem_bytes">>, Stats)),
    ?assertEqual(#{<<"avg">> => 1.0, <<"max">> => 2.0}, maps:get(<<"gpu_util_percent">>, Stats)),
    ?assertEqual(#{<<"avg">> => 3.0, <<"max">> => 4.0}, maps:get(<<"gpu_mem_bytes">>, Stats)),
    Enc = wm_json:encode(Stats),
    ?assertNotEqual(nomatch, binary:match(Enc, <<"\"cpu_percent\"">>)).

-spec query_job_stats_unknown_job() -> ok.
query_job_stats_unknown_job() ->
    meck:expect(wm_conf, select, fun(job, {id, _}) -> {error, not_found} end),
    ?assertEqual({error, not_found}, wm_job_metrics:query_job_stats(?JOB_ID)).

%% ============================================================================
%% Helpers
%% ============================================================================

-spec mock_gun_ok(binary()) -> ok.
mock_gun_ok(Body) ->
    meck:expect(gun, open, fun(_, _, _) -> {ok, self()} end),
    meck:expect(gun, await_up, fun(_, _) -> {ok, http} end),
    meck:expect(gun, get, fun(_, _) -> make_ref() end),
    meck:expect(gun, await, fun(_, _, _) -> {response, nofin, 200, []} end),
    meck:expect(gun, await_body, fun(_, _, _) -> {ok, Body} end),
    meck:expect(gun, close, fun(_) -> ok end).
