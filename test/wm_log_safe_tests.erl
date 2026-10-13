-module(wm_log_safe_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_log_safe_tests

-spec summarize_iodata_sizes_test() -> ok.
summarize_iodata_sizes_test() ->
    ?assertEqual({bytes, 0}, wm_log_safe:summarize_iodata(<<>>)),
    ?assertEqual({bytes, 5}, wm_log_safe:summarize_iodata(<<"hello">>)),
    ?assertEqual({bytes, 5}, wm_log_safe:summarize_iodata("hello")),
    ?assertEqual({bytes, 11}, wm_log_safe:summarize_iodata([<<"hello">>, <<" ">>, <<"world">>])),
    ?assertEqual({bytes, unknown}, wm_log_safe:summarize_iodata(not_iodata)),
    ok.

-spec summarize_headers_allowlist_test() -> ok.
summarize_headers_allowlist_test() ->
    Headers =
        [{<<"Content-Type">>, <<"application/json">>},
         {<<"Authorization">>, <<"Bearer secret-token">>},
         {<<"cookie">>, <<"sid=abc">>},
         {<<"runtime">>, <<"password=hunter2,tenant=x">>},
         {<<"jobid">>, <<"job-1">>},
         {<<"Accept">>, <<"application/json">>}],
    Safe = wm_log_safe:summarize_headers(Headers),
    Keys = [K || {K, _} <- Safe],
    ?assert(lists:member(<<"content-type">>, Keys)),
    ?assert(lists:member(<<"accept">>, Keys)),
    ?assert(lists:member(<<"jobid">>, Keys)),
    ?assertNot(lists:member(<<"authorization">>, Keys)),
    ?assertNot(lists:member(<<"cookie">>, Keys)),
    ?assertNot(lists:member(<<"runtime">>, Keys)),
    {_, <<"job-1">>} = lists:keyfind(<<"jobid">>, 1, Safe),
    ok.

-spec summarize_options_redacts_iodata_test() -> ok.
summarize_options_redacts_iodata_test() ->
    Opts =
        #{node_count => 2,
          image_name => "ubuntu",
          job_id => <<"abc-123">>},
    Safe = wm_log_safe:summarize_options(Opts),
    ?assertEqual(2, maps:get(node_count, Safe)),
    ?assertEqual({bytes, 6}, maps:get(image_name, Safe)),
    ?assertEqual({bytes, 7}, maps:get(job_id, Safe)),
    ok.
