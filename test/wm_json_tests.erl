-module(wm_json_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_json_tests

-spec decode_object_test() -> ok.
decode_object_test() ->
    ?assertEqual(#{<<"a">> => 1, <<"b">> => <<"x">>}, wm_json:decode(<<"{\"a\":1,\"b\":\"x\"}">>)),
    ?assertEqual(#{}, wm_json:decode(<<"{}">>)).

-spec decode_array_and_scalars_test() -> ok.
decode_array_and_scalars_test() ->
    ?assertEqual([true, false, null, 1, 2.5, <<"hi">>], wm_json:decode(<<"[true,false,null,1,2.5,\"hi\"]">>)),
    ?assertEqual([], wm_json:decode(<<"[]">>)).

-spec decode_nested_map_test() -> ok.
decode_nested_map_test() ->
    Input = <<"{\"images\":[{\"id\":\"i1\",\"extra\":{\"status\":\"ok\"}}]}">>,
    Expected = #{<<"images">> => [#{<<"id">> => <<"i1">>, <<"extra">> => #{<<"status">> => <<"ok">>}}]},
    ?assertEqual(Expected, wm_json:decode(Input)).

-spec decode_schema_field_shape_test() -> ok.
decode_schema_field_shape_test() ->
    Input = <<"{\"default\":\"x\",\"type\":\"string\"}">>,
    ?assertEqual(#{<<"default">> => <<"x">>, <<"type">> => <<"string">>}, wm_json:decode(Input)),
    Input2 = <<"{\"type\":\"atom\"}">>,
    ?assertEqual(#{<<"type">> => <<"atom">>}, wm_json:decode(Input2)).

-spec decode_accepts_iodata_test() -> ok.
decode_accepts_iodata_test() ->
    ?assertEqual(#{<<"k">> => 1}, wm_json:decode("{\"k\":1}")),
    ?assertEqual(#{<<"k">> => 1}, wm_json:decode([<<"{\"k\":">>, <<"1}">>])).

-spec decode_unicode_test() -> ok.
decode_unicode_test() ->
    ?assertEqual(#{<<"c">> => <<"é"/utf8>>}, wm_json:decode(<<"{\"c\":\"\\u00e9\"}">>)).

-spec decode_invalid_json_test() -> ok.
decode_invalid_json_test() ->
    ?assertMatch({error, _}, wm_json:decode(<<"foo">>)),
    ?assertMatch({error, _}, wm_json:decode(<<"">>)),
    ?assertMatch({error, _}, wm_json:decode(<<"{\"a\":">>)).

-spec encode_roundtrip_test() -> ok.
encode_roundtrip_test() ->
    Term = #{<<"a">> => 1, <<"b">> => [true, null, <<"x">>]},
    ?assertEqual(Term,
                 wm_json:decode(
                     wm_json:encode(Term))).
