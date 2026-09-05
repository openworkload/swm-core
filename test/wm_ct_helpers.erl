-module(wm_ct_helpers).

-compile(export_all).

%% @doc start external gate program as a separate erlang process
-spec run_gate_system_process() -> pid().
run_gate_system_process() ->
    Pid = proc_lib:spawn(fun() ->
                            Output = lists:flatten(run_command()),
                            ct:print("Gate runner final output: ~p", [Output])
                         end),
    ct:print("Gate pid: ~p", [Pid]),
    ok = wait_gate_port(8444, 30),
    {ok, Pid}.

%% @doc Wait until the mocked cloud-gate listens on Port (or give up after N tries).
-spec wait_gate_port(inet:port_number(), non_neg_integer()) -> ok | {error, timeout}.
wait_gate_port(_Port, 0) ->
    {error, timeout};
wait_gate_port(Port, TriesLeft) ->
    case gen_tcp:connect("127.0.0.1", Port, [], 500) of
        {ok, Sock} ->
            gen_tcp:close(Sock),
            ok;
        {error, _} ->
            timer:sleep(500),
            wait_gate_port(Port, TriesLeft - 1)
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
