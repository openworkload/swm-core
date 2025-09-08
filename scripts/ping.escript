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

%% To run:
%%  export PATH=/opt/swm/current/erts-12.2/bin:$PATH
%%  ./ping.escript localhost 10001

main([Hostname, Port]) ->
    process_flag(trap_exit, true),
    add_paths(),
    ssl:start(),
    do_ping(Hostname, list_to_integer(Port)),
    ssl:stop();
main(_) ->
    usage().

do_ping(Hostname, Port) ->
    CaFile = "/opt/swm/spool/secure/cluster/cert.pem",
    CertFile = "/opt/swm/spool/secure/node/cert.pem",
    KeyFile = "/opt/swm/spool/secure/node/key.pem",
    Opts = [binary,
             {header, 0},
             {packet, 4},
             {active, false},
             {versions, ['tlsv1.3']},
             {partial_chain, wm_utils:get_cert_partial_chain_fun(CaFile)},
             {reuseaddr, true},
             {depth, 99},
             {verify, verify_peer},
             {server_name_indication, disable},
             {cacertfile, CaFile},
             {certfile, CertFile},
             {keyfile, KeyFile}
    ],
    io:format("Try to connect to swm at ~s:~p~n", [Hostname, Port]),
    case ssl:connect(Hostname, Port, Opts, 5000) of
        {ok, Socket} ->
            {ok, {IP, ClientPort}} = ssl:sockname(Socket),
            io:format("Connection info: ~p:~p~n", [IP, ClientPort]),
            ssl:send(Socket, wm_utils:encode_to_binary({call, wm_api, recv, {wm_pinger, ping}})),
            case ssl:recv(Socket, 0) of
                {ok, Data} ->
                   case binary_to_term(Data) of
                       {pong, State} ->
                           io:format("Pong: ~p~n", [State]);
                       Other ->
                           io:format("Unexpected ping data: ~p~n", [Other])
                   end;
                {error, Reason} ->
                    io:format("Receiving data error: ~p~n", [Reason])
            end;
        {error, Error} ->
            io:format("Connection error: ~p~n", [Error]),
            halt(1)
    end.

usage() ->
  Me = escript:script_name(),
  Msg = "Usage: " ++ Me ++ " <HOSTNAME> <PORT>'~n",
  io:format(Msg).

add_paths() ->
  LibDirs = case os:getenv("SWM_LIB", "./_build/default/lib/swm/ebin/") of
                false ->
                    io:format("ERROR: SWM_LIB is undefined~n");
                [] ->
                    io:format("ERROR: SWM_LIB environment variable is empty~n"),
                    [];
                Dirs ->
                    string:tokens(Dirs, ":")
            end,
  F = fun(Dir) ->
          case filelib:is_dir(Dir) of
              false ->
                  io:format("ERROR: directory not found: '" ++ Dir ++ "'~n");
              true ->
                  true = code:add_path(Dir)
          end
      end,
  [F(X) || X <- lists:foldl(fun(X, Acc) -> filelib:wildcard(X) ++ Acc end, [], LibDirs)].

