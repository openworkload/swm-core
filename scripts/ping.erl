#!/usr/bin/env escript
%%! -smp enable

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
            io:format("Connection error: ~p~n", [Error])
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

