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
    timer:sleep(2000),  % allow the gate process to initialize
    {ok, Pid}.

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
    {status, _, {module, gen_fsm}, [_, running, _, _, InfoList]} = sys:get_status(Pid),
    GetStatus =
        fun ({"StateName", _}) ->
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
    {value, {"StateName", StateName}} = lists:search(GetStatus, DataList),
    StateName.
