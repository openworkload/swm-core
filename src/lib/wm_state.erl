-module(wm_state).

-behaviour(gen_statem).

-export([start_link/1, enter/1, breakdown/1, get_current/0]).
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([stopped/3, loading/3, maint/3, offline/3, idle/3]).

-include("wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(_Args) ->
    gen_statem:start_link({local, ?MODULE}, ?MODULE, undefined, []).

-spec enter(atom()) -> ok.
enter(State) ->
    wm_conf:set_node_state(alloc, State, node()),
    gen_statem:cast(?MODULE, {enter, State}).

-spec breakdown(atom()) -> ok.
breakdown(State) ->
    gen_statem:cast(?MODULE, {breakdown, State}).

%% @doc Get current node state
-spec get_current() -> atom().
get_current() ->
    gen_statem:call(?MODULE, get_current).

%% ============================================================================
%% Callbacks
%% ============================================================================

-spec callback_mode() -> state_functions.
-spec init(term()) ->
              {ok, atom(), term()} |
              {ok, atom(), term(), hibernate | infinity | non_neg_integer()} |
              {stop, term()} |
              ignore.
-spec code_change(term(), atom(), term(), term()) -> {ok, term()}.
-spec terminate(term(), atom(), term()) -> ok.
callback_mode() ->
    state_functions.

init(_Args) ->
    ?LOG_DEBUG("Node state module has been started"),
    {ok, stopped, #mstate{}}.

code_change(_OldVsn, StateName, MState, _Extra) ->
    {ok, StateName, MState}.

terminate(Status, StateName, _) ->
    Msg = io_lib:format("status=~p, state=~p", [Status, StateName]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% State machine transitions
%% ============================================================================

%% @doc State meaning: services are unloaded, but maintanance is not needed
-spec stopped({call, pid()} | cast, {atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
stopped({call, From}, get_current, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
stopped(cast, {enter, stopped}, MState) ->
    {next_state, stopped, MState};
stopped(cast, {enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
stopped(cast, {enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
stopped(cast, {enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
stopped(cast, {enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState}.

%% @doc State meaning: services are loading now according the node roles
-spec loading({call, pid()} | cast, {atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
loading({call, From}, get_current, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
loading(cast, {enter, idle}, MState) ->
    {next_state, idle, MState};
loading(cast, {enter, loading}, MState) ->
    {next_state, loading, MState};
loading(cast, {enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState};
loading(cast, {enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
loading(cast, {enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
loading(cast, {enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState}.

%% @doc State meaning: the node requires some intervention from outside
-spec maint({call, pid()} | cast, {atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
maint({call, From}, get_current, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
maint(cast, {enter, maint}, MState) ->
    {next_state, maint, MState};
maint(cast, {enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState};
maint(cast, {enter, idle}, MState) ->
    wm_event:announce(new_node_state, {node(), idle}),
    {next_state, idle, MState};
maint(cast, {enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
maint(cast, {enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
maint(cast, {enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState}.

%% @doc State meaning: services are loaded, but the node should not be used now
-spec offline({call, pid()} | cast, {atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
offline({call, From}, get_current, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
offline(cast, {enter, offline}, MState) ->
    {next_state, offline, MState};
offline(cast, {enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
offline(cast, {enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
offline(cast, {enter, idle}, MState) ->
    wm_event:announce(new_node_state, {node(), idle}),
    {next_state, idle, MState};
offline(cast, {enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
offline(cast, {enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState}.

%% @doc State meaning: node is ready to run jobs
-spec idle({call, pid()} | cast, {atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
idle({call, From}, get_current, MState) ->
    {keep_state, MState, [{reply, From, ?FUNCTION_NAME}]};
idle(cast, {enter, idle}, MState) ->
    {next_state, idle, MState};
idle(cast, {enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
idle(cast, {enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState};
idle(cast, {enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
idle(cast, {enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
idle(cast, {enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState}.
