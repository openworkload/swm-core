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
    %% run-mocked.sh binds SWM_GATE_HOST (default 127.0.0.1). Also probe
    %% localhost aliases and the short hostname for older gate checkouts.
    Hosts = gate_listen_hosts(),
    case wait_gate_port(Hosts, 8444, 60) of
        ok ->
            case wait_gate_mtls("127.0.0.1", 8444, 40) of
                ok ->
                    {ok, Pid};
                {error, Reason} ->
                    ct:fail({gate_mtls_not_ready, Reason})
            end;
        {error, timeout} ->
            ct:fail({gate_not_ready, Hosts, 8444})
    end.

-spec gate_listen_hosts() -> [string()].
gate_listen_hosts() ->
    {ok, Hostname} = inet:gethostname(),
    lists:usort(["127.0.0.1", "localhost", "127.0.1.1", Hostname]).

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

%% @doc Wait until mTLS handshake to the gate succeeds with the node cert.
-spec wait_gate_mtls(string(), inet:port_number(), non_neg_integer()) -> ok | {error, term()}.
wait_gate_mtls(_Host, _Port, 0) ->
    {error, timeout};
wait_gate_mtls(Host, Port, TriesLeft) ->
    case try_gate_mtls(Host, Port) of
        ok ->
            ok;
        {error, Reason} ->
            ct:print("Gate mTLS probe failed (~p tries left): ~p", [TriesLeft, Reason]),
            timer:sleep(500),
            wait_gate_mtls(Host, Port, TriesLeft - 1)
    end.

-spec try_gate_mtls(string(), inet:port_number()) -> ok | {error, term()}.
try_gate_mtls(Host, Port) ->
    Spool = os:getenv("SWM_SPOOL", "/opt/swm/spool"),
    {CaFile, KeyFile, CertFile} = wm_utils:get_node_cert_paths(Spool),
    application:ensure_all_started(ssl),
    TlsOpts =
        [{verify, verify_peer},
         {versions, ['tlsv1.3', 'tlsv1.2']},
         {server_name_indication, disable},
         {partial_chain, wm_utils:get_cert_partial_chain_fun(CaFile)},
         {cacertfile, CaFile},
         {certfile, CertFile},
         {keyfile, KeyFile}],
    case ssl:connect(Host, Port, TlsOpts, 3000) of
        {ok, Sock} ->
            ssl:close(Sock),
            ok;
        {error, Reason} ->
            {error, Reason}
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
