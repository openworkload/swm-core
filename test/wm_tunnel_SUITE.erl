-module(wm_tunnel_SUITE).

-export([suite/0, all/0, groups/0, init_per_suite/1, end_per_suite/1]).
-export([one_server_two_clients/1]).

-include_lib("common_test/include/ct.hrl").

-define(KEYS_DIR, "/opt/swm/spool/secure/host").

%% ============================================================================
%% Common test callbacks
%% ============================================================================

-spec suite() -> list().
suite() ->
    [{timetrap, {seconds, 60}}].

-spec all() -> list().
all() ->
    [{group, common}].

-spec groups() -> list().
groups() ->
    [{common, [], [one_server_two_clients]}].

-spec init_per_suite(list()) -> list().
init_per_suite(Config) ->
    ResultSsh = application:start(ssh),
    ct:print("Application ssh has been started: ~p", [ResultSsh]),
    Config.

-spec end_per_suite(list()) -> list().
end_per_suite(Config) ->
    ok = application:stop(ssh),
    Config.

%% ============================================================================
%% Tests
%% ============================================================================

-spec one_server_two_clients(list()) -> atom().
one_server_two_clients(_Config) ->
    Args = [{spool, "/opt/swm/spool"}],
    {ok, ServerModulePid} = wm_ssh_server:start_link(Args),
    {ok, ClientModulePid} = wm_ssh_client:start_link(Args),

    {ok, RemoteHost, RemotePort} = wm_ssh_server:get_address(),
    ok = wm_ssh_client:connect(RemoteHost, RemotePort),

    {JobSock1, LocalHost1, JobPort1} = tunnel_local_listner(),

    ListenHost = {127, 0, 0, 1},
    {ok, JobPort1_2} = wm_ssh_client:make_tunnel(ListenHost, 0, RemoteHost, JobPort1),
    % We use 2 job ports in the test because the both daemon and client are running on the same machine.
    % In this case JobPort1_2 is selected randomly (we pass 0 to tcpip_tunnel_to_server).
    test_tunneling(JobSock1, LocalHost1, JobPort1_2),

    {JobSock2, LocalHost2, JobPort2} = tunnel_local_listner(),
    {ok, JobPort2_2} = wm_ssh_client:make_tunnel(ListenHost, 0, RemoteHost, JobPort2),
    test_tunneling(JobSock2, LocalHost2, JobPort2_2),

    gen_server:stop(ClientModulePid),
    gen_server:stop(ServerModulePid).

%% ============================================================================
%% Helpers
%% ============================================================================

tunnel_local_listner() ->
    {ok, LSock} = gen_tcp:listen(0, [{active, false}]),
    {ok, {LHost, LPort}} = inet:sockname(LSock),
    {LSock, LHost, LPort}.

test_tunneling(ListenSocket, Host, Port) ->
    {ok, Client1} = gen_tcp:connect(Host, Port, [{active, false}]),
    {ok, Server1} = gen_tcp:accept(ListenSocket),
    {ok, Client2} = gen_tcp:connect(Host, Port, [{active, false}]),
    {ok, Server2} = gen_tcp:accept(ListenSocket),
    send_rcv("Hello!", Client1, Server1),
    send_rcv("Happy to see you!", Server1, Client1),
    send_rcv("Hello, you to!", Client2, Server2),
    send_rcv("Happy to see you too!", Server2, Client2),
    close_and_check(Client1, Server1),
    send_rcv("Still there?", Client2, Server2),
    send_rcv("Yes!", Server2, Client2),
    close_and_check(Server2, Client2).

send_rcv(Txt, From, To) ->
    ct:log("Send ~p from ~p to ~p", [Txt, From, To]),
    ok = gen_tcp:send(From, Txt),
    ct:log("Recv ~p on ~p", [Txt, To]),
    {ok, Txt} = gen_tcp:recv(To, 0, 5000),
    ok.

close_and_check(OneSide, OtherSide) ->
    ok = gen_tcp:close(OneSide),
    ok = chk_closed(OtherSide).

chk_closed(Sock) ->
    chk_closed(Sock, 0).

chk_closed(Sock, Timeout) ->
    case gen_tcp:recv(Sock, 0, Timeout) of
        {error, closed} ->
            ok;
        {error, timeout} ->
            chk_closed(Sock, 2 * max(Timeout, 250));
        Other ->
            Other
    end.
