%% @doc Log-safe summaries for HTTP bodies, headers, and option maps.
%% Prefer these over dumping full request/response payloads.
-module(wm_log_safe).

-export([summarize_iodata/1, summarize_headers/1, summarize_options/1]).

%% Header names kept in DEBUG logs (lowercase). Not: authorization, cookie, runtime.
-define(HEADER_ALLOWLIST,
        [<<"accept">>,
         <<"content-type">>,
         <<"content-length">>,
         <<"osversion">>,
         <<"containerimage">>,
         <<"flavorname">>,
         <<"username">>,
         <<"count">>,
         <<"jobid">>,
         <<"partname">>,
         <<"location">>,
         <<"ports">>,
         <<"installcheckpointtools">>,
         <<"extra">>]).

-spec summarize_iodata(term()) -> {bytes, non_neg_integer() | unknown}.
summarize_iodata(Bin) when is_binary(Bin) ->
    {bytes, byte_size(Bin)};
summarize_iodata(List) when is_list(List) ->
    try
        {bytes, iolist_size(List)}
    catch
        _:_ ->
            {bytes, unknown}
    end;
summarize_iodata(_) ->
    {bytes, unknown}.

%% @doc Keep allowlisted header names only; drop auth/cookie/runtime and unknowns.
-spec summarize_headers([{term(), term()}] | map() | term()) -> [{binary(), term()}].
summarize_headers(Headers) when is_list(Headers) ->
    lists:filtermap(fun summarize_header_pair/1, Headers);
summarize_headers(Headers) when is_map(Headers) ->
    summarize_headers(maps:to_list(Headers));
summarize_headers(_) ->
    [].

-spec summarize_header_pair({term(), term()}) -> {true, {binary(), term()}} | false.
summarize_header_pair({Name0, Value}) ->
    Name = normalize_header_name(Name0),
    case lists:member(Name, ?HEADER_ALLOWLIST) of
        true ->
            {true, {Name, summarize_header_value(Name, Value)}};
        false ->
            false
    end;
summarize_header_pair(_) ->
    false.

-spec normalize_header_name(term()) -> binary().
normalize_header_name(Name) when is_binary(Name) ->
    string:lowercase(Name);
normalize_header_name(Name) when is_list(Name) ->
    string:lowercase(unicode:characters_to_binary(Name));
normalize_header_name(Name) when is_atom(Name) ->
    string:lowercase(atom_to_binary(Name, utf8));
normalize_header_name(_) ->
    <<>>.

-spec summarize_header_value(binary(), term()) -> term().
summarize_header_value(<<"extra">>, Value) ->
    summarize_iodata(Value);
summarize_header_value(_Name, Value) when is_binary(Value); is_list(Value) ->
    Value;
summarize_header_value(_Name, Value) ->
    Value.

%% @doc Map of option keys to safe values (iodata becomes byte size).
-spec summarize_options(map() | term()) -> map() | {bytes, unknown}.
summarize_options(Opts) when is_map(Opts) ->
    maps:map(fun (_K, V) when is_binary(V); is_list(V) ->
                      summarize_iodata(V);
                  (_K, V) ->
                      V
              end,
              Opts);
summarize_options(_) ->
    {bytes, unknown}.
