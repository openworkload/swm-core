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

%%! -smp enable

% NOTE:
% The script is used to for schedulers test and development.
% It is not supposed to be a part of a release deployment.

-define(PORT, 2205).

main(Args) ->
  process_flag(trap_exit, true),
  add_paths(),
  Pid = wm_tcpserver:start_link({?PORT, schedulers}),
  loop(Pid);

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

connection_loop(Socket, #mstate{}=MState) ->
  ?LOG_DEBUG("Enter loop"),
  case wm_tcpserver:recv(Socket) of
    {ok, {ModuleBin, Method}, Args, CallID} ->
      ?LOG_DEBUG("API call: module=~p, method=~p", [ModuleBin, Method]),
      case verify_rpc(ModuleBin, Method, Socket) of
        {ok, {module, Module}} ->
          ?LOG_DEBUG("RPC: module=~p, method=~p, args=~p",
                     [Module, Method, Args]),
          try
            Result = gen_server:call(Module, {Method, Args}, ?CONN_TIMEOUT),
            ?LOG_DEBUG("Call result: ~p", [Result]),
            wm_tcpserver:reply(Result, Socket, CallID)
          catch
            T:Error ->
              Msg = {string, io_lib:format("Cannot perorm RPC: ~p:~p(~p)",
                                           [Module, Method, Args])},
              ?LOG_DEBUG("RPC ERROR [1]: ~p:~p", [T,Error]),
              wm_tcpserver:reply(Msg, Socket, CallID)
          end,
          MState;
        {loop, {module, Module}} -> %TODO Impl several RPCs via one connection
          try
            Result= gen_server:call(Module, {Method, Args}, ?CONN_TIMEOUT),
            wm_tcpserver:reply(Result, Socket, CallID)
          catch
            E1:E2 ->
              Msg = {string, io_lib:format("Cannot perorm RPC: ~p:~p(~p)",
                                           [Module, Method, Args])},
              ?LOG_DEBUG("RPC ERROR [2]: ~p:~p", [E1, E2]),
              wm_tcpserver:reply(Msg, Socket, CallID)
          end,
          connection_loop(Socket, MState);
        {error, Reason} ->
          wm_tcpserver:reply({error, Reason}, Socket, CallID),
          MState
      end;
    Other ->
      ?LOG_INFO("Received asnwer: ~p", [Other]),
      MState
  end.

add_paths() ->
  LibDirs = case os:getenv("SWM_LIB") of
            false ->
              case os:getenv("SWM_ROOT") of
                false ->
                  loge("nor SWM_LIB or SWM_ROOT are defined");
                RootDir ->
                  [filename:join([RootDir, "current", "lib"])]
              end;
            [] ->
              loge("SWM_LIB environment variable is empty");
            Dirs ->
              string:tokens(Dirs, ":")
          end,
  F = fun(Dir) ->
        UnrolledDir = wm_utils:unroll_symlink(Dir),
        case filelib:is_dir(UnrolledDir) of
          false ->
            loge("Directory not found: '" ++ UnrolledDir ++ "'");
          true ->
            true = code:add_patha(UnrolledDir)
        end
      end,
  [F(X) || X <- LibDirs].

loge(Msg) ->
  io:format("ERROR: " ++ Msg ++ "~n"),
  halt(1).

