#!/usr/bin/env escript
%% -*- coding: utf-8 -*-
%%! -smp enable

-include("../../src/lib/wm_log.hrl").
-include("../../include/wm_scheduler.hrl").

-define(DEFAULT_SWM_LIB, "../../../_build/default/lib/swm/ebin").
-define(PORTER_START_TIMEOUT, 5000).

get_final_binary() ->
  User1 = wm_entity:new(user),
  User2 = wm_entity:set_attr([
                              {name, os:getenv("USER")},
                              {id, wm_utils:uuid(v4)}
                             ], User1),
  UserBin = erlang:term_to_binary(User2),
  UserBinSize = byte_size(UserBin),
  JobScriptContent = "#!/usr/bin/env bash\necho SWM_JOB_ID=${SWM_JOB_ID}\nsleep 20\n",

  Job1 = wm_entity:new(job),
  Job2 = wm_entity:set_attr({id, "10000000-0000-0000-0000-000000000000"}, Job1),
  Job3 = wm_entity:set_attr({name, "Test Job"}, Job2),
  Job4 = wm_entity:set_attr({state, "Q"}, Job3),
  Job5 = wm_entity:set_attr({job_stdout, "%j.out"}, Job4),
  Job6 = wm_entity:set_attr({job_stderr, "%j.err"}, Job5),
  Job7 = wm_entity:set_attr({workdir, "/tmp"}, Job6),
  Job8 = wm_entity:set_attr({script_content, JobScriptContent}, Job7),
  JobBin = erlang:term_to_binary(Job8),
  JobBinSize = byte_size(JobBin),
  ?LOG_DEBUG(">>>>>> Job: ~p", Job8),
  ?LOG_DEBUG(">>>>>> JobBin: ~p", JobBin),
  ?LOG_DEBUG(">>>>>> JobBinSize: ~p", JobBinSize),

  <<?PORTER_COMMAND_RUN/integer,
    ?PORTER_DATA_TYPES_COUNT/integer,
    ?PORTER_DATA_TYPE_USERS/integer, UserBinSize:4/big-integer-unit:8, UserBin/binary,
    ?PORTER_DATA_TYPE_JOBS/integer, JobBinSize:4/big-integer-unit:8, JobBin/binary>>.

test_via_port(Verbosity) ->
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
      AddLibDir(?DEFAULT_SWM_LIB);
    LibDir ->
      AddLibDir(LibDir)
  end,
  wm_log:start_link([{printer, Verbosity}]),
  PortArgs = case Verbosity of
          stdout ->
            [{exec, "../../c_src/porter/swm-porter -d"},
             {verbosity, Verbosity}];
          _ ->
            [{exec, "../../c_src/porter/swm-porter"},
             {verbosity, Verbosity}]
         end,
  {ok, WmPortPid} = wm_port:start_link(PortArgs),
  BinIn = get_final_binary(),
  PortOpts = [{parallelism, true},
              use_stdio,
              exit_status,
              stream,
              binary],
  ok = wm_port:run(WmPortPid, [], [], PortOpts, ?PORTER_START_TIMEOUT),
  ?LOG_DEBUG("Job porter started successfully"),
  wm_port:subscribe(WmPortPid),
  wm_port:cast(WmPortPid, BinIn),
  Outputs = loop([]),
  test_outputs(Outputs).

loop(Outputs) ->
  receive
    {exit_status, 0, _} ->
      Outputs;
    {output, BinOut, _} ->
      Out = erlang:binary_to_term(BinOut),
      loop([Out|Outputs])
  end.

test_outputs([{process, _, "F",  0,  0, _},
               {process, _, "R", -1, -1, _},
               {process, _, "R", -1, -1, _},
               {process, _, "R", -1, -1, _},
               {process, _, "R", -1, -1, _},
               {process, _, "R", -1, -1, _}
              ]) ->
  halt(0);
test_outputs(List) ->
  io:format("FAIL: ~p~n", [List]),
  halt(1).

main([]) ->
  test_via_port(none);
main(["-d"|_]) ->
  test_via_port(stdout).

