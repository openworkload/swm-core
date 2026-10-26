%%% @doc Path containment for SFTP / file-transfer jails.
%%% Rejects ".." escapes that filename:absname/1 does not collapse.
-module(wm_path_jail).

-export([resolve/3]).

%% @doc Resolve Path against Cwd and allow only if it stays under one of Roots.
%% Returns a path under that root with ".." removed via filelib:safe_relative_path/2.
-spec resolve([string()], string(), file:filename() | binary()) ->
                 {ok, string()} | {error, outside}.
resolve(Roots, Cwd, Path0) when is_list(Roots), is_list(Cwd) ->
    Path = to_list(Path0),
    Abs =
        case filename:pathtype(Path) of
            absolute ->
                filename:absname(Path);
            _ ->
                filename:absname(Path, Cwd)
        end,
    case lists:member("..", filename:split(Abs)) of
        true ->
            {error, outside};
        false ->
            try_roots([normalize_root(R) || R <- Roots], Abs)
    end.

%% ============================================================================
%% Internal
%% ============================================================================

-spec try_roots([string()], string()) -> {ok, string()} | {error, outside}.
try_roots([], _Abs) ->
    {error, outside};
try_roots(["" | Rest], Abs) ->
    try_roots(Rest, Abs);
try_roots([Root | Rest], Abs) ->
    case under_root(Root, Abs) of
        {ok, SafeAbs} ->
            {ok, SafeAbs};
        error ->
            try_roots(Rest, Abs)
    end.

-spec under_root(string(), string()) -> {ok, string()} | error.
under_root(Root, Abs) ->
    RootParts = filename:split(Root),
    AbsParts = filename:split(Abs),
    case lists:prefix(RootParts, AbsParts) of
        false ->
            error;
        true ->
            RelParts = lists:nthtail(length(RootParts), AbsParts),
            Rel =
                case RelParts of
                    [] ->
                        "";
                    _ ->
                        filename:join(RelParts)
                end,
            case filelib:safe_relative_path(Rel, Root) of
                unsafe ->
                    error;
                SafeRel when SafeRel =:= "" orelse SafeRel =:= [] ->
                    {ok, Root};
                SafeRel when is_list(SafeRel) ->
                    {ok, filename:join(Root, SafeRel)}
            end
    end.

-spec normalize_root(string()) -> string().
normalize_root(Root) when is_list(Root) ->
    string:trim(Root, trailing, "/");
normalize_root(_) ->
    "".

-spec to_list(file:filename() | binary()) -> string().
to_list(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
to_list(List) when is_list(List) ->
    List.
