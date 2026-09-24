%%% @doc Container runtime configuration helpers.
%%% Prefer SWM_CONTAINER_* env vars; fall back to legacy SWM_DOCKER_* /
%%% SWM_FINALIZE_IN_CONTAINER names during the Docker -> Podman transition.
-module(wm_container_cfg).

-export([finalize_script/0, entrypoint/0, volumes_from/0, getenv_first/2, podman_sock/0,
         podman_api_prefix/0, require_crun/0, cdi_available/0, cdi_dirs/0, extra_binds/0,
         gpu_cdi_missing_msg/0]).

-include_lib("eunit/include/eunit.hrl").

-define(DEFAULT_FINALIZE, "/opt/swm/current/scripts/swm-container-finalize.sh").
-define(DEFAULT_API_PREFIX, "/v5.0.0/libpod").
-define(GPU_CDI_MISSING_MSG,
        "GPU job requires NVIDIA CDI on the compute node, but CDI was not available").

%% @doc Absolute path to the in-container finalize script.
-spec finalize_script() -> string().
finalize_script() ->
    case getenv_first(["SWM_CONTAINER_FINALIZE", "SWM_FINALIZE_IN_CONTAINER"], false) of
        false ->
            ?DEFAULT_FINALIZE;
        "" ->
            ?DEFAULT_FINALIZE;
        Path ->
            Path
    end.

%% @doc Container Entrypoint override.
%% Default is `undefined` (Porter is Cmd / PID 1; no tini injection).
-spec entrypoint() -> [binary()] | undefined.
entrypoint() ->
    case getenv_first(["SWM_CONTAINER_ENTRYPOINT", "SWM_DOCKER_ENTRYPOINT"], false) of
        false ->
            undefined;
        "" ->
            undefined;
        Value ->
            [list_to_binary(Part) || Part <- string:tokens(Value, " ")]
    end.

%% @doc Docker VolumesFrom-style list (ignored by Podman backend).
-spec volumes_from() -> [binary()].
volumes_from() ->
    case getenv_first(["SWM_CONTAINER_VOLUMES_FROM", "SWM_DOCKER_VOLUMES_FROM"], false) of
        false ->
            [];
        "" ->
            [];
        Value ->
            [list_to_binary(Value)]
    end.

%% @doc Rootless Podman API unix socket path.
-spec podman_sock() -> string().
podman_sock() ->
    case getenv_first(["SWM_CONTAINER_PODMAN_SOCK", "SWM_PODMAN_SOCK"], false) of
        false ->
            default_podman_sock();
        "" ->
            default_podman_sock();
        Path ->
            Path
    end.

default_podman_sock() ->
    case os:getenv("XDG_RUNTIME_DIR") of
        Dir when is_list(Dir), Dir =/= "" ->
            filename:join(Dir, "podman/podman.sock");
        _ ->
            case file:read_file("/proc/self/loginuid") of
                {ok, Bin} ->
                    Uid = string:trim(binary_to_list(Bin)),
                    "/run/user/" ++ Uid ++ "/podman/podman.sock";
                _ ->
                    "/run/user/1000/podman/podman.sock"
            end
    end.

%% @doc Libpod API path prefix (versioned).
-spec podman_api_prefix() -> string().
podman_api_prefix() ->
    case getenv_first(["SWM_CONTAINER_PODMAN_API_PREFIX"], false) of
        false ->
            ?DEFAULT_API_PREFIX;
        "" ->
            ?DEFAULT_API_PREFIX;
        Prefix ->
            Prefix
    end.

%% @doc When true, refuse to run if Podman OCI runtime is not crun.
-spec require_crun() -> boolean().
require_crun() ->
    case getenv_first(["SWM_CONTAINER_REQUIRE_CRUN"], "1") of
        "0" ->
            false;
        "false" ->
            false;
        "no" ->
            false;
        _ ->
            true
    end.

%% @doc Directories searched for NVIDIA CDI specs.
-spec cdi_dirs() -> [string()].
cdi_dirs() ->
    case getenv_first(["SWM_CONTAINER_CDI_PATHS"], false) of
        false ->
            ["/etc/cdi", "/var/run/cdi"];
        "" ->
            ["/etc/cdi", "/var/run/cdi"];
        Paths ->
            string:tokens(Paths, ":")
    end.

%% @doc True if an NVIDIA CDI spec appears to be present on this host.
-spec cdi_available() -> boolean().
cdi_available() ->
    lists:any(fun dir_has_nvidia_cdi/1, cdi_dirs()).

dir_has_nvidia_cdi(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:any(fun is_nvidia_cdi_name/1, Files);
        _ ->
            false
    end.

is_nvidia_cdi_name(Name) ->
    Low = string:lowercase(Name),
    (string:str(Low, "nvidia") > 0)
    andalso (lists:suffix(".json", Low) orelse lists:suffix(".yaml", Low) orelse lists:suffix(".yml", Low)).

-spec gpu_cdi_missing_msg() -> string().
gpu_cdi_missing_msg() ->
    ?GPU_CDI_MISSING_MSG.

%% @doc Extra bind mounts for Podman: SWM_CONTAINER_EXTRA_BINDS=src:dst[:ro],...
-spec extra_binds() -> [map()].
extra_binds() ->
    case getenv_first(["SWM_CONTAINER_EXTRA_BINDS"], false) of
        false ->
            [];
        "" ->
            [];
        Spec ->
            [parse_bind(S) || S <- string:tokens(Spec, ","), S =/= ""]
    end.

parse_bind(Spec) ->
    Parts = string:tokens(Spec, ":"),
    {Src, Dst, Opts} =
        case Parts of
            [S, D] ->
                {S, D, [<<"rbind">>, <<"rw">>]};
            [S, D, "ro"] ->
                {S, D, [<<"rbind">>, <<"ro">>]};
            [S, D, _] ->
                {S, D, [<<"rbind">>, <<"rw">>]};
            [S] ->
                {S, S, [<<"rbind">>, <<"rw">>]}
        end,
    #{<<"destination">> => list_to_binary(Dst),
      <<"type">> => <<"bind">>,
      <<"source">> => list_to_binary(Src),
      <<"options">> => Opts}.

%% @doc First set env var among Names, or Default if none are set.
-spec getenv_first([string()], term()) -> string() | term().
getenv_first([], Default) ->
    Default;
getenv_first([Name | Rest], Default) ->
    case os:getenv(Name) of
        false ->
            getenv_first(Rest, Default);
        Value ->
            Value
    end.

%% ============================================================================
%% EUnit
%% ============================================================================

entrypoint_default_no_tini_test() ->
    true = os:unsetenv("SWM_CONTAINER_ENTRYPOINT"),
    true = os:unsetenv("SWM_DOCKER_ENTRYPOINT"),
    ?assertEqual(undefined, entrypoint()).

entrypoint_container_overrides_docker_test() ->
    true = os:putenv("SWM_DOCKER_ENTRYPOINT", "tini -g --"),
    true = os:putenv("SWM_CONTAINER_ENTRYPOINT", "catatonit --"),
    ?assertEqual([<<"catatonit">>, <<"--">>], entrypoint()),
    true = os:unsetenv("SWM_CONTAINER_ENTRYPOINT"),
    true = os:unsetenv("SWM_DOCKER_ENTRYPOINT").

finalize_prefers_container_env_test() ->
    true = os:putenv("SWM_FINALIZE_IN_CONTAINER", "/old/finalize.sh"),
    true = os:putenv("SWM_CONTAINER_FINALIZE", "/new/finalize.sh"),
    ?assertEqual("/new/finalize.sh", finalize_script()),
    true = os:unsetenv("SWM_CONTAINER_FINALIZE"),
    true = os:unsetenv("SWM_FINALIZE_IN_CONTAINER").

volumes_from_legacy_alias_test() ->
    true = os:unsetenv("SWM_CONTAINER_VOLUMES_FROM"),
    true = os:putenv("SWM_DOCKER_VOLUMES_FROM", "skyport-dev:ro"),
    ?assertEqual([<<"skyport-dev:ro">>], volumes_from()),
    true = os:unsetenv("SWM_DOCKER_VOLUMES_FROM").

run_steps_docker_test() ->
    ?assertEqual([create, attach, start, create_exec, start_exec, return_started],
                 wm_docker:run_steps()).

run_steps_podman_test() ->
    ?assertEqual(wm_docker:run_steps(), wm_podman:run_steps()).

podman_sock_override_test() ->
    true = os:putenv("SWM_CONTAINER_PODMAN_SOCK", "/tmp/test-podman.sock"),
    ?assertEqual("/tmp/test-podman.sock", podman_sock()),
    true = os:unsetenv("SWM_CONTAINER_PODMAN_SOCK").

cdi_missing_msg_test() ->
    ?assertEqual(?GPU_CDI_MISSING_MSG, gpu_cdi_missing_msg()).

require_crun_default_test() ->
    true = os:unsetenv("SWM_CONTAINER_REQUIRE_CRUN"),
    ?assertEqual(true, require_crun()).

cdi_unavailable_without_specs_test() ->
    true = os:putenv("SWM_CONTAINER_CDI_PATHS", "/tmp/swm-cdi-empty-test-dir-noexist"),
    ?assertEqual(false, cdi_available()),
    true = os:unsetenv("SWM_CONTAINER_CDI_PATHS").

cdi_available_with_nvidia_json_test() ->
    Dir = "/tmp/swm-cdi-test-" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = file:make_dir(Dir),
    ok = file:write_file(filename:join(Dir, "nvidia.com-gpu.json"), <<"{}\n">>),
    true = os:putenv("SWM_CONTAINER_CDI_PATHS", Dir),
    ?assertEqual(true, cdi_available()),
    true = os:unsetenv("SWM_CONTAINER_CDI_PATHS"),
    ok = file:delete(filename:join(Dir, "nvidia.com-gpu.json")),
    ok = file:del_dir(Dir).

communicate_steps_podman_test() ->
    Bin = <<"x">>,
    ?assertMatch([attach_ws, {send, Bin}, return_sent], wm_podman:communicate_steps(Bin)).
