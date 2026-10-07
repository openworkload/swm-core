-module(wm_ssh_server).

-behaviour(gen_server).

-export([start_link/1, get_address/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../lib/wm_log.hrl").
-include("../../include/wm_general.hrl").

-record(mstate,
        {spool = "" :: string(),
         daemon_pid = undefined :: pid() | undefined,
         listen_ip = undefined :: inet:ip_address() | undefined,
         listen_port = undefined :: inet:port_number() | undefined}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec get_address() -> {ok, inet:ip_address(), inet:port_number()} | {error, term()}.
get_address() ->
    gen_server:call(?MODULE, get_address).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init(term()) -> {ok, term()} | {ok, term(), hibernate | infinity | non_neg_integer()} | {stop, term()} | ignore.
-spec handle_call(term(), term(), term()) ->
                     {reply, term(), term()} |
                     {reply, term(), term(), hibernate | infinity | non_neg_integer()} |
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()} |
                     {stop, term(), term(), term()}.
-spec handle_cast(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec handle_info(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec terminate(term(), term()) -> ok.
-spec code_change(term(), term(), term()) -> {ok, term()}.
init(Args) ->
    MState = parse_args(Args, #mstate{}),
    Spool = MState#mstate.spool,
    ListenPort = wm_conf:g(ssh_daemon_listen_port, {?DEFAULT_SSH_DAEMON_PORT, integer}),
    ListenIP = resolve_listen_ip(),
    Options = [{tcpip_tunnel_out, true}, {failfun, fun failfun/2} | wm_ssh_key_cb:daemon_options(Spool)],
    case spawn_ssh_daemon(ListenIP, ListenPort, Options) of
        {Pid, BoundIP, BoundPort} ->
            ?LOG_INFO("SSH tunnel server has been started on ~p:~p", [BoundIP, BoundPort]),
            {ok,
             MState#mstate{daemon_pid = Pid,
                           listen_ip = BoundIP,
                           listen_port = BoundPort}};
        {error, Error} ->
            ?LOG_INFO("SSH tunnel server can't be started: ~p", [Error]),
            {stop, Error}
    end.

handle_call(get_address, _From, #mstate{listen_ip = undefined} = MState) ->
    {reply, {error, "Listen IP is unknown"}, MState};
handle_call(get_address, _From, #mstate{listen_port = undefined} = MState) ->
    {reply, {error, "Listen port is unknown"}, MState};
handle_call(get_address, _From, #mstate{listen_port = Port, listen_ip = IP} = MState) ->
    {reply, {ok, IP, Port}, MState};
handle_call(_Msg, _From, #mstate{} = MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast(_, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, #mstate{daemon_pid = Pid}) ->
    stop_ssh_daemon(Pid),
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec resolve_listen_ip() -> inet:ip_address() | loopback | any.
resolve_listen_ip() ->
    case wm_conf:g(ssh_daemon_listen_ip, {default_ssh_listen_ip(), string}) of
        "loopback" ->
            loopback;
        "localhost" ->
            loopback;
        "127.0.0.1" ->
            {127, 0, 0, 1};
        "::1" ->
            {0, 0, 0, 0, 0, 0, 0, 1};
        "any" ->
            any;
        "0.0.0.0" ->
            any;
        IP when is_list(IP) ->
            case inet:parse_address(IP) of
                {ok, Addr} ->
                    Addr;
                {error, _} ->
                    ?LOG_ERROR("Invalid ssh_daemon_listen_ip ~p; using 127.0.0.1", [IP]),
                    {127, 0, 0, 1}
            end;
        Other ->
            ?LOG_ERROR("Invalid ssh_daemon_listen_ip ~p; using 127.0.0.1", [Other]),
            {127, 0, 0, 1}
    end.

%% Cloud job nodes often have no local global table yet (parent tunnel not up).
%% SWM_JOB_NODE_ROLE=main|compute => listen on all interfaces for Sky Port SSH.
-spec default_ssh_listen_ip() -> string().
default_ssh_listen_ip() ->
    case os:getenv("SWM_JOB_NODE_ROLE") of
        false ->
            "127.0.0.1";
        "" ->
            "127.0.0.1";
        _ ->
            "0.0.0.0"
    end.

-spec spawn_ssh_daemon(string() | inet:ip_address() | loopback | any, integer(), list()) ->
                          {pid(), inet:ip_address(), inet:port_number()} | {error, term()}.
spawn_ssh_daemon(Host, Port, Options) ->
    ?LOG_INFO("Starting SSH tunnel daemon on ~p:~p (publickey, shell/exec disabled)", [Host, Port]),
    case ssh:daemon(Host, Port, Options) of
        {ok, Pid} ->
            R = ssh:daemon_info(Pid),
            ?LOG_DEBUG("SSH daemon started: ~p", [R]),
            {ok, L} = R,
            ListenPort = proplists:get_value(port, L),
            ListenIP = proplists:get_value(ip, L),
            {Pid, ListenIP, ListenPort};
        Error ->
            ?LOG_ERROR("ssh:daemon error ~p", [Error]),
            {error, Error}
    end.

-spec stop_ssh_daemon(pid() | undefined) -> ok.
stop_ssh_daemon(undefined) ->
    ok;
stop_ssh_daemon(Pid) when is_pid(Pid) ->
    case is_process_alive(Pid) of
        false ->
            ok;
        true ->
            case ssh:stop_daemon(Pid) of
                ok ->
                    ok;
                {error, _} ->
                    ok
            end
    end.

failfun(_User, {authmethod, none}) ->
    ok;
failfun(User, Reason) ->
    ?LOG_ERROR("[ssh daemon] ~p failed to login: ~p~n", [User, Reason]).
