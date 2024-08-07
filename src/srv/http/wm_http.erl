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
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    MState2 = MState#mstate{routes = #{"/" => {api, wm_http_top}}},
    Dispatch = dispatch_rules(MState2#mstate.routes, []),
    Port = wm_conf:g(https_port, {?DEFAULT_HTTPS_PORT, integer}),
    {CaFile, KeyFile, CertFile} = wm_utils:get_node_cert_paths(MState#mstate.spool),
    {ok, Result} =
        cowboy:start_tls(https,
                         [{port, Port},
                          {depth, 99},
                          {verify, verify_peer},
                          {versions, ['tlsv1.3', 'tlsv1.2']},
                          {fail_if_no_peer_cert, true},
                          {partial_chain, wm_utils:get_cert_partial_chain_fun(CaFile)},
                          {cacertfile, CaFile},
                          {certfile, CertFile},
                          {keyfile, KeyFile}],
                         #{env => #{dispatch => Dispatch}, onresponse => fun error_hook/4}),
    ?LOG_INFO("Web server has been started on port ~p: ~p", [Port, Result]),
    wm_event:announce(http_started),
    {ok, MState2}.

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
