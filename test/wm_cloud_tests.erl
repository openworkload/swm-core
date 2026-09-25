-module(wm_cloud_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_cloud_tests
%% Relies on eunit_compile_opts export_all for wm_cloud:lookup_node/2.

lookup_node_test() ->
    A = wm_entity:set({name, "a"}, wm_entity:new(node)),
    B = wm_entity:set({name, "b"}, wm_entity:new(node)),
    C = wm_entity:set({name, "c"}, wm_entity:new(node)),

    ?assertEqual({ok, A}, wm_cloud:lookup_node("a", [C, A, B])),
    ?assertEqual({error, not_found}, wm_cloud:lookup_node("z", [C, A, B])),
    ok.
