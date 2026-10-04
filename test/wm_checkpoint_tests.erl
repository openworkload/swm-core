-module(wm_checkpoint_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_checkpoint_tests

-spec enabled_and_env_test() -> ok.
enabled_and_env_test() ->
    Job0 = wm_entity:new(job),
    ?assertEqual(false, wm_checkpoint:enabled(Job0)),
    ?assertEqual("disabled", wm_checkpoint:display_last(Job0)),
    Env0 = wm_checkpoint:env(Job0),
    ?assertEqual("", proplists:get_value("SWM_CKPT", Env0)),
    Job1 = wm_entity:set([{checkpoint, "dmtcp"}, {checkpoint_dir, "/mnt/blob/ckpt"}, {checkpoint_interval, 120}], Job0),
    ?assertEqual(true, wm_checkpoint:enabled(Job1)),
    ?assertEqual("", wm_checkpoint:display_last(Job1)),
    Env1 = wm_checkpoint:env(Job1),
    ?assertEqual("dmtcp", proplists:get_value("SWM_CKPT", Env1)),
    ?assertEqual("/mnt/blob/ckpt", proplists:get_value("SWM_CKPT_DIR", Env1)),
    ?assertEqual("120", proplists:get_value("SWM_CKPT_INTERVAL", Env1)),
    Job2 = wm_entity:set({last_checkpoint_time, "2026-10-04T12:00:00"}, Job1),
    ?assertEqual("2026-10-04T12:00:00", wm_checkpoint:display_last(Job2)).
