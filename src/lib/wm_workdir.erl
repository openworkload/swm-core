%%% @doc Job workdir validation (shell-safe paths under the owner's home).
-module(wm_workdir).

-export([validate_workdir/1, validate_workdir_under_home/2]).

%% @doc Absolute path; no ".." segments; only safe path characters (no shell metacharacters).
-spec validate_workdir(string()) -> ok | {error, empty | not_absolute | parent_segment | unsafe_chars}.
validate_workdir([]) ->
    {error, empty};
validate_workdir(Path) when is_list(Path) ->
    case filename:pathtype(Path) of
        absolute ->
            Segments = filename:split(Path),
            case lists:member("..", Segments) of
                true ->
                    {error, parent_segment};
                false ->
                    case re:run(Path, "^[A-Za-z0-9._/-]+$", [{capture, none}]) of
                        match ->
                            ok;
                        nomatch ->
                            {error, unsafe_chars}
                    end
            end;
        _ ->
            {error, not_absolute}
    end;
validate_workdir(_) ->
    {error, empty}.

%% @doc WorkDir must validate and stay under Home (equality or Home/ prefix).
-spec validate_workdir_under_home(string(), string()) ->
                                     ok |
                                     {error,
                                      empty |
                                      not_absolute |
                                      parent_segment |
                                      unsafe_chars |
                                      outside_home |
                                      bad_home}.
validate_workdir_under_home(WorkDir, Home) ->
    case validate_workdir(Home) of
        {error, _} ->
            {error, bad_home};
        ok ->
            case validate_workdir(WorkDir) of
                {error, _} = Error ->
                    Error;
                ok ->
                    AbsW = filename:absname(WorkDir),
                    AbsH = filename:absname(Home),
                    case AbsW =:= AbsH orelse lists:prefix(AbsH ++ "/", AbsW) of
                        true ->
                            ok;
                        false ->
                            {error, outside_home}
                    end
            end
    end.
