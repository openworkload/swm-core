-module(wm_container_cfg_tests).

-include_lib("eunit/include/eunit.hrl").

-define(GPU_CDI_MISSING_MSG, "GPU job requires NVIDIA CDI on the compute node, but CDI was not available").
-define(ENV_KEYS,
        ["SWM_CONTAINER_ENTRYPOINT",
         "SWM_CONTAINER_FINALIZE",
         "SWM_FINALIZE_IN_CONTAINER",
         "SWM_CONTAINER_PODMAN_SOCK",
         "SWM_CONTAINER_REQUIRE_CRUN",
         "SWM_CONTAINER_CDI_PATHS"]).

%% ============================================================================
%% Fixtures
%% ============================================================================

clear_env() ->
    lists:foreach(fun(K) -> os:unsetenv(K) end, ?ENV_KEYS),
    ok.

%% ============================================================================
%% Tests
%% ============================================================================

wm_container_cfg_test_() ->
    {foreach,
     fun clear_env/0,
     fun(_) -> clear_env() end,
     [fun entrypoint_default_no_tini/0,
      fun entrypoint_override/0,
      fun finalize_prefers_container_env/0,
      fun run_steps_podman/0,
      fun communicate_steps_podman/0,
      fun podman_sock_override/0,
      fun cdi_missing_msg/0,
      fun require_crun_default/0,
      fun cdi_unavailable_without_specs/0,
      fun cdi_available_with_nvidia_json/0]}.

entrypoint_default_no_tini() ->
    ?assertEqual(undefined, wm_container_cfg:entrypoint()).

entrypoint_override() ->
    true = os:putenv("SWM_CONTAINER_ENTRYPOINT", "catatonit --"),
    ?assertEqual([<<"catatonit">>, <<"--">>], wm_container_cfg:entrypoint()).

finalize_prefers_container_env() ->
    true = os:putenv("SWM_FINALIZE_IN_CONTAINER", "/old/finalize.sh"),
    true = os:putenv("SWM_CONTAINER_FINALIZE", "/new/finalize.sh"),
    ?assertEqual("/new/finalize.sh", wm_container_cfg:finalize_script()).

run_steps_podman() ->
    ?assertEqual([create, start, return_started], wm_podman:run_steps()).

communicate_steps_podman() ->
    Bin = <<"x">>,
    ?assertEqual([attach_ws, {send, Bin}, return_sent, create_exec, start_exec],
                 wm_podman:communicate_steps(Bin)).

podman_sock_override() ->
    true = os:putenv("SWM_CONTAINER_PODMAN_SOCK", "/tmp/test-podman.sock"),
    ?assertEqual("/tmp/test-podman.sock", wm_container_cfg:podman_sock()).

cdi_missing_msg() ->
    ?assertEqual(?GPU_CDI_MISSING_MSG, wm_container_cfg:gpu_cdi_missing_msg()).

require_crun_default() ->
    ?assertEqual(true, wm_container_cfg:require_crun()).

cdi_unavailable_without_specs() ->
    true = os:putenv("SWM_CONTAINER_CDI_PATHS", "/tmp/swm-cdi-empty-test-dir-noexist"),
    ?assertEqual(false, wm_container_cfg:cdi_available()).

cdi_available_with_nvidia_json() ->
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
