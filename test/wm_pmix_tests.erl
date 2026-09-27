%% ./rebar3 eunit --module=wm_pmix_tests
-module(wm_pmix_tests).

-include_lib("eunit/include/eunit.hrl").

bootstrap_env_test() ->
    Env = wm_pmix:bootstrap_env(#{job_id => "abc", nodes => ["n1", "n2", "n3"]}, 1),
    ?assertEqual("swm-abc", proplists:get_value("PMIX_NAMESPACE", Env)),
    ?assertEqual("1", proplists:get_value("PMIX_RANK", Env)),
    ?assertEqual("3", proplists:get_value("PMIX_JOB_SIZE", Env)),
    ?assertEqual("1", proplists:get_value("PMIX_LOCAL_SIZE", Env)).

bootstrap_env_with_uri_test() ->
    Env = wm_pmix:bootstrap_env(#{job_id => "x",
                                  nodes => ["a"],
                                  server_uri => "unix:///tmp/x"},
                                0),
    ?assertEqual("unix:///tmp/x", proplists:get_value("PMIX_SERVER_URI", Env)).

porter_ctrl_reply_framing_test() ->
    Ref = <<"ref-1">>,
    Bin = wm_porter_protocol:prepare_ctrl_reply(Ref, {done, 0}),
    <<2, Size:32/big, Rest/binary>> = Bin,
    ?assertEqual(Size, byte_size(Rest)),
    ?assertEqual({porter_rep, Ref, {done, 0}}, binary_to_term(Rest)).

ensure_started_test() ->
    {ok, Pid} = wm_pmix:ensure_started(),
    ?assert(is_pid(Pid)),
    {ok, Pid2} = wm_pmix:ensure_started(),
    ?assertEqual(Pid, Pid2).
