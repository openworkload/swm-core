-module(wm_args).

-export([normalize/1, fetch/3, get_conn_args/0]).

%% ============================================================================
%% API functions
%% ============================================================================

-spec normalize(list()) -> map().
normalize([]) ->
    dict:new();
normalize([Command | ArgsRest]) ->
    ArgsDict = dict:new(),
    extract_args(ArgsRest, none, dict:store(command, Command, ArgsDict)).

-spec fetch(string(), string(), {}) -> string().
fetch(ArgName, DefaultVal, ArgsDict) ->
    try
        dict:fetch(ArgName, ArgsDict)
    catch
        _:_ ->
            DefaultVal
    end.

-spec get_conn_args() -> map().
get_conn_args() ->
    Args = maps:put(port, os:getenv("SWM_API_PORT", 10001), maps:new()),
    maps:put(host, os:getenv("SWM_API_HOST", "localhost"), Args).

%% ============================================================================
%% Implementation functions
%% ============================================================================

extract_args([], _, Dict) ->
    Dict;
extract_args([Arg | T], Last, Dict) when is_list(Arg) ->
    case Last of
        none ->
            case lists:prefix("--", Arg) of
                true ->
                    extract_args(T, string:sub_string(Arg, 3), Dict);
                false ->
                    case lists:prefix("-", Arg) of
                        true ->
                            extract_args(T, string:sub_string(Arg, 2), Dict);
                        false ->
                            extract_args(T, none, extract_free_arg(Arg, Dict))
                    end
            end;
        _ ->
            extract_args(T, none, dict:store(Last, Arg, Dict))
    end;
extract_args(_, _, Dict) ->
    Dict.

extract_free_arg(Arg, Dict) ->
    case dict:is_key(free_arg, Dict) of
        true ->
            dict:store(free_arg, dict:fetch(free_arg, Dict) ++ [Arg], Dict);
        false ->
            dict:store(free_arg, [Arg], Dict)
    end.
