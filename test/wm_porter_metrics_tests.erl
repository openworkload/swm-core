-module(wm_porter_metrics_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_porter_metrics_tests

wm_porter_metrics_test_() ->
    [fun metrics_env_default_no_gpu/0, fun metrics_env_with_gpus/0, fun log_job_metrics_api/0].

fake_job(GpuCount) ->
    ContImg =
        wm_entity:set([{name, "container-image"}, {count, 1}, {properties, [{value, "ubuntu:24.04"}]}],
                      wm_entity:new(resource)),
    Request =
        case GpuCount > 0 of
            true ->
                Gpus = wm_entity:set([{name, "gpus"}, {count, GpuCount}, {properties, []}], wm_entity:new(resource)),
                [ContImg, Gpus];
            false ->
                [ContImg]
        end,
    wm_entity:set([{id, "metrics-job"}, {request, Request}, {env, []}, {nodes, []}, {account_id, []}],
                  wm_entity:new(job)).

metrics_env_default_no_gpu() ->
    Env = wm_porter_protocol:metrics_env(fake_job(0)),
    ?assertEqual("0", proplists:get_value("SWM_METRICS_GPU", Env)),
    Interval = proplists:get_value("SWM_METRICS_INTERVAL_MS", Env),
    ?assert(is_list(Interval) andalso list_to_integer(Interval) >= 0).

metrics_env_with_gpus() ->
    Env = wm_porter_protocol:metrics_env(fake_job(2)),
    ?assertEqual("1", proplists:get_value("SWM_METRICS_GPU", Env)).

log_job_metrics_api() ->
    %% Cast-only API; must not crash when accounting is not started.
    ok =
        wm_accounting:log_job_metrics("job-1",
                                      #{cpu_percent => 1.5,
                                        mem_bytes => 1024,
                                        ts => 1},
                                      node@localhost).
