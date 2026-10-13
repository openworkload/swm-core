-module(wm_utils_submission_address_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_utils_submission_address_tests

-spec local_addresses_allowed_test() -> ok.
local_addresses_allowed_test() ->
    ?assert(wm_utils:is_allowed_submission_address("127.0.0.1", "")),
    ?assert(wm_utils:is_allowed_submission_address("localhost", "")),
    ?assert(wm_utils:is_allowed_submission_address("::1", "")),
    ok.

-spec peer_ip_allowed_test() -> ok.
peer_ip_allowed_test() ->
    ?assert(wm_utils:is_allowed_submission_address("203.0.113.10", "203.0.113.10")),
    ?assert(wm_utils:is_allowed_submission_address("203.0.113.10", " 203.0.113.10 ")),
    ?assertNot(wm_utils:is_allowed_submission_address("203.0.113.10", "198.51.100.1")),
    ok.

-spec foreign_denied_without_allowlist_test() -> ok.
foreign_denied_without_allowlist_test() ->
    meck:new(wm_conf, [passthrough]),
    meck:expect(wm_conf,
                g,
                fun (submission_address_allowlist, {Default, string}) ->
                        Default;
                    (Name, Spec) ->
                        meck:passthrough([Name, Spec])
                end),
    try
        ?assertNot(wm_utils:is_allowed_submission_address("8.8.8.8", "")),
        ?assertNot(wm_utils:is_allowed_submission_address("evil.example.com", "")),
        ?assertNot(wm_utils:is_allowed_submission_address("10.0.0.5", "")),
        ?assertNot(wm_utils:is_allowed_submission_address(not_found, "")),
        ?assertNot(wm_utils:is_allowed_submission_address("", "127.0.0.1"))
    after
        meck:unload(wm_conf)
    end,
    ok.

-spec allowlist_allows_configured_hosts_test() -> ok.
allowlist_allows_configured_hosts_test() ->
    meck:new(wm_conf, [passthrough]),
    meck:expect(wm_conf,
                g,
                fun (submission_address_allowlist, {_, string}) ->
                        "jump.example.com, 198.51.100.20";
                    (Name, Spec) ->
                        meck:passthrough([Name, Spec])
                end),
    try
        ?assert(wm_utils:is_allowed_submission_address("jump.example.com", "")),
        ?assert(wm_utils:is_allowed_submission_address("JUMP.EXAMPLE.COM", "")),
        ?assert(wm_utils:is_allowed_submission_address("198.51.100.20", "")),
        ?assertNot(wm_utils:is_allowed_submission_address("other.example.com", ""))
    after
        meck:unload(wm_conf)
    end,
    ok.
