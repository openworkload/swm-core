-module(wm_cert_profile_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("public_key/include/public_key.hrl").

%% ./rebar3 eunit --module=wm_cert_profile_tests

-spec role_after_profile_rejects_user_as_node_test() -> ok.
role_after_profile_rejects_user_as_node_test() ->
    ?assertEqual(unknown, wm_rpc_acl:role_after_profile(node, user)),
    ?assertEqual(node, wm_rpc_acl:role_after_profile(node, node)),
    ?assertEqual(node, wm_rpc_acl:role_after_profile(node, legacy)),
    ?assertEqual(admin, wm_rpc_acl:role_after_profile(admin, user)),
    ?assertEqual(user, wm_rpc_acl:role_after_profile(user, user)),
    ?assertEqual(unknown, wm_rpc_acl:role_after_profile(unknown, user)),
    ok.

-spec profile_from_der_on_spool_node_cert_test() -> ok.
profile_from_der_on_spool_node_cert_test() ->
    NodePath = "/opt/swm/spool/secure/node/cert.pem",
    case filelib:is_regular(NodePath) of
        true ->
            {ok, Bin} = file:read_file(NodePath),
            [{'Certificate', Der, _} | _] = public_key:pem_decode(Bin),
            %% Lab certs may be legacy (no EKU) until re-issued with node_cert.
            Profile = wm_cert:profile_from_der(Der),
            ?assert(lists:member(Profile, [node, legacy]));
        false ->
            ok
    end,
    ok.
