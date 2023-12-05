-module(wm_topology).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([schedule_latency_update/1, get_children/0, get_children_nodes/1, get_neighbour_nodes/0,
         get_my_neighbour_addresses/0, get_latency/2, get_min_latency_to/1, get_tree/1, get_subdiv/1, get_subdiv/0,
         on_path/2, get_tree_nodes/1, reload/0, is_my_direct_child/1]).

-include("wm_log.hrl").
-include("wm_entity.hrl").

-include_lib("eunit/include/eunit.hrl").

-record(mstate,
        {rh :: map(),            %% Resource Hierarchy: {{DevisionAtom, DevisionId} => Resouce sub hierarchy}
         nl :: binary(),         %% Neighbour List (binary vector)
         ct :: binary(),         %% Connection Tolopogy (binary matrix)
         ct_map :: map(),        %% NodeId --> Position in CT
         mrole :: atom(),        %% Management role name
         sname :: string()}).    %% Short node name

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
-spec get_subdiv() -> [term()].
get_subdiv() ->
    wm_utils:protected_call(?MODULE, {get_subdiv, direct}, #{}).

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

%% @doc Reload topology data structures
-spec reload() -> ok.
reload() ->
    wm_utils:protected_call(?MODULE, construct_data_types, []).

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

handle_call({get_path, FromNodeId, ToNodeId}, _, #mstate{rh = RH} = MState) ->
    NextNodeId =
        case find_rh_path(FromNodeId, ToNodeId, RH) of
            [] ->
                not_found;
            List when is_list(List) ->
                {ok, hd(List)}
        end,
    {reply, NextNodeId, MState};
handle_call({is_my_direct_child, NodeId}, _, #mstate{rh = RH} = MState) ->
    F = fun (#node{id = Id}) when Id == NodeId ->
                true;
            (_) ->
                false
        end,
    MyNodeId = wm_self:get_node_id(),
    Result = lists:any(F, find_close_nodes(MyNodeId, RH, children_only)),
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
handle_call(get_my_neighbour_addresses, _, #mstate{rh = RH} = MState) ->
    Nodes = find_close_nodes(wm_self:get_node_id(), RH, children_and_neighbours),
    Addresses = [wm_utils:get_address(Node) || Node <- Nodes],
    {reply, Addresses, MState};
handle_call(get_my_neighbour_nodes, _, #mstate{rh = RH} = MState) ->
    {reply, find_close_nodes(wm_self:get_node_id(), RH, children_and_neighbours), MState};
handle_call(get_children, _, #mstate{} = MState) ->
    {reply, get_my_children([cluster, partition, node], MState), MState};
handle_call({get_children_nodes, NodeId}, _, #mstate{rh = RH} = MState) ->
    {reply, find_close_nodes(NodeId, RH, children_only), MState};
handle_call(construct_data_types, _, #mstate{} = MState) ->
    ?LOG_INFO("Construct topology"),
    MState1 = set_management_role(MState),
    MState2 = do_make_rh_main(MState1),
    MState3 = do_make_nl(MState2#mstate.mrole, MState2),
    MState4 = init_ct(MState3),
    ?LOG_DEBUG("New MState: ~p", [MState4]),
    wm_event:announce(topology_constructed),
    {reply, ok, MState4};
handle_call(_Msg, _, #mstate{} = MState) ->
    {reply, {error, not_handled}, MState}.

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
    MState#mstate{rh = RH};
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
            ?LOG_ERROR("Grid description not defined => assume cluster without grid"),
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
-spec find_rh_path(string(), string(), map()) -> list().
find_rh_path(_, ToNodeId, _RH = undefined) ->
    ?LOG_DEBUG("RH has not been created yet: assume next node is ~p", [ToNodeId]),
    [ToNodeId];
find_rh_path(FromNodeId, ToNodeId, RH) ->
    ?LOG_DEBUG("Try to find the RH path: ~p --> ~p", [FromNodeId, ToNodeId]),
    case get_parent_id(FromNodeId) of
        {error, not_found} ->
            [];
        {ok, no_parent} ->  % cluster manager node without a parent
            Path1 = find_child_rh_path(ToNodeId, RH, []),
            Path2 = lists:filter(fun(X) -> X =/= FromNodeId end, Path1),
            Path3 = lists:reverse(Path2),
            Path3;
        {ok, ToNodeId} ->
            [ToNodeId];
        _ ->
            NodeRH = get_node_rh(FromNodeId, RH, children_and_neighbours),
            Neighbours = lists:map(fun({X, _}) -> X end, maps:to_list(NodeRH)),
            CheckNeightbours =
                fun ({node, Id}) ->
                        {ok, Node} = wm_conf:select(node, {id, Id}),
                        wm_entity:get(id, Node) == ToNodeId;
                    ({SubDiv, Id}) ->
                        {ok, X} = wm_conf:select(SubDiv, {id, Id}),
                        case is_subdiv_manager(ToNodeId, X) of
                            {false, _} ->
                                false;
                            true ->
                                true
                        end
                end,
            case lists:any(CheckNeightbours, Neighbours) of
                true ->
                    [ToNodeId];
                false ->
                    Path1 = find_child_rh_path(ToNodeId, NodeRH, []),
                    Path2 = lists:filter(fun(X) -> X =/= FromNodeId end, Path1),
                    Path3 = lists:reverse(Path2),
                    Path3
            end
    end.

%% @doc Returns sub-tree of RH of a node (with children and neightbour nodes included if needed)
-spec get_node_rh(node_id(), map(), boolean()) -> map().
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
            F = fun(P) -> get_node_surrounding_rh(P, NodeId, {false, FoundKey, SubRH}) end,
            case lists:flatten(
                     lists:map(F, maps:to_list(SubRH)))
            of
                [] ->
                    {false, {}, #{}};
                List ->
                    UniqueList = lists:usort(List), % remove duplicates
                    case lists:filter(fun({B, _, _}) -> B =:= true end, UniqueList) of
                        [] ->
                            {false, {}, #{}};
                        [Found] ->
                            Found
                    end
            end
    end;
get_node_surrounding_rh({{_, Id}, _}, NodeId, {false, FoundKey, LastSubRH}) when Id == NodeId ->
    {true, FoundKey, LastSubRH};
get_node_surrounding_rh({{_, _}, SubRH}, NodeId, {false, FoundKey, LastSubRH}) ->
    F = fun(P, Acc) -> get_node_surrounding_rh(P, NodeId, Acc) end,
    lists:foldl(F, {false, FoundKey, LastSubRH}, maps:to_list(SubRH));
get_node_surrounding_rh({{_, _}, _}, _, {true, FoundKey, LastSubRH}) ->
    {true, FoundKey, LastSubRH}.

-spec find_child_rh_path(node_id(), map(), [node_id()]) -> [node_id()].
find_child_rh_path(_, RH, _) when map_size(RH) == 0 ->
    [];
find_child_rh_path(NodeId, RH, Path) ->
    F = fun ({{node, Id}, _})
                when Id =:= NodeId ->                              % searched node is found
                [NodeId | Path];
            ({{node, _}, _}) ->                                    % node does not have children
                [];
            ({{Division, Id}, SubRH}) ->                           % check cluster or partition
                {ok, X} = wm_conf:select(Division, {id, Id}),
                case is_subdiv_manager(NodeId, X) of
                    true ->                                        % searched node (manager) is found
                        [NodeId | Path];
                    {false, MgrId} ->                              % not found yet => search in depth
                        find_child_rh_path(NodeId, SubRH, [MgrId | Path])
                end
        end,
    Paths = lists:map(F, maps:to_list(RH)),
    case lists:filter(fun(X) -> X =/= [] end, Paths) of
        [] ->
            [];
        [OnlyOneCorrectPath] ->
            OnlyOneCorrectPath
    end.

-spec is_subdiv_manager(node_id(), tuple()) -> true | {false, node_id()}.
is_subdiv_manager(NodeId, Entity) ->
    MgrName = wm_entity:get(manager, Entity),
    {ok, Node} = wm_conf:select_node(MgrName),
    case wm_entity:get(id, Node) of
        NodeId ->
            true;
        OtherId ->
            {false, OtherId}
    end.

-spec get_parent_id(node_id()) -> {ok, node_id()} | {error, not_found}.
get_parent_id(NodeId) ->
    case wm_conf:select(node, {id, NodeId}) of
        {ok, #node{parent = ParentName}} ->
            case wm_conf:select_node(ParentName) of
                {ok, #node{id = ParentId}} ->
                    {ok, ParentId};
                {error, not_found} ->
                    {ok, no_parent}
            end;
        _ ->
            {error, not_found}
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

%% ============================================================================
%% Tests
%% ============================================================================

-ifdef(EUNIT).

-include_lib("eunit/include/eunit.hrl").

-spec get_mock_ct() -> #mstate{}.
get_mock_ct() ->
    RH = #{{grid, 1} =>
               #{{cluster, 1} => #{},
                 {cluster, 2} =>
                     #{{partition, 1} =>
                           #{{node, 1} => #{},
                             {node, 2} => #{},
                             {node, 3} => #{}},
                       {partition, 2} => #{}},
                 {cluster, 3} => #{}}},
    MState1 = #mstate{rh = RH},
    MState2 = do_make_nl(cluster, MState1),
    init_ct(MState2).

-spec init_ct_test() -> ok.
init_ct_test() ->
    MState = get_mock_ct(),
    RefCt =
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0,
          0, 0, 0, 0>>,
    ?LOG_DEBUG("~p", MState#mstate.ct),
    ?assert(MState#mstate.ct == RefCt).

-spec get_value_from_cl_test() -> ok.
get_value_from_cl_test() ->
    CT = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
           0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7,
           0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
           0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1>>,
    ?assert(get_integer_by_pos(0, 0, 4, CT) == 0),
    ?assert(get_integer_by_pos(2, 1, 4, CT) == 8),
    ?assert(get_integer_by_pos(3, 3, 4, CT) == 72340172838076673).

-spec prepare_test_rh1() -> #{}.
prepare_test_rh1() ->
    % NOTE: in this RH id is also its name (for simplification),
    % grid, cluster and partition manager nodes have names/ids equals
    % to its subdivision id plus "_n0". All non-manager node names/ids
    % are formed as SUBDIVISION_ID plus "_nX", where X > 0.
    SetParent =
        fun ("c1_n0", Node) ->
                wm_entity:set([{parent, "g1_n0"}], Node);
            ("p11_n0", Node) ->
                wm_entity:set([{parent, "c1_n0"}], Node);
            ("c2_n0", Node) ->
                wm_entity:set([{parent, "g1_n0"}], Node);
            ("p21_n0", Node) ->
                wm_entity:set([{parent, "c2_n0"}], Node);
            ("p21_n1", Node) ->
                wm_entity:set([{parent, "p21_n0"}], Node);
            ("p21_n2", Node) ->
                wm_entity:set([{parent, "p21_n0"}], Node);
            ("p211_n0", Node) ->
                wm_entity:set([{parent, "p21_n0"}], Node);
            ("p211_n1", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p211_n2", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p211_n3", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p2111_n0", Node) ->
                wm_entity:set([{parent, "p211_n0"}], Node);
            ("p22_n0", Node) ->
                wm_entity:set([{parent, "c2_n0"}], Node);
            ("p221_n0", Node) ->
                wm_entity:set([{parent, "p22_n0"}], Node);
            ("p2211_n0", Node) ->
                wm_entity:set([{parent, "p221_n0"}], Node);
            ("p22111_n0", Node) ->
                wm_entity:set([{parent, "p2211_n0"}], Node);
            ("p22111_n1", Node) ->
                wm_entity:set([{parent, "p22111_n0"}], Node);
            ("c3_n0", Node) ->
                wm_entity:set([{parent, "g1_n0"}], Node);
            (_, Node) ->
                Node
        end,
    SelectById =
        fun (node, {id, Id}) ->
                Node = wm_entity:set([{id, Id}, {name, Id}], wm_entity:new(node)),
                {ok, SetParent(Id, Node)};
            (SubDiv, {id, Id}) ->
                {ok, wm_entity:set([{id, Id}, {name, Id}, {manager, Id ++ "_n0"}], wm_entity:new(SubDiv))}
        end,
    SelectByName = fun(NameIsAlsoId) -> SelectById(node, {id, NameIsAlsoId}) end,
    meck:new(wm_conf),
    meck:expect(wm_conf, select, SelectById),
    meck:expect(wm_conf, select_node, SelectByName),
    meck:new(wm_self),
    meck:expect(wm_self, get_node_id, fun() -> "c2_n0" end),
    #{{grid, "g1"} =>
          #{{cluster, "c1"} => #{{partition, "p11"} => #{}},
            {cluster, "c2"} =>
                #{{partition, "p21"} =>
                      #{{node, "p21_n1"} => #{},
                        {node, "p21_n2"} => #{},
                        {partition, "p211"} =>
                            #{{node, "p211_n1"} => #{},
                              {node, "p211_n2"} => #{},
                              {node, "p211_n3"} => #{},
                              {partition, "p2111"} => #{}}},
                  {partition, "p22"} =>
                      #{{partition, "p221"} =>
                            #{{partition, "p2211"} => #{{partition, "p22111"} => #{{node, "p22111_n1"} => #{}}}}}},
            {cluster, "c3"} => #{}}}.

-spec prepare_test_rh2() -> #{}.
prepare_test_rh2() ->
    % NOTE: in this RH node id is also its name (for simplification)
    SetExtraProperties =
        fun ("compute-node-1", Node) ->
                wm_entity:set([{parent, "node-skyport"}], Node);
            ("compute-node-2", Node) ->
                wm_entity:set([{parent, "compute-node-1"}], Node);
            ("template-node-1", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-2", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-3", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-4", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-5", Node) ->
                wm_entity:set([{is_template, true}], Node);
            ("template-node-6", Node) ->
                wm_entity:set([{is_template, true}], Node);
            (_, Node) ->
                Node
        end,
    SelectById =
        fun (node, {id, Id}) ->
                Node = wm_entity:set([{id, Id}, {name, Id}], wm_entity:new(node)),
                {ok, SetExtraProperties(Id, Node)};
            (cluster, {id, Id = "cluster"}) ->
                {ok,
                 wm_entity:set([{id, Id},
                                {name, Id},
                                {manager, "node-skyport"},
                                {partitions, ["remote-partition", "local-partition"]}],
                               wm_entity:new(cluster))};
            (partition, {id, Id = "remote-partition"}) ->
                {ok,
                 wm_entity:set([{id, Id},
                                {name, Id},
                                {manager, "node-skyport"},
                                {partitions, ["remote-sub-partition"]}],
                               wm_entity:new(partition))};
            (partition, {id, Id = "local-partition"}) ->
                {ok, wm_entity:set([{id, Id}, {name, Id}, {manager, "node-skyport"}], wm_entity:new(partition))};
            (partition, {id, Id = "remote-sub-partition"}) ->
                {ok, wm_entity:set([{id, Id}, {name, Id}, {manager, "compute-node-1"}], wm_entity:new(partition))}
        end,
    SelectByName = fun(NameIsAlsoId) -> SelectById(node, {id, NameIsAlsoId}) end,
    meck:new(wm_conf),
    meck:expect(wm_conf, select, SelectById),
    meck:expect(wm_conf, select_node, SelectByName),
    meck:new(wm_self),
    meck:expect(wm_self, get_node_id, fun() -> "node-skyport" end),
    #{{cluster, "cluster"} =>
          #{{partition, "remote-partition"} =>
                #{{node, "template-node-1"} => #{},
                  {node, "template-node-2"} => #{},
                  {node, "template-node-3"} => #{},
                  {node, "template-node-4"} => #{},
                  {node, "template-node-5"} => #{},
                  {node, "template-node-6"} => #{},
                  {partition, "remote-sub-partition"} =>
                      #{{node, "compute-node-1"} => #{}, {node, "compute-node-2"} => #{}}},
            {partition, "local-partition"} => #{{node, "node-skyport"} => #{}}}}.

-spec finalize() -> ok.
finalize() ->
    meck:unload().

-spec node_surrounding_rh_test() -> ok.
node_surrounding_rh_test() ->
    RH = prepare_test_rh1(),
    Expected =
        #{{node, "p21_n1"} => #{},
          {node, "p21_n2"} => #{},
          {partition, "p211"} =>
              #{{node, "p211_n1"} => #{},
                {node, "p211_n2"} => #{},
                {node, "p211_n3"} => #{},
                {partition, "p2111"} => #{}}},
    ?assertEqual(Expected, get_node_rh("p211_n0", RH, children_and_neighbours)),
    finalize().

-spec node_children_rh_test() -> ok.
node_children_rh_test() ->
    RH = prepare_test_rh1(),
    Expected =
        #{{node, "p211_n1"} => #{},
          {node, "p211_n2"} => #{},
          {node, "p211_n3"} => #{},
          {partition, "p2111"} => #{}},
    ?assertEqual(Expected, get_node_rh("p211_n0", RH, children_only)),
    finalize().

-spec children_nodes_test() -> ok.
children_nodes_test() ->
    RH = prepare_test_rh1(),
    Result = find_close_nodes("p211_n0", RH, children_only),
    ?assertEqual(4, length(Result)),
    ?assertMatch(#node{id = "p2111_n0"}, lists:nth(1, Result)),
    ?assertMatch(#node{id = "p211_n3"}, lists:nth(2, Result)),
    ?assertMatch(#node{id = "p211_n2"}, lists:nth(3, Result)),
    ?assertMatch(#node{id = "p211_n1"}, lists:nth(4, Result)),
    finalize().

-spec search_path_in_rh_test() -> ok.
search_path_in_rh_test() ->
    RH = prepare_test_rh1(),
    % From top to bottom:
    ?assertEqual([], find_rh_path("c2_n0", "foo", RH)),
    ?assertEqual(["c2_n0", "p22_n0", "p221_n0", "p2211_n0", "p22111_n0", "p22111_n1"],
                 find_rh_path("c1_n0", "p22111_n1", RH)),
    ?assertEqual(["p211_n3"], find_rh_path("p211_n0", "p211_n3", RH)),
    ?assertEqual(["p211_n0"], find_rh_path("p21_n0", "p211_n0", RH)),
    ?assertEqual(["c2_n0"], find_rh_path("c1_n0", "c2_n0", RH)),
    ?assertEqual(["p21_n0", "p211_n0", "p211_n2"], find_rh_path("c2_n0", "p211_n2", RH)),
    ?assertEqual(["p21_n0", "p211_n0", "p2111_n0"], find_rh_path("c2_n0", "p2111_n0", RH)),
    ?assertEqual(["p22_n0", "p221_n0", "p2211_n0", "p22111_n0", "p22111_n1"], find_rh_path("c2_n0", "p22111_n1", RH)),
    % From bottom to top:
    ?assertEqual([], find_rh_path("foo", "c2_n0", RH)),
    ?assertEqual(["p211_n0"], find_rh_path("p211_n3", "p211_n0", RH)),
    ?assertEqual(["p21_n0"], find_rh_path("p211_n0", "p21_n0", RH)),
    ?assertEqual([], find_rh_path("p2111_n0", "c2_n0", RH)),
    ?assertEqual([], find_rh_path("p22111_n1", "c2_n0", RH)),
    ?assertEqual([], find_rh_path("p211_n3", "c1_n0", RH)),
    finalize().

-spec children_duplicate_managers_test() -> ok.
children_duplicate_managers_test() ->
    RH = prepare_test_rh2(),
    Result = find_close_nodes("node-skyport", RH, children_only),
    ?assertEqual(1, length(Result)),
    ?assertMatch(#node{id = "compute-node-1"}, lists:nth(1, Result)),
    finalize().

-spec neighbours_duplicate_managers_test() -> ok.
neighbours_duplicate_managers_test() ->
    RH = prepare_test_rh2(),
    Result = find_close_nodes("node-skyport", RH, neighbours_only),
    ?assertEqual(0, length(Result)),
    finalize().

-endif.
