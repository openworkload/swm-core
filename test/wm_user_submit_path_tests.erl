-module(wm_user_submit_path_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_user_submit_path_tests

%% @doc path qs used to read arbitrary server files into job.script_content.
-spec submit_script_source_rejects_path_test() -> ok.
submit_script_source_rejects_path_test() ->
    ?assertEqual({error, bad_request}, wm_user_rest:submit_script_source(<<"/etc/shadow">>)),
    ?assertEqual({error, bad_request}, wm_user_rest:submit_script_source(<<"/etc/passwd">>)),
    ?assertEqual({error, bad_request},
                 wm_user_rest:submit_script_source(<<"/var/lib/swm/spool/secure/node/key.pem">>)),
    ?assertEqual({error, bad_request}, wm_user_rest:submit_script_source(<<"../../etc/shadow">>)),
    ?assertEqual({error, bad_request}, wm_user_rest:submit_script_source(<<"/tmp/foo.swm">>)),
    ?assertEqual({error, bad_request}, wm_user_rest:submit_script_source(<<"">>)),
    ok.

-spec submit_script_source_allows_body_test() -> ok.
submit_script_source_allows_body_test() ->
    ?assertEqual(body, wm_user_rest:submit_script_source(undefined)),
    ok.
