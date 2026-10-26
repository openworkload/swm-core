-module(wm_posix_utils_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_posix_utils_tests

-spec validate_username_rejects_metachar_test() -> ok.
validate_username_rejects_metachar_test() ->
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username(";id")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username("`id`")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username("$(id)")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username("alice;rm")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username("alice bob")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username("/root")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username("")),
    ?assertEqual({error, bad_username}, wm_posix_utils:validate_username(undefined)),
    ok.

-spec validate_username_accepts_portable_test() -> ok.
validate_username_accepts_portable_test() ->
    ?assertEqual(ok, wm_posix_utils:validate_username("alice")),
    ?assertEqual(ok, wm_posix_utils:validate_username("alice.bob")),
    ?assertEqual(ok, wm_posix_utils:validate_username("alice_bob")),
    ?assertEqual(ok, wm_posix_utils:validate_username("_service")),
    ?assertEqual(ok, wm_posix_utils:validate_username("user-1")),
    ok.

-spec get_user_home_rejects_bad_username_test() -> ok.
get_user_home_rejects_bad_username_test() ->
    ?assertEqual({error, bad_username}, wm_posix_utils:get_user_home(";id")),
    ?assertEqual({error, bad_username}, wm_posix_utils:get_user_home("`id`")),
    ?assertEqual({error, bad_username}, wm_posix_utils:get_user_home("$(reboot)")),
    ?assertEqual({error, bad_username}, wm_posix_utils:get_user_home("a/b")),
    ok.

-spec get_system_uid_gid_rejects_bad_username_test() -> ok.
get_system_uid_gid_rejects_bad_username_test() ->
    ?assertEqual({error, not_found}, wm_posix_utils:get_system_uid_gid(";id")),
    ?assertEqual({error, not_found}, wm_posix_utils:get_system_uid_gid("`id`")),
    ?assertEqual({error, not_found}, wm_posix_utils:get_system_uid_gid("alice;x")),
    ok.
