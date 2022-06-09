-module(wm_ssh_tunnel_client).

-behaviour(gen_server).

-export([start_link/1, connect/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../lib/wm_log.hrl").

-record(mstate, {spool = "" :: string()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec connect(inet:ip_address(), inet:port_number()) -> reference().
connect(Host, Port) ->
    gen_server:call(?MODULE, {connect, Host, Port}).

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
    ?LOG_INFO("SSH tunnel server has been started"),
    {ok, MState}.

handle_call({connect, Host, Port}, _From, #mstate{spool=Spool} = MState) ->
    {reply, do_connect(Host, Port, Spool), MState};
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

-spec do_connect(any | string() | inet:ip_address(), inet:port_number(), string()) -> {ok, reference()}.
do_connect(any, Port, Spool) ->
    do_connect(wm_util:get_my_hostname(), Port, Spool);
do_connect(Host, Port, Spool) ->
    HostCertsDir = filename:join([Spool, "secure/host"]),
    Options = [{silently_accept_hosts, true},
               {user_dir, HostCertsDir},
               {user, "foo"},
               {password, "bar"},
               {user_interaction, false}],
    ConnectionRef = ssh:connect(Host, Port, Options),
    ?LOG_DEBUG("~p:~p ssh:connect(~p, ~p, ~p)~n -> ~p", [?MODULE, ?LINE, Host, Port, Options, ConnectionRef]),
    ConnectionRef.
