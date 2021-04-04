#!/usr/bin/env escript
%% -*- coding: utf-8 -*-
%%! -smp enable

-include("../../src/lib/wm_log.hrl").
-include("../../include/wm_scheduler.hrl").

-define(JSON_FILE_PATH, "./setup.json").
-define(JSON_TO_BIN, "../../../swm-sched/scripts/json-to-bin.escript").
-define(SWM_ROOT, "../../_build/default/rel/swm").
-define(SWM_EBIN, ?SWM_ROOT ++ "/ebin").
-define(SWM_BIN, ?SWM_ROOT ++ "/bin").
-define(SWM_LIB, ?SWM_ROOT ++ "/lib").
-define(SWM_LIB64, ?SWM_ROOT ++ "/lib64").

set_libs() ->
  AddLibDir = fun(Dir) ->
                case filelib:is_dir(Dir) of
                  false ->
                    io:format("Directory not found: '" ++ Dir ++ "'~n"),
                    halt(1);
                  true ->
                    true = code:add_patha(Dir)
                end
              end,
  case os:getenv("SWM_LIB") of
    false ->
      AddLibDir(?SWM_LIB);
    LibDir ->
      AddLibDir(LibDir)
  end.

prepare(Verbosity) ->
  set_libs(),
  wm_log:start_link([{printer, Verbosity}]).

get_binary(Verbosity) ->
  PortArgs = [{exec, ?JSON_TO_BIN ++ " " ++ ?JSON_FILE_PATH},
              {verbosity, Verbosity}
             ],
  {ok, Pid} = wm_port:start_link(PortArgs),
  PortOpts = [{parallelism, true},
              use_stdio,
              exit_status,
              stream,
              binary],
  wm_port:subscribe(Pid),
  ok = wm_port:run(Pid, [], [], PortOpts, ?SCHEDULE_START_TIMEOUT),
  ?LOG_DEBUG("json-to-bin has been started"),
  loop_json_converter(<<>>).

test_via_port(Verbosity) ->
  prepare(Verbosity),
  BinIn = get_binary(Verbosity),
  ?LOG_DEBUG("Scheduler input size: ~p", [byte_size(BinIn)]),
  PortArgs = case Verbosity of
          stdout ->
            [{exec, ?SWM_BIN ++ "/swm-sched -d -p " ++ ?SWM_LIB64},
             {verbosity, Verbosity}];
          _ ->
            [{exec, ?SWM_BIN ++ "/swm-sched -p " ++ ?SWM_LIB64},
             {verbosity, Verbosity}]
         end,
  {ok, WmPortPid} = wm_port:start_link(PortArgs),
  PortOpts = [{parallelism, true},
              use_stdio,
              exit_status,
              stream,
              binary],
  ok = wm_port:run(WmPortPid, [], [], PortOpts, ?SCHEDULE_START_TIMEOUT),
  ?LOG_DEBUG("Scheduler has been started"),
  wm_port:subscribe(WmPortPid),
  wm_port:cast(WmPortPid, BinIn),
  receive_scheduler_result(<<>>, WmPortPid, BinIn).

loop_json_converter(Bin) ->
  receive
    {exit_status, 0, _} ->
      Bin;
    {output, Chunk, _} ->
      loop_json_converter(<<Bin/binary, Chunk/binary>>)
  end.

receive_scheduler_result(Bin, WmPortPid, BinIn) ->
  receive
    {exit_status, 0, _} ->
      Bin;
    {output, Chunk, _} ->
      SchedResult = erlang:binary_to_term(Chunk),
      TT = wm_entity:get_attr(timetable, SchedResult),
      io:format("Received scheduler result: ~p~n", [SchedResult]),
      io:format("Timetable: ~p~n", [TT]),
      case length(TT) > 0 of
        true ->
          halt(0);
        _ ->
          halt(1)
      end
  end.

main([]) ->
  test_via_port(none);
main(["-d"|_]) ->
  test_via_port(stdout).
