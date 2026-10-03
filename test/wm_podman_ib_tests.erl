-module(wm_podman_ib_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

-define(ENV_KEYS, ["SWM_CONTAINER_CDI_PATHS", "SWM_CONTAINER_RDMA_CDI", "SWM_CONTAINER_IB_DEV_DIR", "SWM_ROOT"]).

clear_env() ->
    lists:foreach(fun(K) -> os:unsetenv(K) end, ?ENV_KEYS),
    ok.

wm_podman_ib_test_() ->
    {foreach,
     fun clear_env/0,
     fun(_) -> clear_env() end,
     [fun create_json_gpu_and_ib_cdi/0, fun create_json_ib_devices_fallback/0, fun create_json_no_ib_without_host/0]}.

fake_job(GpuCount) ->
    true = os:putenv("SWM_ROOT", "/tmp"),
    ContImg =
        wm_entity:set([{name, "container-image"}, {count, 1}, {properties, [{value, "ubuntu:24.04"}]}],
                      wm_entity:new(resource)),
    Gpus = wm_entity:set([{name, "gpus"}, {count, GpuCount}, {properties, []}], wm_entity:new(resource)),
    wm_entity:set([{id, "test-job-ib"}, {container, "swm-test-ib"}, {request, [ContImg, Gpus]}, {env, []}],
                  wm_entity:new(job)).

create_json_gpu_and_ib_cdi() ->
    Dir = "/tmp/swm-podman-ib-cdi-" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = file:make_dir(Dir),
    try
        ok =
            file:write_file(
                filename:join(Dir, "nvidia.com-gpu.json"), <<"{}\n">>),
        ok =
            file:write_file(
                filename:join(Dir, "rdma.com-ib.json"), <<"{}\n">>),
        true = os:putenv("SWM_CONTAINER_CDI_PATHS", Dir),
        Job = fake_job(1),
        Bin = wm_podman:generate_create_json(Job, "/opt/swm/current/bin/swm-porter", "swm-test-ib"),
        Map = wm_json:decode(Bin),
        Cdi = maps:get(<<"cdi_devices">>, Map),
        Names = [maps:get(<<"Name">>, D) || D <- Cdi],
        ?assert(lists:member(<<"nvidia.com/gpu=all">>, Names)),
        ?assert(lists:member(<<"rdma.com/ib=all">>, Names)),
        ?assertEqual([<<"IPC_LOCK">>], maps:get(<<"cap_add">>, Map)),
        Rlimits = maps:get(<<"r_limits">>, Map),
        ?assert(lists:any(fun(R) -> maps:get(<<"type">>, R) =:= <<"MEMLOCK">> end, Rlimits))
    after
        _ = file:delete(
                filename:join(Dir, "nvidia.com-gpu.json")),
        _ = file:delete(
                filename:join(Dir, "rdma.com-ib.json")),
        _ = file:del_dir(Dir)
    end.

create_json_ib_devices_fallback() ->
    %% No RDMA CDI; only SWM_CONTAINER_RDMA_CDI empty and fake devices via override of detection
    %% is hard without /dev/infiniband. Use env CDI name empty + force via RDMA env after
    %% clearing paths so ib_host_supported is from env.
    true = os:putenv("SWM_CONTAINER_CDI_PATHS", "/tmp/swm-cdi-empty-noexist"),
    true = os:putenv("SWM_CONTAINER_RDMA_CDI", "rdma.com/ib=all"),
    Job = fake_job(0),
    Bin = wm_podman:generate_create_json(Job, "/opt/swm/current/bin/swm-porter", "swm-test-ib2"),
    Map = wm_json:decode(Bin),
    ?assertEqual([<<"IPC_LOCK">>], maps:get(<<"cap_add">>, Map)),
    Cdi = maps:get(<<"cdi_devices">>, Map),
    ?assertEqual([<<"rdma.com/ib=all">>], [maps:get(<<"Name">>, D) || D <- Cdi]).

create_json_no_ib_without_host() ->
    %% Isolate from host /dev/infiniband (present on some GHA Azure runners).
    true = os:putenv("SWM_CONTAINER_CDI_PATHS", "/tmp/swm-cdi-empty-noexist"),
    true = os:putenv("SWM_CONTAINER_IB_DEV_DIR", "/tmp/swm-ib-empty-noexist"),
    Job = fake_job(0),
    Bin = wm_podman:generate_create_json(Job, "/opt/swm/current/bin/swm-porter", "swm-test-noib"),
    Map = wm_json:decode(Bin),
    ?assertEqual(error, maps:find(<<"cap_add">>, Map)),
    ?assertEqual(error, maps:find(<<"cdi_devices">>, Map)).
