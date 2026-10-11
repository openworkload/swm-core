-module(wm_gate_body_tests).

-include_lib("eunit/include/eunit.hrl").

%% Guardrail: wm_gate must not embed node private key material for the gate.
no_pem_data_helpers_test() ->
    Path = find_wm_gate_erl(),
    {ok, Bin} = file:read_file(Path),
    ?assertEqual(nomatch, binary:match(Bin, <<"pem_data">>)),
    ?assertEqual(nomatch, binary:match(Bin, <<"read_pem_data">>)),
    ?assertEqual(nomatch, binary:match(Bin, <<"BEGIN PRIVATE KEY">>)),
    ?assertEqual(nomatch, binary:match(Bin, <<"BEGIN RSA PRIVATE KEY">>)).

find_wm_gate_erl() ->
    Rel = filename:join(["src", "srv", "cloud", "wm_gate.erl"]),
    Candidates =
        [filename:absname(Rel),
         filename:absname(filename:join(["..", "..", "..", "..", Rel])),
         filename:join([code:lib_dir(swm), Rel])],
    case lists:search(fun filelib:is_file/1, Candidates) of
        {value, Path} ->
            Path;
        false ->
            error({wm_gate_erl_not_found, Candidates})
    end.
