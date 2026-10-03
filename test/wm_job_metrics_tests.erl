-module(wm_job_metrics_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_job_metrics_tests

-spec metrics_test_() -> term().
metrics_test_() ->
    {setup,
     fun() ->
        {ok, _} = application:ensure_all_started(prometheus),
        ok = wm_job_metrics:declare()
     end,
     fun(_) -> ok end,
     [fun observe_sets_gauges/0, fun scrape_contains_metric_names/0]}.

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

scrape_contains_metric_names() ->
    Text = binary_to_list(wm_job_metrics:scrape_reply()),
    lists:foreach(fun(Name) -> ?assertNotEqual(nomatch, string:find(Text, Name)) end,
                  ["swm_job_cpu_percent",
                   "swm_job_cpu_percent_max",
                   "swm_job_mem_bytes",
                   "swm_job_mem_bytes_max",
                   "swm_job_gpu_util_percent",
                   "swm_job_gpu_mem_bytes"]).
