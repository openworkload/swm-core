-module(wm_ssl_dist_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("public_key/include/public_key.hrl").

%% ./rebar3 eunit --module=wm_ssl_dist_tests

-spec verify_fun_rejects_bad_cert_test() -> ok.
verify_fun_rejects_bad_cert_test() ->
    ?assertEqual({fail, {bad_cert, unknown_ca}},
                 wm_ssl_dist:verify_fun(undefined, {bad_cert, unknown_ca}, [])),
    ok.

-spec verify_fun_passes_valid_test() -> ok.
verify_fun_passes_valid_test() ->
    ?assertEqual({valid, st}, wm_ssl_dist:verify_fun(undefined, valid, st)),
    ?assertEqual({unknown, st}, wm_ssl_dist:verify_fun(undefined, {extension, x}, st)),
    ok.

-spec verify_fun_valid_peer_requires_node_profile_test() -> ok.
verify_fun_valid_peer_requires_node_profile_test() ->
    case os:getenv("SWM_SPOOL") of
        false ->
            ok;
        "" ->
            ok;
        Spool ->
            {_Ca, _Key, CertFile} = wm_utils:get_node_cert_paths(Spool),
            case file:read_file(CertFile) of
                {ok, Bin} ->
                    case public_key:pem_decode(Bin) of
                        [{'Certificate', Der, _} | _] ->
                            Cert = public_key:pkix_decode_cert(Der, otp),
                            case wm_cert:profile(Cert) of
                                node ->
                                    ?assertEqual({valid, []},
                                                 wm_ssl_dist:verify_fun(Cert, valid_peer, []));
                                _ ->
                                    ok
                            end;
                        _ ->
                            ok
                    end;
                _ ->
                    ok
            end
    end,
    ok.
