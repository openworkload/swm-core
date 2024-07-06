-module(wm_grid).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([get_nodes/1]).

-include("../../lib/wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec get_nodes(number()) -> list().
get_nodes(Limit) ->
    gen_server:call(?MODULE, {get_nodes, Limit}).

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
    ?LOG_INFO("Load grid management service"),
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    wm_event:subscribe(http_started, node(), ?MODULE),
    {ok, MState}.

handle_call({get_nodes, Limit}, _, MState) ->
    Nodes = wm_conf:select(node, {all, Limit}),
    {reply, Nodes, MState};
handle_call(_Msg, _From, MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast({event, EventType, EventData}, MState) ->
    {noreply, handle_event(EventType, EventData, MState)};
handle_cast(_Msg, MState) ->
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
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

handle_event(http_started, _, #mstate{} = MState) ->
    ?LOG_INFO("Initialize REST API resources"),
    wm_http:add_route({api, wm_grid_rest}, "/grid"),
    MState.
