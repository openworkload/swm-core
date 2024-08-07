-module(wm_shell).

-export([start_link/1, init/1]).

-record(mstate, {mode = "" :: string(), entity = "" :: string(), args_line, spool, root}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    spawn_link(?MODULE, init, [Args]).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec init(list()) -> ok.
init(Args) when is_list(Args) ->
    process_flag(trap_exit, true),
    MState1 = parse_args(Args, #mstate{}),
    wm_log:start_link(Args),
    wm_log:switch(stdout),
    shell_loop(MState1).

shell_loop(#mstate{} = MState) when MState#mstate.args_line =/= undefined ->
    process(MState#mstate.args_line, MState),
    exit(normal);
shell_loop(#mstate{} = MState) ->
    Line = io:get_line(prompt(MState)),
    shell_loop(process(Line, MState)).

process(Line, #mstate{} = MState) ->
    Commands =
        string:tokens(
            string:strip(Line, both, $\n), " "),
    apply_control_args(Commands),
    case check_exit(Commands, MState) of
        {exit, NewState} ->
            NewState;
        _ ->
            do_wmctl(prepend_mode(Commands, MState), MState)
    end.

apply_control_args(Args) ->
    case lists:any(fun(X) -> X =:= "-d" end, Args) of
        false ->
            wm_log:switch(none);
        _ ->
            ok
    end.

do_wmctl([], #mstate{} = MState) ->
    MState;
do_wmctl(Commands, #mstate{} = MState) when is_list(Commands) ->
    [Mode | Tail] = Commands,
    ArgsDict = wm_args:normalize(Commands),
    case Tail of
        [] ->
            enter_mode(Mode, MState);
        _ ->
            ConnArgs = wm_args:get_conn_args(),
            Args = {ArgsDict, MState#mstate.entity},
            Entity =
                case aliases(Mode) of
                    "grid" ->
                        wm_ctl:grid(Args, ConnArgs);
                    "cluster" ->
                        wm_ctl:cluster(Args, ConnArgs);
                    "partition" ->
                        wm_ctl:partition(Args, ConnArgs);
                    "node" ->
                        wm_ctl:node(Args, ConnArgs);
                    "user" ->
                        wm_ctl:user(Args, ConnArgs);
                    "queue" ->
                        wm_ctl:queue(Args, ConnArgs);
                    "scheduler" ->
                        wm_ctl:scheduler(Args, ConnArgs);
                    "image" ->
                        wm_ctl:image(Args, ConnArgs);
                    "global" ->
                        wm_ctl:global(Args, ConnArgs);
                    "remote" ->
                        wm_ctl:remote(Args, ConnArgs);
                    "quit" ->
                        exit(normal);
                    Unknown ->
                        io:format("Mode not found: ~p~n", [Unknown]),
                        MState#mstate.entity
                end,
            NewMState = MState#mstate{entity = Entity},
            enter_mode(Mode, NewMState)
    end.

prepend_mode([], _) ->
    [];
prepend_mode([X | T], #mstate{} = MState) ->
    case lists:member(X, get_ctl_modes()) of
        false ->
            case MState#mstate.mode of
                "" ->
                    [X | T];
                _ ->
                    [MState#mstate.mode] ++ [X | T]
            end;
        true ->
            [X | T]
    end.

check_exit([], _) ->
    ok;
check_exit([Commands | _], #mstate{} = MState) ->
    case aliases(Commands) of
        "exit" ->
            case MState#mstate.entity of
                "" ->
                    {exit, enter_mode("", MState)};
                _ ->
                    {exit, MState#mstate{entity = ""}}
            end;
        _ ->
            ok
    end.

enter_mode(Mode, #mstate{} = MState) ->
    ConnArgs = maps:new(),
    case aliases(Mode) of
        "exit" ->
            enter_mode("", MState);
        "show" ->
            wm_ctl:overview(grid, ConnArgs),
            io:format("~n"),
            wm_ctl:overview(jobs, ConnArgs),
            MState;
        _ ->
            case lists:member(Mode, get_ctl_modes()) of
                true ->
                    MState#mstate{mode = Mode};
                false ->
                    io:format("Command not found: ~s~n", [Mode]),
                    MState
            end
    end.

get_ctl_modes() ->
    ["", "grid", "cluster", "partition", "node", "user", "queue", "scheduler", "image", "global", "remote"].

aliases(X) ->
    get_alias([["exit", ".."], ["quit", "q"], ["list", "l"], ["show", "s"]], X).

get_alias([], X) ->
    X;
get_alias([List | T], X) ->
    case lists:member(X, List) of
        true ->
            hd(List);
        false ->
            get_alias(T, X)
    end.

prompt(#mstate{} = MState) ->
    Mode =
        case MState#mstate.mode of
            "" ->
                "";
            InSubMode ->
                " > " ++ InSubMode
        end,
    Entity =
        case MState#mstate.entity of
            "" ->
                "";
            InEntity ->
                " > " ++ InEntity
        end,
    "[" ++ net_adm:localhost() ++ Mode ++ Entity ++ "] ".

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{"SWM_SPOOL", P} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = P});
parse_args([{"SWM_ROOT", P} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{root = P});
parse_args([{args_line, Args} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{args_line = Args});
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, MState).
