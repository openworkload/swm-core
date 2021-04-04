-module(wm_json).

-export([decode/1]).

%% ============================================================================
%% API
%% ============================================================================

-spec decode(string() | binary()) -> {ok, term()}.
decode(S) ->
    do_decode(S).

%% ============================================================================
%% Implementation functions
%% ============================================================================

do_decode(S) ->
    try
        mochijson2:decode(S)
    catch
        _:Error ->
            Error
    end.
