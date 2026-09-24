-module(wm_container_cfg_SUITE).

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([entrypoint_default_no_tini/1, entrypoint_override/1, finalize_prefers_container_env/1, run_steps_podman/1,
         podman_sock_override/1, cdi_missing_msg/1, require_crun_default/1, cdi_unavailable_without_specs/1,
         cdi_available_with_nvidia_json/1, communicate_steps_podman/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-define(GPU_CDI_MISSING_MSG, "GPU job requires NVIDIA CDI on the compute node, but CDI was not available").
-define(ENV_KEYS,
        ["SWM_CONTAINER_ENTRYPOINT",
         "SWM_CONTAINER_FINALIZE",
         "SWM_FINALIZE_IN_CONTAINER",
         "SWM_CONTAINER_PODMAN_SOCK",
         "SWM_CONTAINER_REQUIRE_CRUN",
         "SWM_CONTAINER_CDI_PATHS"]).

%% ============================================================================
%% Common test callbacks
%% ============================================================================

-spec suite() -> list().
suite() ->
    [{timetrap, {seconds, 10}}].

-spec all() -> [atom()].
all() ->
    [entrypoint_default_no_tini,
     entrypoint_override,
     finalize_prefers_container_env,
     run_steps_podman,
     podman_sock_override,
     cdi_missing_msg,
     require_crun_default,
     cdi_unavailable_without_specs,
     cdi_available_with_nvidia_json,
     communicate_steps_podman].

-spec init_per_suite(list()) -> list().
init_per_suite(Config) ->
    Config.

-spec end_per_suite(list()) -> list().
end_per_suite(Config) ->
    Config.

-spec init_per_testcase(atom(), list()) -> list().
init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun(K) -> os:unsetenv(K) end, ?ENV_KEYS),
    Config.

-spec end_per_testcase(atom(), list()) -> list().
end_per_testcase(_TestCase, Config) ->
    lists:foreach(fun(K) -> os:unsetenv(K) end, ?ENV_KEYS),
    Config.

%% ============================================================================
%% Test cases
%% ============================================================================

entrypoint_default_no_tini(_Config) ->
    ?assertEqual(undefined, wm_container_cfg:entrypoint()).

entrypoint_override(_Config) ->
    true = os:putenv("SWM_CONTAINER_ENTRYPOINT", "catatonit --"),
    ?assertEqual([<<"catatonit">>, <<"--">>], wm_container_cfg:entrypoint()).

finalize_prefers_container_env(_Config) ->
    true = os:putenv("SWM_FINALIZE_IN_CONTAINER", "/old/finalize.sh"),
    true = os:putenv("SWM_CONTAINER_FINALIZE", "/new/finalize.sh"),
    ?assertEqual("/new/finalize.sh", wm_container_cfg:finalize_script()).

run_steps_podman(_Config) ->
    ?assertEqual([create, attach, start, create_exec, start_exec, return_started], wm_podman:run_steps()).

podman_sock_override(_Config) ->
    true = os:putenv("SWM_CONTAINER_PODMAN_SOCK", "/tmp/test-podman.sock"),
    ?assertEqual("/tmp/test-podman.sock", wm_container_cfg:podman_sock()).

cdi_missing_msg(_Config) ->
    ?assertEqual(?GPU_CDI_MISSING_MSG, wm_container_cfg:gpu_cdi_missing_msg()).

require_crun_default(_Config) ->
    ?assertEqual(true, wm_container_cfg:require_crun()).

cdi_unavailable_without_specs(_Config) ->
    true = os:putenv("SWM_CONTAINER_CDI_PATHS", "/tmp/swm-cdi-empty-test-dir-noexist"),
    ?assertEqual(false, wm_container_cfg:cdi_available()).

cdi_available_with_nvidia_json(_Config) ->
    Dir = "/tmp/swm-cdi-test-" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = file:make_dir(Dir),
    try
        ok =
            file:write_file(
                filename:join(Dir, "nvidia.com-gpu.json"), <<"{}\n">>),
        true = os:putenv("SWM_CONTAINER_CDI_PATHS", Dir),
        ?assertEqual(true, wm_container_cfg:cdi_available())
    after
        _ = file:delete(
                filename:join(Dir, "nvidia.com-gpu.json")),
        _ = file:del_dir(Dir)
    end.

communicate_steps_podman(_Config) ->
    Bin = <<"x">>,
    ?assertMatch([attach_ws, {send, Bin}, return_sent], wm_podman:communicate_steps(Bin)).
