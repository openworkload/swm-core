-module(wm_ssh_tunnel_server).

-behaviour(gen_server).

-export([start_link/1, get_address/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../lib/wm_log.hrl").

-record(mstate,
        {spool = "" :: string(),
         daemon_pid = none :: pid() | none,
         listen_ip = none :: inet:ip_address() | none,
         listen_port = none :: inet:port_number() | none
        }).

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
    HostCertsDir = filename:join([Spool, "secure/host"]),
    SystemDir = HostCertsDir,
    UserDir = HostCertsDir,
    case spawn_ssh_daemon(any,  % host
                          0,    % random free port is selected
                          [{tcpip_tunnel_in, true},
                           {system_dir, SystemDir},
                           {user_dir, UserDir},
                           {user_passwords, [{"foo", "bar"}]},
                           {failfun, fun failfun/2}])
    of
        {Pid, ListenIP, ListenPort} ->
            ?LOG_INFO("SSH tunnel server has been started"),
            {ok,
             MState#mstate{daemon_pid = Pid,
                           listen_ip = ListenIP,
                           listen_port = ListenPort}};
        {error, Error} ->
            ?LOG_INFO("SSH tunnel server can't be started: ~p", [Error]),
            {stop, Error}
    end.

handle_call(get_address, _From, #mstate{listen_ip=none} = MState) ->
  {reply, {error, "Listen IP is unknown"}, MState};
handle_call(get_address, _From, #mstate{listen_port=none} = MState) ->
  {reply, {error, "Listen port is unknown"}, MState};
handle_call(get_address, _From, #mstate{listen_port=Port, listen_ip=IP} = MState) ->
  {reply, {ok, IP, Port}, MState};
handle_call(_Msg, _From, #mstate{} = MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast(_, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
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

-spec spawn_ssh_daemon(string() | inet:ip_address() | loopback | any, integer(), list()) ->
                          {pid(), inet:port_number(), inet:ip_address()} | {error, term()}.
spawn_ssh_daemon(Host, Port, Options) ->
    ?LOG_INFO("~p:~p run ssh:daemon(~p, ~p, ~p)", [?MODULE, ?LINE, Host, Port, Options]),
    case ssh:daemon(Host, Port, Options) of
        {ok, Pid} ->
            R = ssh:daemon_info(Pid),
            ?LOG_DEBUG("~p:~p ssh:daemon_info(~p) ->~n ~p", [?MODULE, ?LINE, Pid, R]),
            {ok, L} = R,
            ListenPort = proplists:get_value(port, L),
            ListenIP = proplists:get_value(ip, L),
            {Pid, ListenIP, ListenPort};
        Error ->
            ?LOG_ERROR("ssh:daemon error ~p", [Error]),
            {error, Error}
    end.

failfun(_User, {authmethod, none}) ->
    ok;
failfun(User, Reason) ->
    ?LOG_ERROR("[ssh daemon] ~p failed to login: ~p~n", [User, Reason]).
