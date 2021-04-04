#!/usr/bin/env escript
%
% Copyright (c) 2016-2017 Sky Workflows. All Rights Reserved.
%
% This software is the confidential and proprietary information of
% Sky Workflows ("Confidential Information"). You shall not
% disclose such Confidential Information and shall use it only in
% accordance with the terms of the license agreement you entered into
% with Sky Workflows or its subsidiaries.

%%! -smp enable

-define(ENV_LIB, "SWM_LIB").

main(["grid"]) ->
  add_paths(),
  GridID = wm_utils:uuid(v4),
  wm_cert:create(grid, GridID, "grid");
main(["cluster"]) ->
  add_paths(),
  ClusterID = wm_utils:uuid(v4),
  wm_cert:create(cluster, ClusterID, "cluster");
main(["node"]) ->
  add_paths(),
  NodeID = wm_utils:uuid(v4),
  wm_cert:create(node, NodeID, "node");
main(["skyport"]) ->
  add_paths(),
  NodeID = wm_utils:uuid(v4),
  {ok, Hostname} = inet:gethostname(),
  wm_cert:create(node, NodeID, Hostname);
main(["user", Name]) ->
  main(["user", Name, wm_utils:uuid(v4)]);
main(["user", Name, UserID]) ->
  add_paths(),
  wm_cert:create(user, UserID, Name);
main(["host"]) ->
  add_paths(),
  HostID = wm_utils:uuid(v4),
  wm_cert:create(host, HostID, "host");
main(Args) ->
  io:format("~nWrong arguments: ~p~n~n", [Args]),
  usage().

usage() ->
  Me = escript:script_name(),
  Msg = "Usage: ~n" ++
        "  $ export " ++ ?ENV_LIB ++ "~n" ++
        "  $ " ++ Me ++ " " ++ "grid~n" ++
        "  $ " ++ Me ++ " " ++ "cluster~n" ++
        "  $ " ++ Me ++ " " ++ "node~n" ++
        "  $ " ++ Me ++ " " ++ "user <username>~n" ++
        "  $ " ++ Me ++ " " ++ "host~n~n",
  io:format(Msg).

add_paths() ->
  LibDirs = case os:getenv("SWM_LIB") of
              false ->
                case os:getenv("SWM_ROOT") of
                  false ->
                    loge("nor SWM_LIB or SWM_ROOT are defined");
                  RootDir ->
                    [RootDir]
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

