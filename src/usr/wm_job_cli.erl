-module(wm_job_cli).

-export([list/3, show/2]).

-include("../lib/wm_entity.hrl").

-define(FST_COL_SZ, 12).
-define(MAX_WIDTH, 80).

%% ============================================================================
%% API functions
%% ============================================================================

show(What, Records) ->
    print_show(What, Records).

list(What, Records, Format) when is_list(Records) ->
    S = fun(#job{submit_time = T1}, #job{submit_time = T2}) -> T1 =< T2 end,
    Sorted = lists:sort(S, Records),
    F = split_format_tokens(string:tokens(Format, " "), [], 0),
    print_list({What, header}, F, F, []),
    print_list({What, Sorted}, F, F, []).

%% ============================================================================
%% Implementation functions
%% ============================================================================

print_show(_, []) ->
    ok;
print_show(What, [R | T]) ->
    Indent = io_lib:format("~p", [?FST_COL_SZ]),
    print_show_fields(wm_entity:get_fields(What), Indent, R),
    print_show(What, T).

print_show_fields([], _, _) ->
    ok;
print_show_fields([X | T], Indent, R) ->
    Name =
        string:to_upper(
            lists:flatten(
                io_lib:format("~p", [X]))),
    Format = lists:flatten("~." ++ Indent ++ "s~p~n"),
    io:format(Format, [Name, wm_entity:get_attr(X, R)]),
    print_show_fields(T, Indent, R).

print_list({_, header}, [], RawFormats, Line) ->
    Sizes = [Size || {Size, _} <- RawFormats],
    Len = lists:foldl(fun(X, Sum) -> list_to_integer(X) + Sum end, 0, Sizes),
    UnderLine = lists:duplicate(Len, "-"),
    FLine = lists:flatten("~s~n~s~n"),
    io:format(FLine, [Line, UnderLine]);
print_list(_, [], _, Line) ->
    io:format("~s~n", [Line]);
print_list({_, []}, _, _, _) ->
    ok;
print_list({job, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", ["STATE"]);
            "U" ->
                io_lib:format("~." ++ Sz ++ "s", ["SUBMIT_TIME"]);
            "T" ->
                io_lib:format("~." ++ Sz ++ "s", ["START_TIME"]);
            "I" ->
                io_lib:format("~." ++ Sz ++ "s", ["ID"]);
            _ ->
                ""
        end,
    print_list({job, header}, T, RawFormats, [LinePart | Line]);
print_list({job, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get_attr(name, R)]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get_attr(state, R)]);
            "U" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get_attr(submit_time, R)]);
            "T" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get_attr(start_time, R)]);
            "I" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get_attr(id, R)]);
            _ ->
                ""
        end,
    print_list({job, R}, T, RawFormats, [LinePart | Line]);
print_list({X, [R | T]}, Format, RawFormats, Line) ->
    print_list({X, R}, Format, RawFormats, Line),
    print_list({X, T}, Format, RawFormats, Line).

append_state_number(Sz, Xs, State) ->
    N = length([X || X <- Xs, wm_entity:get_attr(state, X) == State]),
    io_lib:format("~." ++ Sz ++ "s", [io_lib:format("~p", [N])]).

split_format_tokens([], Map, _) ->
    Map;
split_format_tokens([Tok | T], Map, UsedWidth) ->
    try
        case lists:splitwith(fun(C) -> (C >= $0) and (C =< $9) end, tl(Tok)) of
            {"0", F} ->
                WidthN = ?MAX_WIDTH - UsedWidth,
                WidthS =
                    lists:flatten(
                        io_lib:format("~p", [WidthN])),
                split_format_tokens(T, [{WidthS, F} | Map], UsedWidth + WidthN);
            {Width, F} ->
                NewWidth = UsedWidth + list_to_integer(Width),
                split_format_tokens(T, [{Width, F} | Map], NewWidth)
        end
    catch
        _:Error ->
            io:format("Wrong format: ~p~n", [Error]),
            split_format_tokens(T, Map, UsedWidth)
    end.
