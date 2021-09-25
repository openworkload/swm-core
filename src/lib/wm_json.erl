-module(wm_json).

-export([decode/1]).

%% ============================================================================
%% API
%% ============================================================================

-spec decode(string() | binary()) -> {ok, term()} | {error, term()}.
decode(S) ->
    do_decode(S).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec do_decode(string() | binary()) -> {ok, term()} | {error, term()}.
do_decode(S) ->
    try
        mochijson2:decode(S)
    catch
        _:Error ->
        {error, Error}
    end.
