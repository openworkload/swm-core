-module(wm_http).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([add_route/2]).

-include("../../lib/wm_log.hrl").

-record(mstate, {routes = #{} :: map(), spool :: string()}).

-define(DEFAULT_HTTPS_PORT, 8443).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec add_route(term(), list() | {list(), atom()}) -> ok.
add_route(Type, Resource) ->
    gen_server:cast(?MODULE, {add_route, Resource, Type}).

%% ============================================================================
%% Server callbacks
%% ============================================================================

handle_call(_Msg, _From, MState) ->
    {reply, ok, MState}.

handle_cast({add_route, Resource, Type}, MState) ->
    Map = maps:put(Resource, Type, MState#mstate.routes),
    MState2 = MState#mstate{routes = Map},
    update_routes(MState2),
    {noreply, MState2};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Unknown cast: ~p", [Msg]),
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

%% @hidden
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    MState2 = MState#mstate{routes = #{"/" => {api, wm_http_top}}},
    Dispatch = dispatch_rules(MState2#mstate.routes, []),
    Port = wm_conf:g(https_port, {?DEFAULT_HTTPS_PORT, integer}),
    CA = filename:join([MState2#mstate.spool, "secure/cluster/cert.pem"]),
    Cert = filename:join([MState2#mstate.spool, "secure/node/cert.pem"]),
    Key = filename:join([MState2#mstate.spool, "secure/node/key.pem"]),
    {ok, ServerCAs} = file:read_file(CA),
    Pems = public_key:pem_decode(ServerCAs),
    CaCerts = lists:map(fun({_, Der, _}) -> Der end, Pems),
    PartChain = fun(ChainCerts) -> enum_cacerts(CaCerts, ChainCerts) end,
    {ok, Result} =
        cowboy:start_tls(https,
                         [{port, Port},
                          {depth, 99},
                          {verify, verify_peer},
                          {versions, ['tlsv1.2', 'tlsv1.1', tlsv1]},
                          {fail_if_no_peer_cert, true},
                          {partial_chain, PartChain},
                          {cacertfile, CA},
                          {certfile, Cert},
                          {keyfile, Key}],
                         #{env => #{dispatch => Dispatch}, onresponse => fun error_hook/4}),
    ?LOG_INFO("Web server has been started on port ~p: ~p", [Port, Result]),
    wm_event:announce(http_started),
    {ok, MState2}.

enum_cacerts([], _Certs) ->
    unknown_ca;
enum_cacerts([Cert | Rest], Certs) ->
    case lists:member(Cert, Certs) of
        true ->
            {trusted_ca, Cert};
        false ->
            enum_cacerts(Rest, Certs)
    end.

parse_args([], MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

dispatch_rules(Map, Routes) when is_map(Map) ->
    List = maps:to_list(Map),
    dispatch_rules(List, Routes);
dispatch_rules([], Routes) ->
    cowboy_router:compile([{'_', Routes}]);
dispatch_rules([{Resource, {api, HandlerModule}} | T], Routes) ->
    Route = {Resource, HandlerModule, []},
    dispatch_rules(T, [Route | Routes]);
dispatch_rules([{Resource, {static, FsPath}} | T], Routes) ->
    Static = {Resource, cowboy_static, {dir, FsPath}},
    dispatch_rules(T, [Static | Routes]).

error_hook(404, Headers, <<>>, Req) ->
    Path = cowboy_req:path(Req),
    Body = ["404 Not Found: \"", Path, "\" is not the path you are looking for.\n"],
    Headers2 =
        lists:keyreplace(<<"content-length">>, 1, Headers, {<<"content-length">>, integer_to_list(iolist_size(Body))}),
    cowboy_req:reply(404, Headers2, Body, Req);
error_hook(Code, Headers, <<>>, Req) when is_integer(Code), Code >= 400 ->
    Body = ["HTTP Error ", integer_to_list(Code), $\n],
    Headers2 =
        lists:keyreplace(<<"content-length">>, 1, Headers, {<<"content-length">>, integer_to_list(iolist_size(Body))}),
    cowboy_req:reply(Code, Headers2, Body, Req);
error_hook(_Code, _Headers, _Body, Req) ->
    Req.

update_routes(MState) ->
    Rules = dispatch_rules(MState#mstate.routes, []),
    cowboy:set_env(https, dispatch, Rules).
