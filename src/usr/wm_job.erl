-module(wm_job).

-export([top_mode/3]).

-define(FST_COL_SZ, 12).
-define(MAX_WIDTH, 80).

top_mode(ArgsDict, Ent, ConnArgs) ->
    FreeArg = wm_args:fetch(free_arg, unknown, ArgsDict),
    case Ent of
        "submit" ->
            submit(FreeArg, Ent, ConnArgs);
        "list" ->
            list(FreeArg, Ent, ConnArgs);
        "cancel" ->
            cancel(FreeArg, Ent, ConnArgs);
        "requeue" ->
            requeue(FreeArg, Ent, ConnArgs);
        "show" ->
            show(FreeArg, Ent, ConnArgs);
        Else ->
            unknown_arg(Else, Ent)
    end.

show(JIDs, Ent, ConnArgs) ->
    Handler =
        fun ([[]]) ->
                io:format("No jobs found~n");
            ([List | _]) when length(List) > 0 ->
                wm_job_cli:show(job, List);
            (Error) ->
                fatal_error(Error)
        end,
    rpc_generic(show, {JIDs}, ConnArgs, Handler),
    get_entity_submode(Ent).

requeue(JIDs, Ent, ConnArgs) ->
    Handler =
        fun H([[]]) ->
                io:format("No jobs to requeue~n");
            H([{string, Msg} | T]) ->
                io:format("~s~n", [Msg]),
                H(T);
            H([]) ->
                ok;
            H(Error) ->
                fatal_error(Error)
        end,
    rpc_generic(requeue, {JIDs}, ConnArgs, Handler),
    get_entity_submode(Ent).

cancel(JIDs, Ent, ConnArgs) ->
    Handler =
        fun H([[]]) ->
                io:format("No jobs to cancel~n");
            H([{string, Msg} | T]) ->
                io:format("~s~n", [Msg]),
                H(T);
            H([]) ->
                ok;
            H(Error) ->
                fatal_error(Error)
        end,
    rpc_generic(cancel, {JIDs}, ConnArgs, Handler),
    get_entity_submode(Ent).

submit([JobScriptPath | _], Ent, ConnArgs) ->
    Handler =
        fun H([]) ->
                ok;
            H([[]]) ->
                io:format("Job was not submitted~n");
            H([{string, Msg} | T]) ->
                io:format("~s~n", [Msg]),
                H(T);
            H(Error) ->
                fatal_error(Error)
        end,
    Username = wm_posix_utils:get_current_user(),
    case wm_utils:read_file(JobScriptPath, [binary]) of
        {ok, JobScript} ->
            Args = {JobScript, filename:absname(JobScriptPath), Username},
            rpc_generic(submit, Args, ConnArgs, Handler);
        {error, Error} ->
            fatal_error(Error)
    end,
    get_entity_submode(Ent).

list(_, Ent, ConnArgs) ->
    rpc_list(job, "%37I %6S %20U %20T", ConnArgs),
    get_entity_submode(Ent).

get_entity_submode(_Ent) ->
    "".

unknown_arg(Arg, Ent) ->
    io:format("Command not found: ~s~n", [Arg]),
    get_entity_submode(Ent).

fatal_error(Msg) when is_list(Msg) ->
    io:format("[ERROR] ~s~n", [lists:flatten(Msg)]);
fatal_error(Msg) ->
    io:format("[ERROR] ~p~n", [Msg]).

rpc_generic(Command, Args, ConnArgs, Handler) ->
    Answer = wm_rpc:call(wm_user, Command, Args),
    Handler(Answer).

rpc_get(Tab, ConnArgs) ->
    wm_rpc:call(wm_user, list, {[Tab]}).

rpc_list(Tab, Format, ConnArgs) ->
    case rpc_get(Tab, ConnArgs) of
        List when is_list(List) ->
            [wm_job_cli:list(Tab, X, Format) || X <- List];
        {string, Msg} ->
            io:format("~p~n", [Msg]);
        {error, Error} ->
            Str = inet:format_error(Error),
            fatal_error(Str ++ " (check SWM_API_PORT and SWM_API_HOST)")
    end.
