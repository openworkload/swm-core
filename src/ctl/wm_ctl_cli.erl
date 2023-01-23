-module(wm_ctl_cli).

-export([list/3, show/2, overview/3]).

-define(FST_COL_SZ, 16).
-define(MAX_WIDTH, 80).

%% ============================================================================
%% API functions
%% ============================================================================

show(What, Records) ->
    print_show(What, Records).

list(What, Records, Format) when is_list(Records) ->
    F = split_format_tokens(string:tokens(Format, " "), [], 0),
    print_list({What, header}, F, F, []),
    print_list({What, Records}, F, F, []).

overview({Type, {list, Xs}}, Format, Name) ->
    overview({Type, Xs}, Format, Name);
overview({Type, X}, Format, Name) ->
    F = split_format_tokens(string:tokens(Format, " "), [], 0),
    print_overview({Type, X}, F, F, [], Name).

%% ============================================================================
%% Implementation functions
%% ============================================================================

print_show(_, []) ->
    ok;
print_show(tree, Map) when is_map(Map) ->
    F1 = fun MakeTree({Ent, ID}, V, {Indent, Lines0}) when is_map(V) ->
                 Line =
                     case Indent of
                         0 ->
                             io_lib:format("~p: ~s~n", [Ent, ID]);
                         X ->
                             IndentStr = integer_to_list(X - 2),
                             Spaces = io_lib:format("~." ++ IndentStr ++ "s", [" "]),
                             io_lib:format("~s\\_~p: ~s~n", [Spaces, Ent, ID])
                     end,
                 Lines1 =
                     case Lines0 of
                         [] ->
                             [lists:flatten(Line)];
                         _ ->
                             Lines0 ++ [lists:flatten(Line)]
                     end,
                 Lines2 =
                     case maps:size(V) == 0 of
                         true ->
                             Lines1;
                         _ ->
                             {_, Lines3} = maps:fold(MakeTree, {Indent + 2, Lines1}, V),
                             Lines3
                     end,
                 {Indent, Lines2}
         end,
    {_, Lines} = maps:fold(F1, {0, []}, Map),
    F2 = fun AddVertBarPerLine(1, _, AllLines) ->
                 AllLines;
             AddVertBarPerLine(LineNum, N, AllLines) ->
                 Line = lists:nth(LineNum, AllLines),
                 case lists:nth(N, Line) /= $\s of
                     true ->
                         AllLines;
                     false ->
                         Line2 =
                             case N == 1 of
                                 true ->
                                     ["|" | lists:nthtail(N, Line)];
                                 false ->
                                     lists:sublist(Line, N - 1) ++ ["|" | lists:nthtail(N, Line)]
                             end,
                         NewLines =
                             lists:sublist(AllLines, LineNum - 1)
                             ++ [lists:flatten(Line2)]
                             ++ lists:nthtail(LineNum, AllLines),
                         AddVertBarPerLine(LineNum - 1, N, NewLines)
                 end
         end,
    F3 = fun AddVertBars([], _, All) ->
                 All;
             AddVertBars([_ | T], 1, All) ->
                 AddVertBars(T, 2, All);
             AddVertBars([Line | T], LineNum, All) ->
                 NewAll =
                     case string:chr(Line, $\\) of
                         0 ->
                             All;
                         N ->
                             F2(LineNum - 1, N, All)
                     end,
                 AddVertBars(T, LineNum + 1, NewAll)
         end,
    io:format("~s", [F3(Lines, 1, Lines)]);
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
    io:format(Format, [Name, wm_entity:get(X, R)]),
    print_show_fields(T, Indent, R).

print_overview({header, _}, [], RawFormats, Line, Name) ->
    Sizes = [Size || {Size, _} <- RawFormats],
    Len = lists:foldl(fun(X, Sum) -> list_to_integer(X) + Sum end, 0, Sizes),
    UnderLine = lists:duplicate(?FST_COL_SZ, " ") ++ lists:duplicate(Len, "-"),
    Indent = io_lib:format("~p", [?FST_COL_SZ]),
    FLine = lists:flatten("~." ++ Indent ++ "s| ~s~n~s~n"),
    io:format(FLine, [Name, Line, UnderLine]);
print_overview(_, [], _, Line, Name) ->
    Indent = io_lib:format("~p", [?FST_COL_SZ]),
    FLine = lists:flatten("~" ++ Indent ++ "s| ~s~n"),
    io:format(FLine, [Name ++ " ", Line]);
print_overview({header, grid}, [{Sz, What} | T], RawFormats, Line, Name) ->
    LinePart =
        case What of
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", ["ALL"]);
            "I" ->
                io_lib:format("~." ++ Sz ++ "s", ["IDLE"]);
            "D" ->
                io_lib:format("~." ++ Sz ++ "s", ["DOWN"]);
            "O" ->
                io_lib:format("~." ++ Sz ++ "s", ["OFFLINE"]);
            "B" ->
                io_lib:format("~." ++ Sz ++ "s", ["BUSY"]);
            _ ->
                ""
        end,
    print_overview({header, grid}, T, RawFormats, [LinePart | Line], Name);
print_overview({header, jobs}, [{Sz, What} | T], RawFormats, Line, Name) ->
    LinePart =
        case What of
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", ["ALL"]);
            "Q" ->
                io_lib:format("~." ++ Sz ++ "s", ["QUEUED"]);
            "R" ->
                io_lib:format("~." ++ Sz ++ "s", ["RUNNING"]);
            "E" ->
                io_lib:format("~." ++ Sz ++ "s", ["ERROR"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["FINISHED"]);
            _ ->
                ""
        end,
    print_overview({header, jobs}, T, RawFormats, [LinePart | Line], Name);
print_overview({{grid, Ent}, Xs}, [{Sz, What} | T], RawFormats, Line, Name) ->
    LinePart =
        case What of
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", [io_lib:format("~p", [length(Xs)])]);
            "I" ->
                append_state_number(Sz, Xs, idle, Ent);
            "D" ->
                append_state_number(Sz, Xs, down, Ent);
            "O" ->
                append_state_number(Sz, Xs, offline, Ent);
            "B" ->
                append_state_number(Sz, Xs, busy, Ent);
            _ ->
                ""
        end,
    print_overview({{grid, Ent}, Xs}, T, RawFormats, [LinePart | Line], Name);
print_overview({jobs, Xs}, [{Sz, What} | T], RawFormats, Line, Name) ->
    LinePart =
        case What of
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", [io_lib:format("~p", [length(Xs)])]);
            "Q" ->
                append_state_number(Sz, Xs, queued, jobs);
            "R" ->
                append_state_number(Sz, Xs, running, jobs);
            "E" ->
                append_state_number(Sz, Xs, error, jobs);
            "C" ->
                append_state_number(Sz, Xs, finished, jobs);
            _ ->
                ""
        end,
    print_overview({jobs, Xs}, T, RawFormats, [LinePart | Line], Name).

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
print_list({cluster, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", ["STATE"]);
            "P" ->
                io_lib:format("~." ++ Sz ++ "s", ["PARTITIONS"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({cluster, header}, T, RawFormats, [LinePart | Line]);
print_list({partition, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", ["STATE"]);
            "H" ->
                io_lib:format("~." ++ Sz ++ "s", ["NODES"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({partition, header}, T, RawFormats, [LinePart | Line]);
print_list({node, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", ["POWER"]);
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", ["ALLOC"]);
            "H" ->
                io_lib:format("~." ++ Sz ++ "s", ["HOST"]);
            "P" ->
                io_lib:format("~." ++ Sz ++ "s", ["PORT"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            "G" ->
                io_lib:format("~." ++ Sz ++ "s", ["GATEWAY"]);
            _ ->
                ""
        end,
    print_list({node, header}, T, RawFormats, [LinePart | Line]);
print_list({user, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "G" ->
                io_lib:format("~." ++ Sz ++ "s", ["GROUPS"]);
            "P" ->
                io_lib:format("~." ++ Sz ++ "s", ["PROJECTS"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({user, header}, T, RawFormats, [LinePart | Line]);
print_list({queue, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", ["STATE"]);
            "H" ->
                io_lib:format("~." ++ Sz ++ "s", ["NODES"]);
            "J" ->
                io_lib:format("~." ++ Sz ++ "s", ["JOBS"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({queue, header}, T, RawFormats, [LinePart | Line]);
print_list({scheduler, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", ["STATE"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({scheduler, header}, T, RawFormats, [LinePart | Line]);
print_list({image, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "I" ->
                io_lib:format("~." ++ Sz ++ "s", ["ID"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({image, header}, T, RawFormats, [LinePart | Line]);
print_list({global, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "V" ->
                io_lib:format("~." ++ Sz ++ "s", ["VALUE"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["COMMENT"]);
            _ ->
                ""
        end,
    print_list({global, header}, T, RawFormats, [LinePart | Line]);
print_list({remote, header}, [{Sz, What} | T], RawFormats, Line) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", ["NAME"]);
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", ["ADDRESS"]);
            "K" ->
                io_lib:format("~." ++ Sz ++ "s", ["KIND"]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", ["ACCOUNT_ID"]);
            _ ->
                ""
        end,
    print_list({remote, header}, T, RawFormats, [LinePart | Line]);
print_list({cluster, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(state, R)]);
            "P" ->
                N = length(wm_entity:get(partitions, R)),
                io_lib:format("~." ++ Sz ++ "s", [io_lib:format("~p", [N])]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({cluster, R}, T, RawFormats, [LinePart | Line]);
print_list({partition, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(state, R)]);
            "H" ->
                N = io_lib:format("~p", [length(wm_entity:get(nodes, R))]),
                io_lib:format("~." ++ Sz ++ "s", [N]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({partition, R}, T, RawFormats, [LinePart | Line]);
print_list({node, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(state_power, R)]);
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(state_alloc, R)]);
            "H" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(host, R)]);
            "P" ->
                N = io_lib:format("~p", [wm_entity:get(api_port, R)]),
                io_lib:format("~." ++ Sz ++ "s", [N]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            "G" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(gateway, R)]);
            _ ->
                ok
        end,
    print_list({node, R}, T, RawFormats, [LinePart | Line]);
print_list({user, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "G" ->
                N = io_lib:format("~p", [length(wm_entity:get(groups, R))]),
                io_lib:format("~." ++ Sz ++ "s", [N]);
            "P" ->
                N = io_lib:format("~p", [length(wm_entity:get(projects, R))]),
                io_lib:format("~." ++ Sz ++ "s", [N]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({user, R}, T, RawFormats, [LinePart | Line]);
print_list({queue, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(state, R)]);
            "H" ->
                N = io_lib:format("~p", [length(wm_entity:get(nodes, R))]),
                io_lib:format("~." ++ Sz ++ "s", [N]);
            "J" ->
                N = io_lib:format("~p", [length(wm_entity:get(jobs, R))]),
                io_lib:format("~." ++ Sz ++ "s", [N]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({queue, R}, T, RawFormats, [LinePart | Line]);
print_list({scheduler, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "S" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(state, R)]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({scheduler, R}, T, RawFormats, [LinePart | Line]);
print_list({image, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "I" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(id, R)]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({image, R}, T, RawFormats, [LinePart | Line]);
print_list({global, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [atom_to_list(wm_entity:get(name, R))]);
            "V" ->
                V = wm_entity:get(value, R),
                io_lib:format("~." ++ Sz ++ "s", [io_lib:format("~p", [V])]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(comment, R)]);
            _ ->
                ""
        end,
    print_list({global, R}, T, RawFormats, [LinePart | Line]);
print_list({remote, R}, [{Sz, What} | T], RawFormats, Line) when is_tuple(R) ->
    LinePart =
        case What of
            "N" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(name, R)]);
            "A" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(address, R)]);
            "K" ->
                io_lib:format("~." ++ Sz ++ "s", [wm_entity:get(kind, R)]);
            "C" ->
                io_lib:format("~." ++ Sz ++ "p", [wm_entity:get(account_id, R)]);
            _ ->
                ""
        end,
    print_list({remote, R}, T, RawFormats, [LinePart | Line]);
print_list({X, [R | T]}, Format, RawFormats, Line) ->
    print_list({X, R}, Format, RawFormats, Line),
    print_list({X, T}, Format, RawFormats, Line).

append_state_number(Sz, Xs, State, node) ->
    N = length([X || X <- Xs, wm_entity:get(state_alloc, X) == State]),
    io_lib:format("~." ++ Sz ++ "s", [io_lib:format("~p", [N])]);
append_state_number(Sz, Xs, State, _) ->
    N = length([X || X <- Xs, wm_entity:get(state, X) == State]),
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
