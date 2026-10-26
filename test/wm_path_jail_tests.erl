-module(wm_path_jail_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_path_jail_tests

-spec resolve_allows_in_jail_test() -> ok.
resolve_allows_in_jail_test() ->
    Roots = ["/home/user", "/spool/job"],
    ?assertEqual({ok, "/home/user/file"}, wm_path_jail:resolve(Roots, "/home/user", "/home/user/file")),
    ?assertEqual({ok, "/home/user/a/b"}, wm_path_jail:resolve(Roots, "/home/user", "a/b")),
    ?assertEqual({ok, "/home/user"}, wm_path_jail:resolve(Roots, "/home/user", "/home/user")),
    ?assertEqual({ok, "/spool/job/out"}, wm_path_jail:resolve(Roots, "/spool/job", "/spool/job/out")),
    ok.

-spec resolve_rejects_dotdot_escape_test() -> ok.
resolve_rejects_dotdot_escape_test() ->
    Roots = ["/home/user"],
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "/home/user/../etc/passwd")),
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "/home/user/foo/../../etc/passwd")),
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "../../etc/passwd")),
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "../etc/passwd")),
    ok.

-spec resolve_rejects_sibling_prefix_test() -> ok.
resolve_rejects_sibling_prefix_test() ->
    Roots = ["/home/user"],
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "/home/user2/secret")),
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "/home/userX")),
    ?assertEqual({error, outside}, wm_path_jail:resolve(Roots, "/home/user", "/etc/passwd")),
    ok.

-spec resolve_rejects_empty_root_test() -> ok.
resolve_rejects_empty_root_test() ->
    ?assertEqual({error, outside}, wm_path_jail:resolve([""], "/", "/etc/passwd")),
    ?assertEqual({error, outside}, wm_path_jail:resolve([], "/", "/home/user/x")),
    ok.
