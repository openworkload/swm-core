-module(wm_cloud).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([get_flavors/1]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_general.hrl").

-record(mstate, {refs_in_process = #{} :: #{}, timer = undefined :: reference()}).

-define(UPDATE_INTERVAL, timer:minutes(60)).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Get flavor (template) nodes kept in local config
-spec get_flavors(remote_id()) -> ok.
get_flavors(RemoteId) ->
    {ok, _Ref} = gen_server:call(?MODULE, {get_flavors, RemoteId}).

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
    ?LOG_INFO("Remote nodes flavors collector started"),
    MState = parse_args(Args, #mstate{}),
    wm_works:call_asap(?MODULE, turn_timer_on),
    {ok, MState#mstate{refs_in_process = #{}}}.

handle_call(turn_timer_on, _From, MState) ->
    MState2 =
        case wm_self:has_role("cluster") of
            true ->
                ?LOG_INFO("Turn periodic cloud information update timer ON"),
                MState#mstate{timer = wm_utils:wake_up_after(1000, update)};
            false ->
                MState
        end,
    {reply, ok, MState2};
handle_call({get_flavors, RemoteId}, _From, MState) ->
    FlavorNodes = select_template_nodes(RemoteId),
    ?LOG_DEBUG("{get_flavors, ~p}: selected ~p flavor nodes", [RemoteId, length(FlavorNodes)]),
    {reply, FlavorNodes, MState}.

handle_cast({list_flavors, Ref, FlavorNodes}, MState = #mstate{refs_in_process = Refs}) ->
    case maps:get(Ref, Refs, undefined) of
        undefined ->
            ?LOG_WARN("Got orphaned list_flavors message with reference ~p", [Ref]),
            {noreply, MState};
        RemoteId ->
            handle_retrieved_flavors(FlavorNodes, RemoteId),
            {noreply, MState#mstate{refs_in_process = maps:remove(Ref, Refs)}}
    end;
handle_cast({Ref, 'EXIT', Msg}, MState = #mstate{refs_in_process = Refs}) ->
    case maps:get(Ref, Refs, undefined) of
        undefined ->
            ?LOG_WARN("Got orphaned list_flavors error with reference ~p: ~p", [Ref, Msg]),
            {noreply, MState};
        RemoteId ->
            ?LOG_WARN("Could not list flavors for remote ~p: ~p", [RemoteId, Msg]),
            {noreply, MState#mstate{refs_in_process = maps:remove(Ref, Refs)}}
    end.

handle_info(update, MState = #mstate{refs_in_process = Refs, timer = OldTRef}) ->
    catch timer:cancel(OldTRef),
    NewRefs =
        case wm_conf:select([remote], all) of
            Remotes when is_list(Remotes) ->
                ?LOG_DEBUG("Update cloud information for ~p remote site(s)", [Remotes]),
                lists:foldl(fun(Remote, Accum) ->
                               RemoteId = wm_entity:get_attr(id, Remote),
                               {ok, Creds} = wm_conf:select(credential, {remote_id, RemoteId}),
                               {ok, Ref} = wm_gate:list_flavors(?MODULE, Remote, Creds),
                               Accum#{Ref => RemoteId}
                            end,
                            Refs,
                            Remotes);
            {error, not_found} ->
                Refs
        end,
    {noreply, MState#mstate{refs_in_process = NewRefs, timer = wm_utils:wake_up_after(?UPDATE_INTERVAL, update)}}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState = #mstate{}) ->
    MState;
parse_args([{_, _} | T], MState = #mstate{}) ->
    parse_args(T, MState).

-spec handle_retrieved_flavors([#node{}], remote_id()) -> atom().
handle_retrieved_flavors(FlavorNodes, RemoteId) ->
    TemplateNodes = select_template_nodes(RemoteId),
    case wm_conf:select(remote, {id, RemoteId}) of
        {ok, _} ->
            {PreserveNodes, DeleteNodes} =
                lists:foldl(fun(FlavorNode, {PreserveNodes, DeleteNodes}) ->
                               Name = wm_entity:get_attr(name, FlavorNode),
                               case lookup_node(Name, DeleteNodes) of
                                   {ok, FoundTemplateNode} ->
                                       Resources = wm_entity:get_attr(resources, FlavorNode),
                                       Prices = wm_entity:get_attr(prices, FlavorNode),
                                       UpdNode =
                                           wm_entity:set_attr([{resources, Resources}, {prices, Prices}],
                                                              FoundTemplateNode),
                                       {[UpdNode | PreserveNodes], DeleteNodes -- [FoundTemplateNode]};
                                   {error, not_found} ->
                                       {[FlavorNode | PreserveNodes], DeleteNodes}
                               end
                            end,
                            {[], TemplateNodes},
                            FlavorNodes),
            [ok = wm_conf:delete(Node) || Node <- DeleteNodes],
            true = wm_conf:update(PreserveNodes) == length(PreserveNodes);
        {error, not_found} ->
            [ok = wm_conf:delete(Node) || Node <- TemplateNodes]
    end.

-spec lookup_node(nonempty_string(), [#node{}]) -> {ok, #node{}} | {error, not_found}.
lookup_node(_, []) ->
    {error, not_found};
lookup_node(Name, [X = #node{name = Name} | _]) ->
    {ok, X};
lookup_node(Name, [_ | Xs]) ->
    lookup_node(Name, Xs).

-spec select_template_nodes(remote_id()) -> [#node{}].
select_template_nodes(RemoteId) ->
    P = fun(X) -> wm_entity:get_attr(remote_id, X) =:= RemoteId andalso wm_entity:get_attr(is_template, X) =:= true end,
    case wm_conf:select(node, P) of
        {ok, Xs} ->
            Xs;
        {error, not_found} ->
            []
    end.

%% ============================================================================
%% Tests
%% ============================================================================

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

lookup_node_test() ->
    A = wm_entity:set_attr({name, "a"}, wm_entity:new(node)),
    B = wm_entity:set_attr({name, "b"}, wm_entity:new(node)),
    C = wm_entity:set_attr({name, "c"}, wm_entity:new(node)),

    ?assertEqual({ok, A}, lookup_node("a", [C, A, B])),
    ?assertEqual({error, not_found}, lookup_node("z", [C, A, B])),
    ok.

-endif.
