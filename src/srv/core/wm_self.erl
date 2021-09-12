-module(wm_self).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([has_role/1, get_node_id/0, get_node/0, get_sname/0, get_host/0, update/0]).
-export([is_local_node/1]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").

-record(mstate, {sname = "" :: string(), host = "" :: string(), node_id = "" :: string()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Returns true if the role is assigned to the current node
-spec has_role(string()) -> true | false.
has_role(RoleName) ->
    gen_server:call(?MODULE, {has_role, RoleName}).

%% @doc Returns current node entity id
-spec get_node_id() -> string().
get_node_id() ->
    gen_server:call(?MODULE, get_node_id).

%% @doc Set current node entity id
-spec get_node() -> {ok, #node{}} | {error, not_found}.
get_node() ->
    gen_server:call(?MODULE, get_node).

%% @doc Get current node short name
-spec get_sname() -> {ok, string()} | {error, not_found}.
get_sname() ->
    gen_server:call(?MODULE, get_sname).

%% @doc Get current node host name
-spec get_host() -> {ok, string()} | {error, not_found}.
get_host() ->
    gen_server:call(?MODULE, get_host).

%% @doc Update internal state
-spec update() -> ok.
update() ->
    gen_server:call(?MODULE, update).

%% @doc Verify is node entity points to the node where the code is running now
-spec is_local_node(#node{}) -> true | false.
is_local_node(Node) ->
    wm_entity:get_attr(id, Node) == get_node_id().

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
%% @hidden
init(Args) ->
    ?LOG_INFO("Load self node management service"),
    process_flag(trap_exit, true),
    Hostname = wm_utils:get_my_hostname(),
    MState1 = parse_args(Args, #mstate{host = Hostname}),
    MState2 = update_node_id(MState1),
    {ok, MState2}.

handle_call(update, _From, MState = #mstate{}) ->
    {reply, ok, update_node_id(MState)};
handle_call(get_host, _From, MState = #mstate{host = Host}) ->
    case Host of
        "" ->
            {reply, {error, not_found}, MState};
        _ ->
            {reply, {ok, Host}, MState}
    end;
handle_call(get_sname, _From, MState = #mstate{sname = SName}) ->
    case SName of
        "" ->
            {reply, {error, not_found}, MState};
        _ ->
            {reply, {ok, SName}, MState}
    end;
handle_call({has_role, RoleName}, _From, MState = #mstate{}) ->
    Result =
        case do_get_node(MState) of
            {error, _} ->
                false;
            {ok, Node} ->
                wm_utils:has_role(RoleName, Node)
        end,
    {reply, Result, MState};
handle_call(get_node, _From, MState = #mstate{node_id = ID}) ->
    {reply, wm_conf:select(node, {id, ID}), MState};
handle_call(get_node_id, _From, MState = #mstate{node_id = ID}) ->
    {reply, ID, MState};
handle_call(Msg, From, MState) ->
    ?LOG_ERROR("Unknown call: ~p from ~p", [Msg, From]),
    {reply, ok, MState}.

handle_cast(Msg, MState) ->
    ?LOG_ERROR("Unknown cast: ~p", [Msg]),
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
parse_args([{sname, Name} | T], MState) ->
    parse_args(T, MState#mstate{sname = Name});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

update_node_id(MState) ->
    ?LOG_DEBUG("Update node id"),
    case do_get_node(MState) of
        {ok, Node} ->
            ID = wm_entity:get_attr(id, Node),
            MState#mstate{node_id = ID};
        _ ->
            MState
    end.

do_get_node(MState) ->
    case wm_conf:select_node(MState#mstate.sname) of
        {error, Error} ->
            ?LOG_DEBUG("Could not get node: ~p", [Error]),
            wm_state:enter(maint),
            {error, Error};
        {ok, Node} ->
            {ok, Node}
    end.
