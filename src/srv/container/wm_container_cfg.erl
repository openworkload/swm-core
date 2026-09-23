%%% @doc Container runtime configuration helpers.
%%% Prefer SWM_CONTAINER_* env vars; fall back to legacy SWM_DOCKER_* /
%%% SWM_FINALIZE_IN_CONTAINER names during the Docker -> Podman transition.
-module(wm_container_cfg).

-export([finalize_script/0, entrypoint/0, volumes_from/0, getenv_first/2]).

-include_lib("eunit/include/eunit.hrl").

-define(DEFAULT_FINALIZE, "/opt/swm/current/scripts/swm-container-finalize.sh").

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
%% Set SWM_CONTAINER_ENTRYPOINT or SWM_DOCKER_ENTRYPOINT to a space-separated
%% list to force an entrypoint; set to empty string for image default.
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

%% @doc Docker VolumesFrom-style list (legacy; Podman will use explicit binds).
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
