-module(wm_ssh_key_cb_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_ssh_key_cb_tests

-spec pinned_host_key_matches_generated_pub_test() -> ok.
pinned_host_key_matches_generated_pub_test() ->
    Tmp = make_temp_spool(),
    try
        HostDir = wm_ssh_key_cb:host_dir(Tmp),
        ok =
            filelib:ensure_dir(
                filename:join(HostDir, "x")),
        KeyFile = filename:join(HostDir, "ssh_host_ed25519_key"),
        Cmd = lists:flatten(
                  io_lib:format("ssh-keygen -t ed25519 -N '' -f ~s -q", [KeyFile])),
        "" = os:cmd(Cmd),
        {ok, Bin} = file:read_file(KeyFile ++ ".pub"),
        [{Pub, _} | _] = ssh_file:decode(Bin, openssh_key),
        ?assert(wm_ssh_key_cb:pinned_host_key_matches(Tmp, Pub)),
        Foreign = {'RSAPublicKey', 1234567890123456789012345678901234567890, 65537},
        ?assertNot(wm_ssh_key_cb:pinned_host_key_matches(Tmp, Foreign))
    after
        os:cmd("rm -rf " ++ Tmp)
    end,
    ok.

-spec client_options_disable_silent_accept_test() -> ok.
client_options_disable_silent_accept_test() ->
    Opts = wm_ssh_key_cb:client_options("/tmp/swm-spool-test", "swm"),
    ?assertEqual(false, proplists:get_value(silently_accept_hosts, Opts)),
    ?assertEqual("/tmp/swm-spool-test/secure/host", proplists:get_value(user_dir, Opts)),
    ok.

-spec unknown_host_rejected_without_pin_test() -> ok.
unknown_host_rejected_without_pin_test() ->
    Tmp = make_temp_spool(),
    try
        HostDir = wm_ssh_key_cb:host_dir(Tmp),
        ok =
            filelib:ensure_dir(
                filename:join(HostDir, "x")),
        %% Empty host dir / no known_hosts => is_host_key false.
        Foreign = {'RSAPublicKey', 9876543210987654321098765432109876543210, 65537},
        Opts = [{key_cb_private, [{spool, Tmp}]}, {user_dir, HostDir}],
        ?assertEqual(false, wm_ssh_key_cb:is_host_key(Foreign, "127.0.0.1", 22, 'ssh-rsa', Opts))
    after
        os:cmd("rm -rf " ++ Tmp)
    end,
    ok.

-spec make_temp_spool() -> string().
make_temp_spool() ->
    Base =
        filename:join(
            os:getenv("TMPDIR", "/tmp"), "wm_ssh_key_cb_tests." ++ integer_to_list(erlang:unique_integer([positive]))),
    ok =
        filelib:ensure_dir(
            filename:join([Base, "secure", "host", "x"])),
    Base.
