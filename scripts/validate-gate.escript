#!/usr/bin/env escript

-define(PORT, 8444).
-define(SERVER, "container").

-define(CA, "/opt/swm/spool/secure/cluster/ca-chain-cert.pem").
-define(KEY, "/opt/swm/spool/secure/node/key.pem").

-define(GUN_EBIN, "./_build/default/lib/gun/ebin").
-define(COWLIB_EBIN, "./_build/default/lib/cowlib/ebin").
-define(RANCH_EBIN, "./_build/default/lib/ranch/ebin").

main(_Args) ->
  process_flag(trap_exit, true),

  true = code:add_patha(?GUN_EBIN),
  true = code:add_patha(?COWLIB_EBIN),
  true = code:add_patha(?RANCH_EBIN),

  case application:ensure_all_started(gun) of
    {ok, StartedModules} ->
      io:format("Gun started: ~p~n", [StartedModules]);
    AppErr ->
      io:format(AppErr),
      halt(1)
  end,

  ConnPid = case gun:open(?SERVER,
                          ?PORT,
                          #{transport => tls,
                            protocols => [http],
                            tls_opts => [{verify, verify_peer},
                                         {cacertfile, ?CA},
                                         {keyfile, ?KEY}]
                           }
  ) of
    {ok, Pid} ->
      io:format("Opened connection to port ~p: ~p~n", [Pid, ?PORT]),
      Pid;
    OpenError ->
      io:format("ERROR1: ~p~n", [OpenError]),
      halt(1)
  end,

  case gun:await_up(ConnPid) of
    {ok, Protocol} ->
      io:format("Connection is UP, protocol: ~p~n", [Protocol]);
    AwaitUpError ->
      io:format("ERROR2: ~p~n", [AwaitUpError]),
      halt(1)
  end,

  Headers = [{<<"Accept">>, <<"application/json">>},
             {<<"username">>, <<"demo1">>},
             {<<"password">>, <<"demo1">>}],
  StreamRef = gun:get(ConnPid, "/openstack/images", Headers),

  case gun:await(ConnPid, StreamRef) of
    {response, nofin, 200, _} ->
      case gun:await_body(ConnPid, StreamRef) of
        {ok, Body} ->
          io:format("Response body: ~p~n", [Body]);
        ResponseError ->
          io:format("ERROR4: ~p~n", [ResponseError])
      end;
    AwaitError ->
      io:format("ERROR3: ~p~n", [AwaitError])
  end,

  gun:close(ConnPid).
