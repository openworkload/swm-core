-module(wm_topology).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([schedule_latency_update/1, get_children/0, get_children_nodes/1, get_neighbour_nodes/0,
         get_my_neighbour_addresses/0, get_latency/2, get_min_latency_to/1, get_tree/1, get_subdiv/1, get_subdiv/0,
         on_path/2, get_tree_nodes/1, reload/0, is_my_direct_child/1]).

-include("wm_log.hrl").
-include("wm_entity.hrl").

-record(mstate,
        {rh :: map(),                 %% Resource Hierarchy
         rh_index = #{} :: map(),     %% NodeId => path from RH root (root-first)
         rh_children = #{} :: map(),  %% MgrNodeId => [#node{}] (children_only)
         rh_neighbours = #{} :: map(),%% NodeId => [#node{}] (neighbours_only)
         nl :: binary(),              %% Neighbour List (binary vector)
         ct :: binary(),              %% Connection Topology (binary matrix)
         ct_map :: map(),             %% NodeId --> Position in CT
         mrole :: atom(),             %% Management role name
         sname :: string(),           %% Short node name
         constructing = false :: boolean()}).  %% Async RH rebuild in flight

-define(DEFAULT_TRIALS, 8).
-define(BINARY_ID_BITS, 64).
-define(BINARY_WEIGHT_BITS, 64).
-define(BITS_IN_BYTE, 8).
-define(MILLISECONDS_IN_1_SECOND, 1000000).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Returns true if node is direct child of self node
-spec is_my_direct_child(string()) -> true | false.
is_my_direct_child(NodeId) ->
    wm_utils:protected_call(?MODULE, {is_my_direct_child, NodeId}, false).

%% @doc Initiate latency update to the specified node
-spec schedule_latency_update(tuple()) -> ok.
schedule_latency_update(Node) ->
    gen_server:cast(?MODULE, {update_latency, Node}).

%% @doc Get all neightbour records
-spec get_neighbour_nodes() -> [{atom(), number()}].
get_neighbour_nodes() ->
    wm_utils:protected_call(?MODULE, get_neighbour_nodes, []).

%% @doc Get all children records of my node
-spec get_children() -> [{atom(), number()}].
get_children() ->
    wm_utils:protected_call(?MODULE, get_children, []).

%% @doc Get all children records of the specified division
-spec get_children_nodes(node_id()) -> [#node{}].
get_children_nodes(NodeId) ->
    wm_utils:protected_call(?MODULE, {get_children_nodes, NodeId}, []).

%% @doc Get neightbour nodenames
-spec get_my_neighbour_addresses() -> list().
get_my_neighbour_addresses() ->
    wm_utils:protected_call(?MODULE, get_my_neighbour_addresses, []).

%% @doc Get latency that are calculated between two nodes
-spec get_latency(atom(), atom()) -> pos_integer().
get_latency(SrcNode, DstNode) ->
    wm_utils:protected_call(?MODULE, {get_latency, SrcNode, DstNode}, 0).

%% @doc Get minimum latency value from local node to nodes specified by names
-spec get_min_latency_to([atom()]) -> {atom(), pos_integer()}.
get_min_latency_to(NodeNames) ->
    wm_utils:protected_call(?MODULE, {get_min_latency_to, NodeNames}, 0).

%% @doc Get hierarchy as list
-spec get_tree(atom()) -> [term()].
get_tree(Type) ->
    wm_utils:protected_call(?MODULE, {get_tree, Type}, #{}).

%% @doc Get direct (lowest) subdivision
-spec get_subdiv() -> term() | not_found.
get_subdiv() ->
    wm_utils:protected_call(?MODULE, {get_subdiv, direct}, not_found).

%% @doc Get subdivision of the specified type
-spec get_subdiv(atom()) -> [term()].
get_subdiv(Type) ->
    wm_utils:protected_call(?MODULE, {get_subdiv, Type}, not_found).

%% @doc Get next node id which node stends on path to specified node address
-spec on_path(string(), string()) -> {ok, string()} | not_found.
on_path(FromNodeId, ToNodeId) ->
    wm_utils:protected_call(?MODULE, {get_path, FromNodeId, ToNodeId}, []).

%% @doc Get node entities for each
-spec get_tree_nodes(boolean()) -> [tuple()].
get_tree_nodes(WithTemplates) ->
    wm_utils:protected_call(?MODULE, {get_tree_nodes, WithTemplates}, []).

%% @doc Reload topology data structures asynchronously.
%% Heavy RH rebuild must not block get_subdiv/other calls on this gen_server
%% (otherwise job submit times out while cancel/cloud reloads run).
-spec reload() -> ok.
reload() ->
    gen_server:cast(?MODULE, construct_data_types).

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
    ?LOG_INFO("Load topology module"),
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    wm_works:call_asap(?MODULE, construct_data_types),
    {ok, MState}.

handle_call({get_path, FromNodeId, ToNodeId}, _, #mstate{rh_index = Index} = MState) ->
    NextNodeId =
        case find_rh_path_from_index(FromNodeId, ToNodeId, Index) of
            [] ->
                not_found;
            List when is_list(List) ->
                {ok, hd(List)}
        end,
    {reply, NextNodeId, MState};
handle_call({is_my_direct_child, NodeId}, _, #mstate{rh_children = Children} = MState) ->
    MyNodeId = wm_self:get_node_id(),
    MyChildren = maps:get(MyNodeId, Children, []),
    Result = lists:any(fun(#node{id = Id}) -> Id =:= NodeId end, MyChildren),
    {reply, Result, MState};
handle_call({get_tree_nodes, WithTemplates}, _, #mstate{} = MState) ->
    {reply, do_get_tree_nodes(WithTemplates, MState), MState};
handle_call({get_subdiv, Name}, _, #mstate{} = MState) ->
    {reply, do_get_my_subdiv(Name, MState), MState};
handle_call({get_tree, list}, _, #mstate{rh = RH} = MState) ->
    {reply, wm_utils:map_to_list(RH), MState};
handle_call({get_tree, rh}, _, #mstate{rh = RH} = MState) ->
    {reply, RH, MState};
handle_call({get_tree, static}, _, #mstate{rh = RH} = MState) ->
    F = fun({EntityType, EntityId}) ->
           case wm_conf:select(EntityType, {id, EntityId}) of
               {error, Error} ->
                   {EntityType, Error};
               {ok, Entity} ->
                   {EntityType, wm_entity:get(name, Entity)}
           end
        end,
    Tree = wm_utils:update_map(RH, F, #{}),
    {reply, Tree, MState};
handle_call({get_min_latency_to, NodeNames}, _, #mstate{} = MState) ->
    {ok, SelfNode} = wm_self:get_node(),
    {reply, do_get_min_latency(SelfNode, NodeNames, {}, MState), MState};
handle_call({get_latency, SrcNode, DstNode}, _, #mstate{} = MState) ->
    {reply, do_get_latency(SrcNode, DstNode, MState), MState};
handle_call(get_my_neighbour_addresses, _, #mstate{rh_children = Ch, rh_neighbours = Nb} = MState) ->
    MyId = wm_self:get_node_id(),
    Nodes = maps:get(MyId, Ch, []) ++ maps:get(MyId, Nb, []),
    Addresses = [wm_utils:get_address(Node) || Node <- Nodes],
    {reply, Addresses, MState};
handle_call(get_my_neighbour_nodes, _, #mstate{rh_children = Ch, rh_neighbours = Nb} = MState) ->
    MyId = wm_self:get_node_id(),
    {reply, maps:get(MyId, Ch, []) ++ maps:get(MyId, Nb, []), MState};
handle_call(get_children, _, #mstate{} = MState) ->
    {reply, get_my_children([cluster, partition, node], MState), MState};
handle_call({get_children_nodes, NodeId}, _, #mstate{rh_children = Ch, rh = RH} = MState) ->
    Nodes =
        case maps:find(NodeId, Ch) of
            {ok, Cached} ->
                Cached;
            error ->
                find_close_nodes(NodeId, RH, children_only)
        end,
    {reply, Nodes, MState};
handle_call(construct_data_types, _, #mstate{} = MState) ->
    %% Sync path (startup via wm_works); callers that need RH immediately.
    {reply, ok, do_construct_inplace(MState)};
handle_call(_Msg, _, #mstate{} = MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast(construct_data_types, #mstate{constructing = true} = MState) ->
    ?LOG_DEBUG("Topology reconstruct already in progress; coalesce"),
    {noreply, MState};
handle_cast(construct_data_types, #mstate{} = MState) ->
    Self = self(),
    Snapshot = MState,
    spawn_link(fun() ->
                  try
                      Built = do_construct_inplace(Snapshot),
                      gen_server:cast(Self, {construct_done, Built})
                  catch
                      Class:Error:Stack ->
                          ?LOG_ERROR("Topology reconstruct failed: ~p:~p~n~p", [Class, Error, Stack]),
                          gen_server:cast(Self, construct_failed)
                  end
               end),
    {noreply, MState#mstate{constructing = true}};
handle_cast({construct_done, Built}, #mstate{} = MState) ->
    ?LOG_DEBUG("Async topology reconstruct applied (rh_nodes=~p)", [maps:size(Built#mstate.rh_index)]),
    {noreply,
     MState#mstate{rh = Built#mstate.rh,
                   rh_index = Built#mstate.rh_index,
                   rh_children = Built#mstate.rh_children,
                   rh_neighbours = Built#mstate.rh_neighbours,
                   nl = Built#mstate.nl,
                   ct = Built#mstate.ct,
                   ct_map = Built#mstate.ct_map,
                   mrole = Built#mstate.mrole,
                   constructing = false}};
handle_cast(construct_failed, #mstate{} = MState) ->
    {noreply, MState#mstate{constructing = false}};
handle_cast({update_latency, Node}, #mstate{} = MState) ->
    do_update_latency(Node, MState),
    {noreply, MState};
handle_cast(_Msg, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(_Info, #mstate{} = MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, #mstate{} = MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @doc Full RH/NL/CT rebuild. Safe to run off the gen_server process on a snapshot.
-spec do_construct_inplace(#mstate{}) -> #mstate{}.
do_construct_inplace(#mstate{} = MState) ->
    ?LOG_INFO("Construct topology"),
    MState1 = set_management_role(MState),
    MState2 = do_make_rh_main(MState1),
    MState3 = do_make_nl(MState2#mstate.mrole, MState2),
    MState4 = init_ct(MState3),
    ?LOG_DEBUG("Topology ready: role=~p rh_nodes=~p children_cached=~p",
               [MState4#mstate.mrole, maps:size(MState4#mstate.rh_index), maps:size(MState4#mstate.rh_children)]),
    wm_event:announce(topology_constructed),
    MState4#mstate{constructing = false}.

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{sname, Name} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{sname = Name});
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, MState).

-spec set_management_role(#mstate{}) -> #mstate{}.
set_management_role(#mstate{} = MState) ->
    ?LOG_DEBUG("Set management role"),
    {ok, NodeName} = wm_self:get_sname(),
    {ok, Host} = wm_self:get_host(),
    Name =
        case wm_utils:get_my_vnode_name(short, string, NodeName, Host) of
            {ok, X} ->
                X;
            {error, _} ->
                [];
            _Y ->
                ?LOG_ERROR("Can not get my node name: ~p", [_Y])
        end,
    case wm_conf:select_node(Name) of
        {error, _E} ->
            ?LOG_ERROR("Could not get my node information: ~p", [_E]),
            MState#mstate{mrole = none};
        {ok, Node} ->
            RoleIDs = wm_entity:get(roles, Node),
            Roles = wm_conf:select(role, RoleIDs),
            RoleNames = [wm_entity:get(name, Role) || Role <- Roles],
            ?LOG_DEBUG("Roles: ~p", [RoleNames]),
            ManagementRole = get_management_role(RoleNames, none),
            ?LOG_DEBUG("Management role is set to ~p", [ManagementRole]),
            MState#mstate{mrole = ManagementRole}
    end.

-spec get_management_role([string()], atom()) -> atom().
get_management_role([], Role) ->
    Role;
get_management_role(["grid" | _], _) ->
    grid;
get_management_role(["cluster" | T], _) ->
    get_management_role(T, cluster);
get_management_role(["partition" | T], cluster) ->
    get_management_role(T, cluster);
get_management_role(["partition" | T], _) ->
    get_management_role(T, partition);
get_management_role(["compute" | T], partition) ->
    get_management_role(T, partition);
get_management_role(["compute" | T], cluster) ->
    get_management_role(T, cluster);
get_management_role(["compute" | T], _) ->
    get_management_role(T, compute);
get_management_role([_ | T], Role) ->
    get_management_role(T, Role).

-spec do_make_rh_main(#mstate{}) -> #mstate{}.
do_make_rh_main(#mstate{mrole = Role} = MState) when Role =/= none ->
    ?LOG_DEBUG("Construct RH for ~p", [MState#mstate.mrole]),
    RH = case MState#mstate.mrole of
             grid ->
                 do_make_rh(grid, [], maps:new(), grid, MState);
             cluster ->
                 do_make_rh(grid, [], maps:new(), cluster, MState);
             partition ->
                 case do_get_my_subdiv(cluster, MState) of
                     Cluster = #cluster{id = Id} ->
                         ?LOG_DEBUG("My cluster subdivision: ~p", [Id]),
                         do_make_rh(cluster, [Cluster], maps:new(), partition, MState);
                     Partition = #partition{id = Id} ->
                         ?LOG_DEBUG("My partition subdivision: ~p", [Id]),
                         do_make_rh(partition, [Partition], maps:new(), partition, MState)
                 end;
             _ ->
                 Subdiv = do_get_my_subdiv(partition, MState),
                 ?LOG_DEBUG("My subdivision: ~p", [Subdiv]),
                 do_make_rh(element(1, Subdiv), [Subdiv], maps:new(), node, MState)
         end,
    Index = build_rh_index(RH),
    {Children, Neighbours} = build_rh_close_caches(RH),
    ?LOG_DEBUG("RH index built for ~p nodes (children=~p neighbours=~p)",
               [maps:size(Index), maps:size(Children), maps:size(Neighbours)]),
    MState#mstate{rh = RH,
                  rh_index = Index,
                  rh_children = Children,
                  rh_neighbours = Neighbours};
do_make_rh_main(#mstate{} = MState) ->
    ?LOG_INFO("Not ready to make RH"),
    MState.

-spec get_props_res(tuple(), map()) -> map().
get_props_res(Entity, Map) when is_tuple(Entity) ->
    Map2 = add_properties(wm_entity:get(properties, Entity), Map),
    add_resources(wm_entity:get(resources, Entity), Map2).

-spec do_make_rh(atom(), [tuple()], map(), atom(), #mstate{}) -> map().
do_make_rh(grid, _, RH, Owner, #mstate{} = MState) ->
    ?LOG_DEBUG("Do make RH for ~p", [Owner]),
    Grids = wm_conf:select(grid, all),
    case Grids of
        [] ->
            ?LOG_DEBUG("Grid description not defined => assume cluster without grid"),
            Cluster = do_get_my_subdiv(cluster, MState),
            do_make_rh(cluster, [Cluster], RH, Owner, MState);
        GridList when is_list(GridList) ->
            Grid = hd(GridList),
            Map1 = get_props_res(Grid, maps:new()),
            ClusterIDs = wm_entity:get(clusters, Grid),
            Map2 =
                case wm_conf:select(cluster, ClusterIDs) of
                    [] ->
                        ?LOG_DEBUG("No cluster is found with ids: ~p", [ClusterIDs]),
                        Map1;
                    Clusters when is_list(Clusters) ->
                        do_make_rh(cluster, Clusters, Map1, Owner, MState)
                end,
            GridID = wm_entity:get(id, Grid),
            maps:put({grid, GridID}, Map2, RH)
    end;
do_make_rh(cluster, [], RH, _, _) ->
    RH;
do_make_rh(cluster, [Cluster | T], RH, Owner, #mstate{} = MState) ->
    F = fun(Map) ->
           PartitionIDs = wm_entity:get(partitions, Cluster),
           case wm_conf:select(partition, PartitionIDs) of
               [] ->
                   ?LOG_DEBUG("No partition found with ids: ~p", [PartitionIDs]),
                   Map;
               Parts ->
                   do_make_rh(partition, Parts, Map, cluster, MState)
           end
        end,
    Map1 = get_props_res(Cluster, maps:new()),
    ClusterId = wm_entity:get(id, Cluster),
    RH2 = case Owner of
              grid ->
                  maps:put({cluster, ClusterId}, F(Map1), RH);
              _ ->
                  {ok, NodeName} = wm_self:get_sname(),
                  {ok, Host} = wm_self:get_host(),
                  {ok, Me} = wm_utils:get_my_vnode_name(long, atom, NodeName, Host),
                  Map2 =
                      case wm_entity:get(manager, Cluster) of
                          Me ->
                              F(Map1);
                          _ ->
                              Subdiv = do_get_my_subdiv(cluster, MState),
                              case wm_entity:get(id, Subdiv) of
                                  ClusterId ->
                                      F(Map1);
                                  _ ->
                                      Map1
                              end
                      end,
                  maps:put({cluster, ClusterId}, Map2, RH)
          end,
    do_make_rh(cluster, T, RH2, Owner, MState);
do_make_rh(partition, [], RH, _, _) ->
    RH;
do_make_rh(partition, [Partition | T], RH, Owner, #mstate{} = MState) ->
    F = fun(Map) ->
           NodeIDs = wm_entity:get(nodes, Partition),
           MapNs =
               case wm_conf:select(node, NodeIDs) of
                   [] ->
                       ?LOG_DEBUG("No nodes found with ids: ~p", [NodeIDs]),
                       Map;
                   Nodes ->
                       do_make_rh(node, Nodes, Map, partition, MState)
               end,
           case wm_entity:get(partitions, Partition) of
               [] ->
                   MapNs;
               PartIDs ->
                   case wm_conf:select(partition, PartIDs) of
                       [] ->
                           ?LOG_DEBUG("No partitions found with ids: ~p", [PartIDs]),
                           MapNs;
                       Parts ->
                           do_make_rh(partition, Parts, MapNs, partition, MState)
                   end
           end
        end,
    Map1 = get_props_res(Partition, maps:new()),
    PartitionId = wm_entity:get(id, Partition),
    RH2 = case Owner of
              X when X =:= cluster; X =:= partition ->
                  maps:put({partition, PartitionId}, F(Map1), RH);
              _ ->
                  {ok, NodeName} = wm_self:get_sname(),
                  {ok, Host} = wm_self:get_host(),
                  {ok, Me} = wm_utils:get_my_vnode_name(long, atom, NodeName, Host),
                  Map2 =
                      case wm_entity:get(manager, Partition) of
                          Me ->
                              F(Map1);
                          _ ->
                              Subdiv = do_get_my_subdiv(partition, MState),
                              case wm_entity:get(id, Subdiv) of
                                  PartitionId ->
                                      F(Map1);
                                  _ ->
                                      Map1
                              end
                      end,
                  maps:put({partition, PartitionId}, Map2, RH)
          end,
    do_make_rh(partition, T, RH2, Owner, MState);
do_make_rh(node, [], RH, _, _) ->
    RH;
do_make_rh(node, [Node | T], RH, Owner, #mstate{} = MState) ->
    NodeId = wm_entity:get(id, Node),
    %Map = get_props_res(Node, maps:new()),
    Map = #{}, % swm-sched does not support node resources within RH for now
    RH2 = maps:put({node, NodeId}, Map, RH),
    do_make_rh(node, T, RH2, Owner, MState).

-spec add_properties([{term(), term()}], map()) -> map().
add_properties([], Map) ->
    Map;
add_properties([{X, Y} | T], Map) ->
    add_properties(T, maps:put({property, X}, Y, Map)).

-spec add_resources([tuple()], map()) -> map().
add_resources([], Map) ->
    Map;
add_resources([R | T], Map) ->
    Name = wm_entity:get(name, R),
    RMap = maps:new(),
    RMap2 = add_properties(wm_entity:get(properties, R), RMap),
    RMap3 = add_resources(wm_entity:get(resources, R), RMap2),
    Map2 = maps:put({resource, Name}, RMap3, Map),
    add_resources(T, Map2).

-spec append_id_to_binary(pos_integer(), binary()) -> binary().
append_id_to_binary(ID, Binary) ->
    <<Binary/binary, ID:(?BINARY_ID_BITS)/unsigned-integer>>.

get_my_neightbour_addresses(Filters, RH) when is_list(Filters) ->
    F = fun(Filter, Acc) -> [get_my_neightbour_addresses(Filter, RH) | Acc] end,
    lists:flatten(
        lists:foldl(F, [], Filters));
get_my_neightbour_addresses(Filter, RH) ->
    case RH of
        undefined -> %FIXME do not check if undefined (should always be defined)
            ?LOG_DEBUG("Could not get my neighbours"),
            [];
        _ ->
            case maps:size(RH) of
                0 ->
                    [];
                1 ->
                    [Root] = maps:keys(RH), % RH should have only one root
                    Map = maps:get(Root, RH),
                    F = fun ({X, _}) when X == Filter ->
                                true;
                            (_) ->
                                false
                        end,
                    lists:filter(F, maps:keys(Map))
            end
    end.

-spec get_my_children([atom()] | atom(), #mstate{}) -> [{atom(), string()}].
get_my_children(Filters, #mstate{} = MState) when is_list(Filters) ->
    F = fun(Filter, Acc) -> [get_my_children(Filter, MState) | Acc] end,
    lists:flatten(
        lists:foldl(F, [], Filters));
get_my_children(Filter, #mstate{mrole = Role, rh = RH} = MState) ->
    case RH of
        undefined ->
            ?LOG_ERROR("Could not get my children"),
            [];
        _ ->
            case maps:size(RH) of
                0 ->
                    [];
                1 ->
                    [Root] = maps:keys(RH),
                    SubRH =
                        case [Role, Root] of
                            [grid, _] ->
                                maps:get(Root, RH);
                            [cluster, {cluster, _}] ->
                                maps:get(Root, RH);
                            [compute, _] ->
                                #{};
                            [_, _] ->
                                case do_get_my_subdiv(direct, MState) of
                                    [] ->
                                        #{};
                                    not_found ->
                                        #{};
                                    SubDiv ->
                                        SubDivID = wm_entity:get(id, SubDiv),
                                        SearchFor = {Role, SubDivID},
                                        case maps:find(SearchFor, maps:get(Root, RH)) of
                                            {ok, X} ->
                                                X;
                                            _ ->
                                                #{}
                                        end
                                end
                        end,
                    F = fun ({Y, _}) when Y == Filter ->
                                true;
                            (_) ->
                                false
                        end,
                    lists:filter(F, maps:keys(SubRH))
            end
    end.

make_ct_map([], _, Map) ->
    Map;
make_ct_map([{_, ID} | T], Counter, Map) ->
    make_ct_map(T, Counter + 1, maps:put(ID, Counter, Map)).

do_make_nl(Entity, #mstate{rh = RH, mrole = Role} = MState)
    when Role =/= none, Entity == cluster; Entity == partition ->
    ?LOG_DEBUG("Make NL for ~p", [Entity]),
    F = fun ({X, ID}, A) when X == Entity, is_integer(ID) ->
                append_id_to_binary(ID, A);
            ({_, _}, A) ->
                A
        end,
    {NL, M} =
        case get_my_neightbour_addresses(Entity, RH) of
            [] ->
                ?LOG_DEBUG("No neighbours found"),
                {<<>>, maps:new()};
            Neighbours ->
                ?LOG_DEBUG("Neighbours found: ~p", [Neighbours]),
                CtMap = make_ct_map(Neighbours, 0, maps:new()),
                Bin = lists:foldl(F, <<>>, Neighbours),
                {Bin, CtMap}
        end,
    ?LOG_DEBUG("NL: ~p, CtMap=~p", [NL, M]),
    MState#mstate{nl = NL, ct_map = M};
do_make_nl(compute, #mstate{rh = RH, mrole = Role} = MState) when Role =/= none ->
    ?LOG_DEBUG("Make NL for compute node"),
    F = fun ({node, ID}, A) when is_integer(ID) ->
                append_id_to_binary(ID, A);
            ({_, _}, A) ->
                A
        end,
    {NL, M} =
        case get_my_neightbour_addresses(node, RH) of
            [] ->
                ?LOG_DEBUG("No neighbours has found"),
                <<>>;
            Neighbours ->
                ?LOG_DEBUG("Neighbours has found: ~p", [Neighbours]),
                CtMap = make_ct_map(Neighbours, 0, maps:new()),
                Bin = lists:foldl(F, <<>>, Neighbours),
                {Bin, CtMap}
        end,
    ?LOG_DEBUG("NL: ~p, CtMap=~p", [NL, M]),
    MState#mstate{nl = NL, ct_map = M};
do_make_nl(_X, #mstate{} = MState) ->
    ?LOG_INFO("No need to make NL for ~p", [_X]),
    NL = <<>>,
    MState#mstate{nl = NL}.

init_ct(#mstate{} = MState) ->
    ?LOG_DEBUG("Initialize CT"),
    NeighbourNum = round(size(MState#mstate.nl) * ?BITS_IN_BYTE / ?BINARY_ID_BITS),
    CT = init_ct(<<>>, NeighbourNum, NeighbourNum, NeighbourNum, MState),
    ?LOG_DEBUG("CT: ~p", [CT]),
    MState#mstate{ct = CT}.

init_ct(CT, _, _, _, #mstate{mrole = Role}) when Role == none ->
    CT;
init_ct(CT, 0, N2, _, _) when N2 =< 1 ->
    CT;
init_ct(CT, 0, N2, Len, #mstate{} = MState) ->
    init_ct(CT, Len, N2 - 1, Len, MState);
init_ct(CT, N1, N2, Len, #mstate{} = MState) when N1 == N2 ->
    NewCT = <<0:(?BINARY_WEIGHT_BITS)/unsigned-integer, CT/binary>>,
    init_ct(NewCT, N1 - 1, N2, Len, MState);
init_ct(CT, N1, N2, Len, #mstate{} = MState) ->
    %% Assume 1 second is a relatively big weight and real value is usually less:
    X = <<?MILLISECONDS_IN_1_SECOND:(?BINARY_WEIGHT_BITS)/unsigned-integer>>,
    init_ct(<<X/binary, CT/binary>>, N1 - 1, N2, Len, MState).

do_update_latency(Node, #mstate{}) ->
    Trials = wm_conf:g(latency_trials, {?DEFAULT_TRIALS, integer}),
    NodeName = wm_utils:node_to_fullname(Node),
    _Latency = wm_latency:ping(NodeName, Trials),
    ?LOG_DEBUG("Measured latency for ~p: ~p microseconds", [Node, _Latency]),
    %TODO Implement latency saving
    %TODO Rename latency to roundtrip
    ok.

-spec do_get_latency(#node{}, #node{}, #mstate{}) -> pos_integer().
do_get_latency(SrcNode, DstNode, #mstate{} = MState) ->
    X = maps:get(
            wm_entity:get(id, SrcNode), MState#mstate.ct_map),
    Y = maps:get(
            wm_entity:get(id, DstNode), MState#mstate.ct_map),
    Size = round(byte_size(MState#mstate.nl) * ?BITS_IN_BYTE / ?BINARY_WEIGHT_BITS),
    get_integer_by_pos(X, Y, Size, MState#mstate.ct).

-spec get_integer_by_pos(pos_integer(), pos_integer(), pos_integer(), binary()) -> pos_integer().
get_integer_by_pos(X, Y, MatrixSize, Matrix) ->
    Pos = X * MatrixSize + Y,
    PosBytes = Pos * ?BITS_IN_BYTE,
    ValLen = round(?BINARY_WEIGHT_BITS / ?BITS_IN_BYTE),
    ValBin = binary:part(Matrix, PosBytes, ValLen),
    binary:decode_unsigned(ValBin).

-spec do_get_min_latency(#node{}, [atom()], {atom(), pos_integer()}, #mstate{}) -> {atom(), pos_integer()}.
do_get_min_latency(_, [], MinWeightNode, _) ->
    MinWeightNode;
do_get_min_latency(SrcNode, [DstNodeName | T], {}, #mstate{} = MState) ->
    {ok, DstNode} = wm_conf:select_node(atom_to_list(DstNodeName)),
    MinWeightNode = {DstNodeName, do_get_latency(SrcNode, DstNode, MState)},
    do_get_min_latency(SrcNode, T, MinWeightNode, MState);
do_get_min_latency(SrcNode, [DstNodeName | T], {MinNode, MinWeight}, #mstate{} = MState) ->
    {ok, DstNode} = wm_conf:select_node(atom_to_list(DstNodeName)),
    MinWeightNode =
        case do_get_latency(SrcNode, DstNode, MState) of
            W when W < MinWeight ->
                {W, DstNodeName};
            _ ->
                {MinNode, MinWeight}
        end,
    do_get_min_latency(SrcNode, T, MinWeightNode, MState).

-spec get_direct_subdiv(tuple()) -> tuple().
get_direct_subdiv(Entity) ->
    try
        case element(1, Entity) of
            X when X =:= node; X =:= partition ->
                Subdiv = wm_entity:get(subdivision, Entity),
                ID = wm_entity:get(subdivision_id, Entity),
                case wm_conf:select(Subdiv, {id, ID}) of
                    {error, _Error} ->
                        ?LOG_DEBUG("Could not find ~p with id=~p: ~p", [Subdiv, ID, _Error]),
                        not_found;
                    {ok, S} ->
                        S
                end;
            _ ->
                Entity
        end
    catch
        _E1:_E2 ->
            ?LOG_ERROR("Can not get direct subdiv ~p: ~p", [_E1, _E2]),
            Entity
    end.

-spec do_get_subdiv(atom(), tuple()) -> tuple().
do_get_subdiv(partition, Entity) ->
    case element(1, Entity) of
        node ->
            get_direct_subdiv(Entity);
        partition ->
            Entity
    end;
do_get_subdiv(cluster, Entity) ->
    case element(1, Entity) of
        node ->
            get_direct_subdiv(get_direct_subdiv(Entity));
        partition ->
            get_direct_subdiv(Entity);
        cluster ->
            Entity
    end.

-spec do_get_my_subdiv(atom(), #mstate{}) -> tuple() | not_found.
do_get_my_subdiv(direct, #mstate{} = MState) ->
    case wm_conf:select_node(MState#mstate.sname) of
        {error, _} ->
            not_found;
        {ok, Node} ->
            get_direct_subdiv(Node)
    end;
do_get_my_subdiv(SubDivName, #mstate{} = MState) ->
    case wm_conf:select_node(MState#mstate.sname) of
        {error, _} ->
            [];
        {ok, Node} ->
            do_get_subdiv(SubDivName, Node)
    end.

-spec do_get_tree_nodes(boolean(), #mstate{}) -> [tuple()].
do_get_tree_nodes(WithTemplates, #mstate{rh = RH}) when is_map(RH) ->
    F = fun FoldFun({node, ID}, _, IDs) ->
                [ID | IDs];
            FoldFun(_, V, IDs) when is_map(V) ->
                maps:fold(FoldFun, IDs, V)
        end,
    NodeIDs = maps:fold(F, [], RH),
    Nodes = wm_conf:select(node, NodeIDs),
    case WithTemplates of
        false ->
            lists:filter(fun(X) -> wm_entity:get(is_template, X) == false end, Nodes);
        true ->
            Nodes
    end;
do_get_tree_nodes(_, #mstate{rh = _RH}) ->
    ?LOG_DEBUG("RH has not been constructed yet: ~p", [_RH]),
    [].

%% @doc Finds a list of intermediate nodes (excluding the destination) on path between two nodes
%%
%% The idea is to check:
%% 1. If the destination node is a parent of the source (from) node.
%% 2. If parent is not the destination, then check neighbours.
%% 3. If not found, then check children recursively.
%% 4. If not found, then it returns empty list.
%%
%% Destination node is included in the path if the path found
%%
%% NOTE: If the path goes from leafs to top of the tree, then the
%%       function cannot find the path and returns empty list,
%%       which means that the next node should be parent node.
%%       Eventually one of the parent finds correct path and
%%       forward the message or the message comes to the grid
%%       management node and will be logged as error.

%% @doc Path from From toward To using a precomputed NodeId => root-first path index.
%% Returns [] when no forward path exists (same semantics as the former tree walk).
-spec find_rh_path_from_index(string(), string(), map()) -> [string()].
find_rh_path_from_index(FromNodeId, ToNodeId, _Index) when FromNodeId =:= ToNodeId ->
    [];
find_rh_path_from_index(FromNodeId, ToNodeId, Index) ->
    case {maps:find(FromNodeId, Index), maps:find(ToNodeId, Index)} of
        {{ok, FromPath}, {ok, ToPath}} ->
            path_from_indexed_routes(FromNodeId, FromPath, ToPath);
        _ ->
            []
    end.

-spec path_from_indexed_routes(string(), [string()], [string()]) -> [string()].
path_from_indexed_routes(FromNodeId, FromPath, ToPath) ->
    ToId = lists:last(ToPath),
    case parent_id_from_path(FromPath) of
        {ok, ToId} ->
            [ToId];
        Parent ->
            case lists:prefix(ToPath, FromPath) of
                true ->
                    %% To is a strict ancestor beyond the immediate parent — no upward route.
                    [];
                false ->
                    Common = common_prefix(FromPath, ToPath),
                    Rest = lists:nthtail(length(Common), ToPath),
                    case Rest of
                        [] ->
                            [];
                        _ ->
                            case Parent of
                                no_parent ->
                                    lists:filter(fun(X) -> X =/= FromNodeId end, ToPath);
                                {ok, ParentId} ->
                                    case lists:prefix(FromPath, ToPath) of
                                        true ->
                                            %% Straight down from From toward To.
                                            Rest;
                                        false ->
                                            %% Sideways via a sibling under From's parent.
                                            case length(Common) =:= length(FromPath) - 1
                                                 andalso lists:last(Common) =:= ParentId
                                            of
                                                true ->
                                                    Rest;
                                                false ->
                                                    []
                                            end
                                    end
                            end
                    end
            end
    end.

-spec parent_id_from_path([string()]) -> {ok, string()} | no_parent.
parent_id_from_path([_]) ->
    no_parent;
parent_id_from_path(Path) ->
    {ok, lists:nth(length(Path) - 1, Path)}.

-spec common_prefix([string()], [string()]) -> [string()].
common_prefix([A | T1], [A | T2]) ->
    [A | common_prefix(T1, T2)];
common_prefix(_, _) ->
    [].

%% @doc Build NodeId => root-first path index for O(depth) get_path lookups.
-spec build_rh_index(map() | undefined) -> map().
build_rh_index(undefined) ->
    #{};
build_rh_index(RH) when map_size(RH) == 0 ->
    #{};
build_rh_index(RH) ->
    build_rh_index_tree(maps:to_list(RH), [], #{}).

-spec build_rh_index_tree([{{atom(), string()}, map()}], [string()], map()) -> map().
build_rh_index_tree([], _PathPrefix, Acc) ->
    Acc;
build_rh_index_tree([{{node, Id}, _Sub} | T], PathPrefix, Acc) ->
    Acc2 = maps:put(Id, PathPrefix ++ [Id], Acc),
    build_rh_index_tree(T, PathPrefix, Acc2);
build_rh_index_tree([{{Division, Id}, SubRH} | T], PathPrefix, Acc) when Division =/= node ->
    Acc2 =
        case division_manager_id(Division, Id) of
            {ok, MgrId} ->
                NewPrefix = PathPrefix ++ [MgrId],
                AccMgr = maps:put(MgrId, NewPrefix, Acc),
                build_rh_index_tree(maps:to_list(SubRH), NewPrefix, AccMgr);
            _ ->
                build_rh_index_tree(maps:to_list(SubRH), PathPrefix, Acc)
        end,
    build_rh_index_tree(T, PathPrefix, Acc2);
build_rh_index_tree([_ | T], PathPrefix, Acc) ->
    build_rh_index_tree(T, PathPrefix, Acc).

-spec division_manager_id(atom(), string()) -> {ok, string()} | {error, not_found}.
division_manager_id(Division, Id) ->
    case wm_conf:select(Division, {id, Id}) of
        {ok, Entity} ->
            MgrName = wm_entity:get(manager, Entity),
            case wm_conf:select_node(MgrName) of
                {ok, #node{id = MgrId}} ->
                    {ok, MgrId};
                _ ->
                    {error, not_found}
            end;
        _ ->
            {error, not_found}
    end.

%% @doc Build children/neighbours caches in one RH walk (avoids per-call DB scans).
-spec build_rh_close_caches(map() | undefined) -> {map(), map()}.
build_rh_close_caches(undefined) ->
    {#{}, #{}};
build_rh_close_caches(RH) when map_size(RH) == 0 ->
    {#{}, #{}};
build_rh_close_caches(RH) ->
    Cache0 = #{},
    {Children, Neighbours, _} = index_close_entries(maps:to_list(RH), #{}, #{}, Cache0),
    {Children, Neighbours}.

-spec index_close_entries([{{atom(), string()}, map()}], map(), map(), map()) -> {map(), map(), map()}.
index_close_entries([], Children, Neighbours, Cache) ->
    {Children, Neighbours, Cache};
index_close_entries([{{node, _}, _} | T], Children, Neighbours, Cache) ->
    index_close_entries(T, Children, Neighbours, Cache);
index_close_entries([{{Division, Id}, SubRH} | T], Children, Neighbours, Cache) when Division =/= node ->
    Entries = maps:to_list(SubRH),
    {Children1, Neighbours1, Cache1} = index_close_entries(Entries, Children, Neighbours, Cache),
    {Children2, Neighbours2, Cache2} =
        case division_manager_id(Division, Id) of
            {ok, MgrId} ->
                {DirectNodes, CacheD} = direct_member_nodes(Entries, Cache1),
                ChildNodes = collect_mgr_children(MgrId, Entries, CacheD),
                %% Flat list kept without the cache tuple from collect
                {ChildList, CacheC} = ChildNodes,
                Neighbours3 =
                    lists:foldl(fun(#node{id = Nid}, AccNb) ->
                                   Others = [N || #node{id = Oid} = N <- DirectNodes, Oid =/= Nid],
                                   maps:put(Nid, Others, AccNb)
                                end,
                                Neighbours1,
                                DirectNodes),
                {maps:put(MgrId, ChildList, Children1), Neighbours3, CacheC};
            _ ->
                {Children1, Neighbours1, Cache1}
        end,
    index_close_entries(T, Children2, Neighbours2, Cache2);
index_close_entries([_ | T], Children, Neighbours, Cache) ->
    index_close_entries(T, Children, Neighbours, Cache).

%% Direct members of a division: leaf nodes + managers of immediate child divisions (not flattened).
-spec direct_member_nodes([{{atom(), string()}, map()}], map()) -> {[#node{}], map()}.
direct_member_nodes(Entries, Cache) ->
    lists:foldl(fun ({{node, Id}, _}, {Acc, CacheIn}) ->
                        case fetch_node_cached(Id, CacheIn) of
                            {ok, #node{is_template = false} = Node, CacheOut} ->
                                {[Node | Acc], CacheOut};
                            {_, _, CacheOut} ->
                                {Acc, CacheOut}
                        end;
                    ({{Division, Id}, _}, {Acc, CacheIn}) when Division =/= node ->
                        case division_manager_id(Division, Id) of
                            {ok, MgrId} ->
                                case fetch_node_cached(MgrId, CacheIn) of
                                    {ok, Node, CacheOut} ->
                                        {[Node | Acc], CacheOut};
                                    {_, _, CacheOut} ->
                                        {Acc, CacheOut}
                                end;
                            _ ->
                                {Acc, CacheIn}
                        end;
                    (_, AccCache) ->
                        AccCache
                end,
                {[], Cache},
                Entries).

%% children_only semantics for a division manager (flatten self-managed nested partitions).
-spec collect_mgr_children(string(), [{{atom(), string()}, map()}], map()) -> {[#node{}], map()}.
collect_mgr_children(MgrId, Entries, Cache) ->
    lists:foldl(fun ({{node, Id}, _}, {Acc, CacheIn}) ->
                        case fetch_node_cached(Id, CacheIn) of
                            {ok, #node{is_template = false, id = Id} = Node, CacheOut} when Id =/= MgrId ->
                                {[Node | Acc], CacheOut};
                            {_, _, CacheOut} ->
                                {Acc, CacheOut}
                        end;
                    ({{Division, Id}, SubRH}, {Acc, CacheIn}) when Division =/= node ->
                        case division_manager_id(Division, Id) of
                            {ok, MgrId} ->
                                {Nested, CacheOut} = collect_mgr_children(MgrId, maps:to_list(SubRH), CacheIn),
                                {Nested ++ Acc, CacheOut};
                            {ok, OtherMgrId} ->
                                case fetch_node_cached(OtherMgrId, CacheIn) of
                                    {ok, Node, CacheOut} ->
                                        {[Node | Acc], CacheOut};
                                    {_, _, CacheOut} ->
                                        {Acc, CacheOut}
                                end;
                            _ ->
                                {Acc, CacheIn}
                        end;
                    (_, AccCache) ->
                        AccCache
                end,
                {[], Cache},
                Entries).

-spec fetch_node_cached(string(), map()) -> {ok, #node{}, map()} | {error, not_found, map()}.
fetch_node_cached(Id, Cache) ->
    case maps:find(Id, Cache) of
        {ok, Node} ->
            {ok, Node, Cache};
        error ->
            case wm_conf:select(node, {id, Id}) of
                {ok, #node{} = Node} ->
                    {ok, Node, maps:put(Id, Node, Cache)};
                _ ->
                    {error, not_found, Cache}
            end
    end.

%% @doc Returns sub-tree of RH of a node (with children and neightbour nodes included if needed)
-spec get_node_rh(node_id(), map(), boolean()) -> map().
get_node_rh(_, undefined, _) ->
    #{};
get_node_rh(NodeId, RH, Scope) ->
    [RootKey] = maps:keys(RH), % RH should have only one root
    RootRH = maps:get(RootKey, RH),
    case get_node_surrounding_rh({RootKey, RootRH}, NodeId, {false, {}, RH}) of
        {false, _, #{}} ->
            #{};
        {true, {}, SubRH} ->
            SubRH;
        {true, _, Map} when map_size(Map) == 0 ->
            #{};
        {true, FoundKey, SubRH} ->
            case Scope of
                children_only ->
                    maps:get(FoundKey, SubRH);
                _ ->
                    SubRH
            end
    end.

-spec get_node_surrounding_rh({{atom(), string()}, map()}, node_id(), {boolean(), {atom(), string()}, map()}) ->
                                 {boolean(), {atom(), string()}, map()}.
get_node_surrounding_rh({{Division, Id}, SubRH}, NodeId, {false, FoundKey, LastSubRH}) when Division =/= node ->
    {ok, DivisionEntity} = wm_conf:select(Division, {id, Id}),
    MgrName = wm_entity:get(manager, DivisionEntity),
    {ok, MgrNode} = wm_conf:select_node(MgrName),
    case wm_entity:get(id, MgrNode) of
        NodeId ->
            {true, {Division, Id}, LastSubRH};
        _ ->
            search_surrounding_children(maps:to_list(SubRH), NodeId, FoundKey, SubRH)
    end;
get_node_surrounding_rh({{_, Id}, _}, NodeId, {false, FoundKey, LastSubRH}) when Id == NodeId ->
    {true, FoundKey, LastSubRH};
get_node_surrounding_rh({{_, _}, SubRH}, NodeId, {false, FoundKey, LastSubRH}) ->
    search_surrounding_children(maps:to_list(SubRH), NodeId, FoundKey, LastSubRH);
get_node_surrounding_rh({{_, _}, _}, _, {true, FoundKey, LastSubRH}) ->
    {true, FoundKey, LastSubRH}.

-spec search_surrounding_children([{{atom(), string()}, map()}], node_id(), {atom(), string()} | {}, map()) ->
                                     {boolean(), {atom(), string()} | {}, map()}.
search_surrounding_children([], _NodeId, _FoundKey, _SubRH) ->
    {false, {}, #{}};
search_surrounding_children([P | T], NodeId, FoundKey, SubRH) ->
    case get_node_surrounding_rh(P, NodeId, {false, FoundKey, SubRH}) of
        {true, _, _} = Found ->
            Found;
        _ ->
            search_surrounding_children(T, NodeId, FoundKey, SubRH)
    end.

-spec find_close_nodes(node_id(), map(), atom()) -> [#node{}].
find_close_nodes(NodeId, RH, children_and_neighbours) ->
    find_close_nodes(NodeId, RH, neighbours_only) ++ find_close_nodes(NodeId, RH, children_only);
find_close_nodes(NodeId, RH, Scope) ->
    SubRH = get_node_rh(NodeId, RH, Scope),
    F = fun ({node, EntityId}, _, Nodes) ->
                case wm_conf:select(node, {id, EntityId}) of
                    {ok, #node{is_template = false, id = Id} = Node} when Id =/= NodeId ->
                        [Node | Nodes];
                    _ ->
                        Nodes
                end;
            ({DivisionType, DivisionId}, EntityRH, Nodes) ->
                case wm_conf:select(DivisionType, {id, DivisionId}) of
                    {error, _} ->
                        Nodes;
                    {ok, Division} ->
                        case wm_utils:get_division_manager(DivisionType, Division, false) of
                            {ok, #node{id = NodeId}} ->
                                case Scope of
                                    children_only ->
                                        SubSubRH = maps:put({DivisionType, DivisionId}, EntityRH, maps:new()),
                                        find_close_nodes(NodeId, SubSubRH, children_only) ++ Nodes;
                                    neighbours_only ->
                                        Nodes
                                end;
                            {ok, Node} ->
                                [Node | Nodes];
                            _ ->
                                Nodes
                        end
                end
        end,
    maps:fold(F, [], SubRH).
