-module(wm_ct_helpers).

-compile(export_all).

%% @doc start external gate program as a separate erlang process
-spec run_gate_system_process() -> {ok, pid()}.
run_gate_system_process() ->
    Pid = proc_lib:spawn(fun() ->
                            Output = lists:flatten(run_command()),
                            ct:print("Gate runner final output: ~p", [Output])
                         end),
    ct:print("Gate pid: ~p", [Pid]),
    %% swm-cloud-gate/run.py binds uvicorn to socket.getfqdn(). On Ubuntu that
    %% often resolves to 127.0.1.1 (see /etc/hosts), not 127.0.0.1. Probe the
    %% same names clients use (inet:gethostname/0 in wm_gate_SUITE) plus the
    %% common loopback aliases so CI and local docker both succeed.
    Hosts = gate_listen_hosts(),
    case wait_gate_port(Hosts, 8444, 60) of
        ok ->
            {ok, Pid};
        {error, timeout} ->
            ct:fail({gate_not_ready, Hosts, 8444})
    end.

-spec gate_listen_hosts() -> [string()].
gate_listen_hosts() ->
    {ok, Hostname} = inet:gethostname(),
    lists:usort([Hostname, "localhost", "127.0.0.1", "127.0.1.1"]).

%% @doc Wait until the mocked cloud-gate accepts TCP on any of Hosts:Port.
-spec wait_gate_port([string()], inet:port_number(), non_neg_integer()) -> ok | {error, timeout}.
wait_gate_port(_Hosts, _Port, 0) ->
    {error, timeout};
wait_gate_port(Hosts, Port, TriesLeft) ->
    case try_connect_any(Hosts, Port) of
        ok ->
            ok;
        {error, _} ->
            timer:sleep(500),
            wait_gate_port(Hosts, Port, TriesLeft - 1)
    end.

-spec try_connect_any([string()], inet:port_number()) -> ok | {error, term()}.
try_connect_any([], _Port) ->
    {error, econnrefused};
try_connect_any([Host | Rest], Port) ->
    case gen_tcp:connect(Host, Port, [binary, {active, false}], 500) of
        {ok, Sock} ->
            gen_tcp:close(Sock),
            ok;
        {error, _} ->
            try_connect_any(Rest, Port)
    end.

run_command() ->
    Command = "./run-mocked.sh",
    Dir = get_gate_dir(),
    ct:print("Gate runner command: ~p, dir: ~p", [Command, Dir]),
    Opt = [stream, exit_status, use_stdio, stderr_to_stdout, in, eof, {cd, Dir}],
    P = open_port({spawn, Command}, Opt),
    get_command_data(P, []).

get_gate_dir() ->
    CurrentDir =
        filename:dirname(
            code:which(?MODULE)),
    DefaultGateDir =
        filename:absname(
            filename:join([CurrentDir, "../../../../../../swm-cloud-gate"])),
    os:getenv("SWM_GATE_DIR", DefaultGateDir).

get_command_data(P, D) ->
    receive
        {P, {data, D1}} ->
            ct:print("Output: ~p", [D1]),
            get_command_data(P, [D | D1]);
        {P, eof} ->
            port_close(P),
            receive
                {P, {exit_status, N}} ->
                    {N, lists:reverse(D)}
            end
    end.

kill_gate_system_process() ->
    SysPid =
        string:trim(
            os:cmd("cat /tmp/cm-cloud-gate.tmp/pid")),
    Command = io_lib:format("kill -2 ~p", [SysPid]),
    ct:print("Kill cloud gate command: ~p", [Command]),
    os:cmd(Command).

-spec get_fsm_state_name(pid()) -> {ok, atom()}.
get_fsm_state_name(Pid) ->
    {status, _, {module, gen_statem}, [_, running, _, _, InfoList]} = sys:get_status(Pid),
    GetStatus =
        fun ({"Status", _}) ->
                true;
            (_) ->
                false
        end,
    GetResult =
        fun ({data, _}) ->
                true;
            (_) ->
                false
        end,
    {value, {data, DataList}} = lists:search(GetResult, InfoList),
    {value, {"Status", StateName}} = lists:search(GetStatus, DataList),
    StateName.
