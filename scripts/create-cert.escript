#!/usr/bin/env escript
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
  Domain = inet_db:res_option(domain),
  FQDN = case Domain of
    "" -> Hostname;
    _ -> Hostname ++ "." ++ Domain
  end,
  wm_cert:create(node, NodeID, FQDN);
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

