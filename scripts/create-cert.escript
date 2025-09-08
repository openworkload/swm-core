#!/usr/bin/env escript
%
% SPDX-FileCopyrightText: © 2021 Taras Shapovalov
% SPDX-License-Identifier: BSD-3-Clause
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%
% * Redistributions of source code must retain the above copyright notice, this
% list of conditions and the following disclaimer.
%
% * Redistributions in binary form must reproduce the above copyright notice,
% this list of conditions and the following disclaimer in the documentation
% and/or other materials provided with the distribution.
%
% * Neither the name of the copyright holder nor the names of its
% contributors may be used to endorse or promote products derived from
% this software without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
% OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%
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

