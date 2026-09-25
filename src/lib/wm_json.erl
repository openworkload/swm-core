-module(wm_json).

-export([decode/1, encode/1]).

%% ============================================================================
%% API
%% ============================================================================

%% Decode JSON to Erlang terms: objects as maps with binary keys;
%% arrays as lists; strings as binaries.
-spec decode(iodata()) -> term() | {error, term()}.
decode(S) ->
    try
        json:decode(iolist_to_binary(S))
    catch
        _:Error ->
            {error, Error}
    end.

%% Encode Erlang terms to a JSON binary (maps/lists; atoms become strings
%% except true/false/null).
-spec encode(term()) -> binary().
encode(Term) ->
    iolist_to_binary(json:encode(Term)).
