#!/usr/bin/env escript
%TODO Add copyright
%%! -smp enable

main([]) ->
  process_flag(trap_exit, true),
  add_paths(),
  Pid = wm_shell:start_link([{parent, wmjob},
                             {printer, stdout}
                            ]),
  loop(Pid);
main(Args) ->
  process_flag(trap_exit, true),
  add_paths(),
  ArgsDict = wm_args:normalize(Args),
  case wm_args:fetch(command, unknown, ArgsDict) of
    "-h" ->
      usage();
    _ ->
      ArgsLine = lists:flatten([X ++ " " || X <- Args]),
      Pid = wm_shell:start_link([{parent, wmjob},
                                 {args_line, ArgsLine},
                                 {printer, stdout}
                                ]),
      loop(Pid)
  end.

loop(Pid) ->
  receive
    {'EXIT', Pid, normal} ->
      halt();
    {'EXIT', From, Reason} ->
      io:format("New message from ~p: ~p~n", [From, Reason]),
      loop(Pid);
    {Msg, Pid} ->
      io:format("New message from shell: ~p~n", [Msg]),
      loop(Pid)
  end.

usage() ->
  Me = escript:script_name(),
  Msg = "Usage: ~n" ++ Me ++ " "
        "command [OPTIONS] script-file~n"
        "Command:~n"
        "  submit~n"
        "  delete~n"
        "  show~n"
        "  hold~n"
        "  release~n"
        "  suspend~n"
        "  resume~n"
        "  trace~n"
        "Otions:~n...~n",
  io:format(Msg).

add_paths() ->
  LibDirs = case os:getenv("SWM_LIB") of
              false ->
                case os:getenv("SWM_ROOT") of
                  false ->
                    loge("nor SWM_LIB or SWM_ROOT are defined");
                  RootDir ->
                    RootDir
                end;
              [] ->
                loge("SWM_LIB environment variable is empty");
              Dirs ->
                string:tokens(Dirs, ":")
            end,
  F = fun(Dir) ->
        case filelib:is_dir(Dir) of
          false ->
            loge("Directory not found: '" ++ Dir ++ "'");
          true ->
            true = code:add_path(Dir)
        end
      end,
  [F(X) || X <- lists:foldl(fun(X, Acc) -> filelib:wildcard(X) ++ Acc end, [], LibDirs)].

loge(Msg) ->
  io:format("ERROR: " ++ Msg ++ "~n"),
  halt(1).

