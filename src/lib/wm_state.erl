-module(wm_state).

-behaviour(gen_fsm).

-export([start_link/1]).
-export([enter/1, breakdown/1, get_current/0]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, code_change/4, terminate/3]).
-export([stopped/2, loading/2, maint/2, offline/2, idle/2]).

-include("wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(_Args) ->
    gen_fsm:start_link({local, ?MODULE}, ?MODULE, undefined, []).

-spec enter(atom()) -> ok.
enter(State) ->
    wm_conf:set_node_state(alloc, State, node()),
    gen_fsm:send_event(?MODULE, {enter, State}).

-spec breakdown(atom()) -> ok.
breakdown(State) ->
    gen_fsm:send_event(?MODULE, {breakdown, State}).

%% @doc Get current node state
-spec get_current() -> atom().
get_current() ->
    gen_fsm:sync_send_all_state_event(?MODULE, get_current).

%% ============================================================================
%% Callbacks
%% ============================================================================

-spec init(term()) ->
              {ok, atom(), term()} |
              {ok, atom(), term(), hibernate | infinity | non_neg_integer()} |
              {stop, term()} |
              ignore.
-spec handle_event(term(), atom(), term()) ->
                      {next_state, atom(), term()} |
                      {next_state, atom(), term(), hibernate | infinity | non_neg_integer()} |
                      {stop, term(), term()} |
                      {stop, term(), term(), term()}.
-spec handle_sync_event(term(), atom(), atom(), term()) ->
                           {next_state, atom(), term()} |
                           {next_state, atom(), term(), hibernate | infinity | non_neg_integer()} |
                           {reply, term(), atom(), term()} |
                           {reply, term(), atom(), term(), hibernate | infinity | non_neg_integer()} |
                           {stop, term(), term()} |
                           {stop, term(), term(), term()}.
-spec handle_info(term(), atom(), term()) ->
                     {next_state, atom(), term()} |
                     {next_state, atom(), term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec code_change(term(), atom(), term(), term()) -> {ok, term()}.
-spec terminate(term(), atom(), term()) -> ok.
init(_Args) ->
    ?LOG_DEBUG("Node state module has been started"),
    {ok, stopped, #mstate{}}.

handle_sync_event(get_current, From, State, MState) ->
    ?LOG_DEBUG("Asked for current state (~p) by ~p", [State, From]),
    {reply, State, State, MState}.

handle_event(_Event, State, MState) ->
    {next_state, State, MState}.

handle_info(_Info, StateName, MState) ->
    {next_state, StateName, MState}.

code_change(_OldVsn, StateName, MState, _Extra) ->
    {ok, StateName, MState}.

terminate(Status, StateName, _) ->
    Msg = io_lib:format("status=~p, state=~p", [Status, StateName]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @doc State meaning: services are unloaded, but maintanance is not needed
-spec stopped({atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
stopped({enter, stopped}, MState) ->
    {next_state, stopped, MState};
stopped({enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
stopped({enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
stopped({enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
stopped({enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState}.

%% @doc State meaning: services are loading now according the node roles
-spec loading({atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
loading({enter, idle}, MState) ->
    {next_state, idle, MState};
loading({enter, loading}, MState) ->
    {next_state, loading, MState};
loading({enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState};
loading({enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
loading({enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
loading({enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState}.

%% @doc State meaning: the node requires some intervention from outside
-spec maint({atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
maint({enter, maint}, MState) ->
    {next_state, maint, MState};
maint({enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState};
maint({enter, idle}, MState) ->
    wm_event:announce(new_node_state, {node(), idle}),
    {next_state, idle, MState};
maint({enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
maint({enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
maint({enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState}.

%% @doc State meaning: services are loaded, but the node should not be used now
-spec offline({atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
offline({enter, offline}, MState) ->
    {next_state, offline, MState};
offline({enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
offline({enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
offline({enter, idle}, MState) ->
    wm_event:announce(new_node_state, {node(), idle}),
    {next_state, idle, MState};
offline({enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
offline({enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState}.

%% @doc State meaning: node is ready to run jobs
-spec idle({atom(), atom()}, #mstate{}) -> {atom(), atom(), #mstate{}}.
idle({enter, idle}, MState) ->
    {next_state, idle, MState};
idle({enter, loading}, MState) ->
    wm_event:announce(new_node_state, {node(), loading}),
    {next_state, loading, MState};
idle({enter, offline}, MState) ->
    wm_event:announce(new_node_state, {node(), offline}),
    {next_state, offline, MState};
idle({enter, maint}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState};
idle({enter, stopped}, MState) ->
    wm_event:announce(new_node_state, {node(), stopped}),
    {next_state, stopped, MState};
idle({enter, breakdown}, MState) ->
    wm_event:announce(new_node_state, {node(), maint}),
    {next_state, maint, MState}.
