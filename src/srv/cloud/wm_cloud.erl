-module(wm_cloud).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

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
    {reply, ok, MState2}.

handle_cast({list_images, Ref, Images}, MState = #mstate{refs_in_process = Refs}) ->
    case maps:get(Ref, Refs, undefined) of
        undefined ->
            ?LOG_WARN("Got orphaned list_images message with reference ~p", [Ref]),
            {noreply, MState};
        RemoteId ->
            handle_retrieved_images(Images, RemoteId),
            {noreply, MState#mstate{refs_in_process = maps:remove(Ref, Refs)}}
    end;
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
            ?LOG_WARN("Could not list flavors for remote ~p", [RemoteId]),
            {noreply, MState#mstate{refs_in_process = maps:remove(Ref, Refs)}}
    end;
handle_cast({error, Ref, Error}, MState = #mstate{refs_in_process = Refs}) ->
    case maps:get(Ref, Refs, undefined) of
        undefined ->
            ?LOG_WARN("Orphaned gate error with reference ~p: ~p", [Ref, Error]),
            {noreply, MState};
        RemoteId ->
            ?LOG_WARN("Gate error for remote ~p: ~p", [RemoteId, Error]),
            {noreply, MState#mstate{refs_in_process = maps:remove(Ref, Refs)}}
    end.

handle_info(update, MState = #mstate{refs_in_process = Refs, timer = OldTRef}) ->
    catch timer:cancel(OldTRef),
    NewRefs =
        case wm_conf:select([remote], all) of
            Remotes when is_list(Remotes) ->
                ?LOG_DEBUG("Update cloud information for ~p remote site(s)", [Remotes]),
                lists:foldl(fun(Remote, Accum) ->
                               RemoteId = wm_entity:get(id, Remote),
                               {ok, Creds} = wm_conf:select(credential, {remote_id, RemoteId}),
                               {ok, RefFlavors} = wm_gate:list_flavors(?MODULE, Remote, Creds),
                               {ok, RefImages} = wm_gate:list_images(?MODULE, Remote, Creds),
                               ?LOG_DEBUG("Flavors and images requested, refs: ~p and ~p", [RefFlavors, RefImages]),
                               Accum#{RefFlavors => RemoteId, RefImages => RemoteId}
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

-spec handle_retrieved_images([#image{}], remote_id()) -> atom().
handle_retrieved_images([], RemoteId) ->
    ?LOG_DEBUG("Retrieved 0 images for remote ~p => clean known images for this remote", [RemoteId]),
    case wm_conf:select(image, {remote_id, RemoteId}) of
        {error, not_found} ->
            ok;
        {ok, OldImages} ->
            ?LOG_DEBUG("Remove ~p outdated images for remote ~p", [length(OldImages), RemoteId]),
            [ok = wm_conf:delete(Image) || Image <- OldImages]
    end;
handle_retrieved_images(NewImages, RemoteId) ->
    ?LOG_DEBUG("Handle retrieved ~p images for remote ~p", [length(NewImages), RemoteId]),
    case wm_conf:select(image, {remote_id, RemoteId}) of
        {error, not_found} ->
            ok;
        {ok, OldImages} when is_list(OldImages) ->
            ?LOG_DEBUG("Found ~p old images for remote ~p", [length(OldImages), RemoteId]),
            [ok = wm_conf:delete(Image) || Image <- OldImages];
        {ok, OldImage} ->
            ?LOG_DEBUG("Found old image for remote ~p", [RemoteId]),
            ok = wm_conf:delete(OldImage)
    end,
    case wm_conf:select(remote, {id, RemoteId}) of
        {ok, Remote} ->
            true = wm_conf:update(NewImages) == length(NewImages),
            DefaultImage = lists:nth(1, NewImages),
            DefaultImageId = wm_entity:get(id, DefaultImage),
            case wm_entity:get(default_image_id, Remote) of
                DefaultImageId ->
                    ok;
                undefined ->
                    ?LOG_INFO("Default image ID is updated for remote ~p: ~p", [RemoteId, DefaultImageId]),
                    1 =
                        wm_conf:update(
                            wm_entity:set({default_image_id, DefaultImageId}, Remote));
                _ ->
                    ok
            end;
        {error, not_found} ->
            ?LOG_DEBUG("New images will not be added for remote ~p, because it is not configured", [RemoteId])
    end.

-spec handle_retrieved_flavors([#node{}], remote_id()) -> atom().
handle_retrieved_flavors(FlavorNodes, RemoteId) ->
    ?LOG_DEBUG("Handle retrieved ~p flavors for remote ~p", [length(FlavorNodes), RemoteId]),
    TemplateNodes = select_template_nodes(RemoteId),
    case wm_conf:select(remote, {id, RemoteId}) of
        {ok, Remote} ->
            {PreserveNodes, DeleteNodes} =
                lists:foldl(fun(FlavorNode, {PreserveNodes, DeleteNodes}) ->
                               Name = wm_entity:get(name, FlavorNode),
                               case lookup_node(Name, DeleteNodes) of
                                   {ok, FoundTemplateNode} ->
                                       Resources = wm_entity:get(resources, FlavorNode),
                                       Prices = wm_entity:get(prices, FlavorNode),
                                       UpdNode =
                                           wm_entity:set([{resources, Resources}, {prices, Prices}], FoundTemplateNode),
                                       {[UpdNode | PreserveNodes], DeleteNodes -- [FoundTemplateNode]};
                                   {error, not_found} ->
                                       {[FlavorNode | PreserveNodes], DeleteNodes}
                               end
                            end,
                            {[], TemplateNodes},
                            FlavorNodes),
            [ok = wm_conf:delete(Node) || Node <- DeleteNodes],

            case length(PreserveNodes) of
                0 ->
                    ok;
                Length ->
                    AddFlavorRes =
                        fun(Node) ->
                           Resources1 = wm_entity:get(resources, Node),
                           Resources2 =
                               Resources1
                               ++ case lists:keysearch("flavor", 2, Resources1) of
                                      false ->
                                          Name = wm_entity:get(name, Node),
                                          Parameters = [{name, "flavor"}, {properties, [{value, Name}]}],
                                          [wm_entity:set(Parameters, wm_entity:new(resource))];
                                      _ ->  % flavor resource already presents
                                          []
                                  end,
                           wm_entity:set([{resources, Resources2}], Node)
                        end,
                    NodesToUpdate = lists:map(AddFlavorRes, PreserveNodes),
                    true = wm_conf:update(NodesToUpdate) == Length,
                    RemoteName = wm_entity:get(name, Remote),
                    add_nodes_to_new_partition(NodesToUpdate, RemoteName),
                    Default = lists:nth(1, NodesToUpdate),
                    DefaultId = wm_entity:get(id, Default),
                    case wm_entity:get(default_flavor_id, Remote) of
                        DefaultId ->
                            ok;
                        undefined ->
                            ?LOG_INFO("Default flavor node ID is updated for remote ~p: ~p", [RemoteId, DefaultId]),
                            1 =
                                wm_conf:update(
                                    wm_entity:set({default_flavor_id, DefaultId}, Remote));
                        _ ->
                            ok
                    end
            end;
        {error, not_found} ->
            [ok = wm_conf:delete(Node) || Node <- TemplateNodes]
    end.

-spec merge_partition_node_ids([node_id()], [#node{}]) -> [node_id()].
merge_partition_node_ids(OldNodeIds, NewNodes) ->
    OldNodes = wm_conf:select(node, OldNodeIds),
    OldNameIdPairs = [{Node#node.name, Node#node.id} || Node <- OldNodes],
    NewNameIdPairs = [{Node#node.name, Node#node.id} || Node <- NewNodes],
    FinalNameIdPairs = lists:ukeymerge(1, lists:ukeysort(1, OldNameIdPairs), lists:ukeysort(1, NewNameIdPairs)),
    [Id || {_, Id} <- FinalNameIdPairs].

-spec add_nodes_to_new_partition([#node{}], string()) -> integer().
add_nodes_to_new_partition(Nodes, PartName) ->
    Cluster1 = wm_topology:get_subdiv(cluster),
    ClusterId = wm_entity:get(id, Cluster1),
    OldPartIds = wm_entity:get(partitions, Cluster1),
    ExistingParts = wm_conf:select(partition, OldPartIds),
    PartId =
        case lists:any(fun(P) -> wm_entity:get(name, P) == PartName end, ExistingParts) of
            true ->
                ?LOG_DEBUG("Partition with name ~p exists in cluster (good)", [PartName]),
                {ok, Part1} = wm_conf:select(partition, {name, PartName}),
                OldNodeIds = wm_entity:get(nodes, Part1),
                NewNodeIds = merge_partition_node_ids(OldNodeIds, Nodes),
                Part2 = wm_entity:set([{nodes, NewNodeIds}], Part1),
                1 = wm_conf:update(Part2),
                wm_entity:get(id, Part2);
            false ->
                NewPartId = wm_utils:uuid(v4),
                NodeIds = [Node#node.id || Node <- Nodes],
                NewPart =
                    wm_entity:set([{id, NewPartId},
                                   {name, PartName},
                                   {nodes, NodeIds},
                                   {state, up},
                                   {subdivision, cluster},
                                   {subdivision_id, ClusterId},
                                   {comment, "Remote site partition"}],
                                  wm_entity:new(partition)),
                Cluster2 = wm_entity:set({partitions, [NewPartId | OldPartIds]}, Cluster1),
                1 = wm_conf:update(NewPart),
                1 = wm_conf:update(Cluster2),
                NewPartId
        end,
    UpdatedNodes =
        lists:map(fun(Node) -> wm_entity:set([{subdivision, partition}, {subdivision_id, PartId}], Node) end, Nodes),
    NodesNumber = length(Nodes),
    NodesNumber = wm_conf:update(UpdatedNodes).

-spec lookup_node(nonempty_string(), [#node{}]) -> {ok, #node{}} | {error, not_found}.
lookup_node(_, []) ->
    {error, not_found};
lookup_node(Name, [X = #node{name = Name} | _]) ->
    {ok, X};
lookup_node(Name, [_ | Xs]) ->
    lookup_node(Name, Xs).

-spec select_template_nodes(remote_id()) -> [#node{}].
select_template_nodes(RemoteId) ->
    P = fun(X) -> wm_entity:get(remote_id, X) =:= RemoteId andalso wm_entity:get(is_template, X) =:= true end,
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
    A = wm_entity:set({name, "a"}, wm_entity:new(node)),
    B = wm_entity:set({name, "b"}, wm_entity:new(node)),
    C = wm_entity:set({name, "c"}, wm_entity:new(node)),

    ?assertEqual({ok, A}, lookup_node("a", [C, A, B])),
    ?assertEqual({error, not_found}, lookup_node("z", [C, A, B])),
    ok.

-endif.
