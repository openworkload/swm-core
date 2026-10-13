-module(wm_utils_etf_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_utils_etf_tests

-spec roundtrip_existing_atom_test() -> ok.
roundtrip_existing_atom_test() ->
    %% Atoms already loaded by the VM decode under [safe].
    Term = {ok, yield, process},
    Bin = term_to_binary(Term),
    ?assertEqual(Term, wm_utils:decode_from_binary(Bin)),
    ok.

-spec reject_new_atom_test() -> ok.
reject_new_atom_test() ->
    %% Craft ATOM_EXT for a name that must not exist as an atom yet.
    Suffix = integer_to_binary(erlang:unique_integer([positive])),
    Name = <<"wm_etf_nosuch_atom_", Suffix/binary>>,
    ?assertError(badarg, binary_to_existing_atom(Name, utf8)),
    Etf = <<131, 100, (byte_size(Name)):16, Name/binary>>,
    ?assertError(badarg, wm_utils:decode_from_binary(Etf)),
    ok.

-spec reject_oversized_test() -> ok.
reject_oversized_test() ->
    Bin = term_to_binary(lists:duplicate(100, ok)),
    Max = 8,
    ?assert(byte_size(Bin) > Max),
    ?assertError({etf_too_large, _, Max}, wm_utils:decode_from_binary(Bin, [{max_bytes, Max}])),
    ok.

-spec used_mux_two_terms_test() -> ok.
used_mux_two_terms_test() ->
    T1 = {process, 1, "done", 0, 0, ""},
    T2 = {porter_req, <<"ref">>, ping, #{}},
    Mux = <<(term_to_binary(T1))/binary, (term_to_binary(T2))/binary>>,
    {Decoded1, Used} = wm_utils:decode_from_binary(Mux, [used]),
    ?assertEqual(T1, Decoded1),
    ?assert(is_integer(Used) andalso Used > 0),
    <<_:Used/binary, Rest/binary>> = Mux,
    ?assertEqual(T2, wm_utils:decode_from_binary(Rest)),
    ok.
