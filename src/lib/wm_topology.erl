-module(wm_topology).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([schedule_latency_update/1, get_children/1, get_neighbours/1, get_neighbour_addresses/1, get_latency/2,
         get_min_latency_to/1, get_tree/1, get_subdiv/1, get_subdiv/0, on_path/2, get_tree_nodes/1, reload/0,
         is_direct_child/1]).

-include("wm_log.hrl").
-include("wm_entity.hrl").

-record(mstate,
        {rh :: map(),            %% Resource Hierarchy
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
-spec is_direct_child(string()) -> true | false.
is_direct_child(NodeId) ->
    wm_utils:protected_call(?MODULE, {is_direct_child, NodeId}, false).

%% @doc Initiate latency update to the specified node
-spec schedule_latency_update(tuple()) -> ok.
schedule_latency_update(Node) ->
    gen_server:cast(?MODULE, {update_latency, Node}).

%% @doc Get all neightbour records
-spec get_neighbours(atom()) -> [{atom(), number()}].
get_neighbours(SortBy) ->
    wm_utils:protected_call(?MODULE, {get_neighbours, SortBy}, []).

%% @doc Get all children records
-spec get_children(atom()) -> [{atom(), number()}].
get_children(SortBy) ->
    wm_utils:protected_call(?MODULE, {get_children, SortBy}, []).

%% @doc Get neightbour nodenames
-spec get_neighbour_addresses(atom()) -> list().
get_neighbour_addresses(SortBy) ->
    wm_utils:protected_call(?MODULE, {get_neightbour_addresses, SortBy}, []).

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
handle_call({is_direct_child, NodeId}, _, #mstate{} = MState) ->
    Children = get_my_children([cluster, partition, node], unsorted, MState),
    F = fun ({node, Id}) ->
                NodeId == Id;
            ({partition, Id}) ->
                case wm_conf:select(partition, {id, Id}) of
                    {ok, Part} ->
                        MgrFullName = wm_entity:get_attr(manager, Part),
                        case wm_conf:select_node(MgrFullName) of
                            {ok, Node} ->
                                NodeId == wm_entity:get_attr(id, Node);
                            _ ->
                                false
                        end;
                    _ ->
                        false
                end;
            (_) ->
                false
        end,
    Result = lists:any(F, Children),
    {reply, Result, MState};
handle_call({get_tree_nodes, WithTemplates}, _, #mstate{} = MState) ->
    {reply, do_get_tree_nodes(WithTemplates, MState), MState};
handle_call({get_subdiv, Name}, _, #mstate{} = MState) ->
    {reply, do_get_my_subdiv(Name, MState), MState};
handle_call({get_tree, list}, _, #mstate{rh = RH} = MState) ->
    {reply, wm_utils:map_to_list(RH), MState};
handle_call({get_tree, static}, _, #mstate{rh = RH} = MState) ->
    {reply, RH, MState};
handle_call({get_min_latency_to, NodeNames}, _, #mstate{} = MState) ->
    {ok, SelfNode} = wm_self:get_node(),
    {reply, do_get_min_latency(SelfNode, NodeNames, {}, MState), MState};
handle_call({get_latency, SrcNode, DstNode}, _, #mstate{} = MState) ->
    {reply, do_get_latency(SrcNode, DstNode, MState), MState};
handle_call({get_neighbours, SortBy}, _, #mstate{rh = RH} = MState) ->
    Xs = get_my_neighbours([cluster, partition, node], SortBy, RH),
    {reply, Xs, MState};
handle_call({get_children, SortBy}, _, #mstate{} = MState) ->
    Xs = get_my_children([cluster, partition, node], SortBy, MState),
    {reply, Xs, MState};
handle_call({get_neightbour_addresses, SortBy}, _, #mstate{} = MState) ->
    Xs = do_get_neighbours_addresses(SortBy, MState),
    {reply, Xs, MState};
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
            Y ->
                ?LOG_ERROR("Cannot get my node name: ~p", [Y])
        end,
    case wm_conf:select_node(Name) of
        {error, E} ->
            ?LOG_ERROR("Could not get my node information: ~p", [E]),
            MState#mstate{mrole = none};
        {ok, Node} ->
            RoleIDs = wm_entity:get_attr(roles, Node),
            Roles = wm_conf:select(role, RoleIDs),
            RoleNames = [wm_entity:get_attr(name, Role) || Role <- Roles],
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
                 Cluster = do_get_my_subdiv(cluster, MState),
                 ?LOG_DEBUG("My cluster subdivision: ~p", [Cluster]),
                 do_make_rh(cluster, [Cluster], maps:new(), partition, MState);
             _ ->
                 Subdiv = do_get_my_subdiv(partition, MState),
                 ?LOG_DEBUG("My subdivision: ~p", [Subdiv]),
                 do_make_rh(element(1, Subdiv), [Subdiv], maps:new(), node, MState)
         end,
    ?LOG_DEBUG("RH: ~p", [RH]),
    MState#mstate{rh = RH};
do_make_rh_main(#mstate{} = MState) ->
    ?LOG_INFO("Not ready to make RH"),
    MState.

-spec get_props_res(tuple(), map()) -> map().
get_props_res(Entity, Map) when is_tuple(Entity) ->
    Map2 = add_properties(wm_entity:get_attr(properties, Entity), Map),
    add_resources(wm_entity:get_attr(resources, Entity), Map2).

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
            ClusterIDs = wm_entity:get_attr(clusters, Grid),
            Map2 =
                case wm_conf:select(cluster, ClusterIDs) of
                    [] ->
                        ?LOG_DEBUG("No cluster is found with ids: ~p", [ClusterIDs]),
                        Map1;
                    Clusters when is_list(Clusters) ->
                        do_make_rh(cluster, Clusters, Map1, Owner, MState)
                end,
            GridID = wm_entity:get_attr(id, Grid),
            maps:put({grid, GridID}, Map2, RH)
    end;
do_make_rh(cluster, [], RH, _, _) ->
    RH;
do_make_rh(cluster, [Cluster | T], RH, Owner, #mstate{} = MState) ->
    F = fun(Map) ->
           PartitionIDs = wm_entity:get_attr(partitions, Cluster),
           case wm_conf:select(partition, PartitionIDs) of
               [] ->
                   ?LOG_DEBUG("No partition found with ids: ~p", [PartitionIDs]),
                   Map;
               Parts ->
                   do_make_rh(partition, Parts, Map, cluster, MState)
           end
        end,
    Map1 = get_props_res(Cluster, maps:new()),
    ClusterId = wm_entity:get_attr(id, Cluster),
    RH2 = case Owner of
              grid ->
                  maps:put({cluster, ClusterId}, F(Map1), RH);
              _ ->
                  {ok, NodeName} = wm_self:get_sname(),
                  {ok, Host} = wm_self:get_host(),
                  {ok, Me} = wm_utils:get_my_vnode_name(long, atom, NodeName, Host),
                  Map2 =
                      case wm_entity:get_attr(manager, Cluster) of
                          Me ->
                              F(Map1);
                          _ ->
                              Subdiv = do_get_my_subdiv(cluster, MState),
                              case wm_entity:get_attr(id, Subdiv) of
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
           NodeIDs = wm_entity:get_attr(nodes, Partition),
           MapNs =
               case wm_conf:select(node, NodeIDs) of
                   [] ->
                       ?LOG_DEBUG("No nodes found with ids: ~p", [NodeIDs]),
                       Map;
                   Nodes ->
                       do_make_rh(node, Nodes, Map, partition, MState)
               end,
           PartIDs = wm_entity:get_attr(partitions, Partition),
           case wm_conf:select(partition, PartIDs) of
               [] ->
                   ?LOG_DEBUG("No partitions found with ids: ~p", [PartIDs]),
                   MapNs;
               Parts ->
                   do_make_rh(partition, Parts, MapNs, partition, MState)
           end
        end,
    Map1 = get_props_res(Partition, maps:new()),
    PartitionId = wm_entity:get_attr(id, Partition),
    RH2 = case Owner of
              X when X =:= cluster; X =:= partition ->
                  maps:put({partition, PartitionId}, F(Map1), RH);
              _ ->
                  {ok, NodeName} = wm_self:get_sname(),
                  {ok, Host} = wm_self:get_host(),
                  {ok, Me} = wm_utils:get_my_vnode_name(long, atom, NodeName, Host),
                  Map2 =
                      case wm_entity:get_attr(manager, Partition) of
                          Me ->
                              F(Map1);
                          _ ->
                              Subdiv = do_get_my_subdiv(partition, MState),
                              case wm_entity:get_attr(id, Subdiv) of
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
    NodeId = wm_entity:get_attr(id, Node),
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
    Name = wm_entity:get_attr(name, R),
    RMap = maps:new(),
    RMap2 = add_properties(wm_entity:get_attr(properties, R), RMap),
    RMap3 = add_resources(wm_entity:get_attr(resources, R), RMap2),
    Map2 = maps:put({resource, Name}, RMap3, Map),
    add_resources(T, Map2).

-spec append_id_to_binary(pos_integer(), binary()) -> binary().
append_id_to_binary(ID, Binary) ->
    <<Binary/binary, ID:(?BINARY_ID_BITS)/unsigned-integer>>.

-spec do_get_neighbours_addresses(atom(), #mstate{}) -> [node_address()].
do_get_neighbours_addresses(SortBy, #mstate{rh = RH}) ->
    %TODO sort the neightbours
    Neightbours = get_my_neighbours([cluster, partition, node], SortBy, RH),
    F = fun({EntityType, ID}) ->
           {ok, Entity} = wm_conf:select(EntityType, {id, ID}),
           case element(1, Entity) of
               node ->
                   wm_utils:get_address(Entity);
               X when X =:= cluster; X =:= partition; X =:= grid ->
                   wm_utils:get_address(
                       wm_entity:get_attr(manager, Entity))
           end
        end,
    [F(X) || X <- Neightbours].

get_my_neighbours(Filters, SortBy, RH) when is_list(Filters) ->
    %TODO sort the neightbours
    F = fun(Filter, Acc) -> [get_my_neighbours(Filter, SortBy, RH) | Acc] end,
    lists:flatten(
        lists:foldl(F, [], Filters));
get_my_neighbours(Filter, _, RH) ->
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

get_my_children(Filters, SortBy, #mstate{} = MState) when is_list(Filters) ->
    %TODO sort the children checking SortBy
    F = fun(Filter, Acc) -> [get_my_children(Filter, SortBy, MState) | Acc] end,
    lists:flatten(
        lists:foldl(F, [], Filters));
get_my_children(Filter, _, #mstate{mrole = Role, rh = RH} = MState) ->
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
                                        SubDivID = wm_entity:get_attr(id, SubDiv),
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
        case get_my_neighbours(Entity, unsorted, RH) of
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
        case get_my_neighbours(node, unsorted, RH) of
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
do_make_nl(X, #mstate{} = MState) ->
    ?LOG_INFO("No need to make NL for ~p", [X]),
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
    Latency = wm_latency:ping(NodeName, Trials),
    ?LOG_DEBUG("Measured latency for ~p: ~p microseconds", [Node, Latency]),
    %TODO Implement latency saving
    %TODO Rename latency to roundtrip
    ok.

-spec do_get_latency(#node{}, #node{}, #mstate{}) -> pos_integer().
do_get_latency(SrcNode, DstNode, #mstate{} = MState) ->
    X = maps:get(
            wm_entity:get_attr(id, SrcNode), MState#mstate.ct_map),
    Y = maps:get(
            wm_entity:get_attr(id, DstNode), MState#mstate.ct_map),
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
                Subdiv = wm_entity:get_attr(subdivision, Entity),
                ID = wm_entity:get_attr(subdivision_id, Entity),
                case wm_conf:select(Subdiv, {id, ID}) of
                    {error, Error} ->
                        ?LOG_DEBUG("Could not find ~p with id=~p: ~p", [Subdiv, ID, Error]),
                        not_found;
                    {ok, S} ->
                        S
                end;
            _ ->
                Entity
        end
    catch
        E1:E2 ->
            ?LOG_ERROR("Cannot get direct subdiv ~p: ~p", [E1, E2]),
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
    ?LOG_DEBUG("RH node ids: ~p", [NodeIDs]),
    Nodes = wm_conf:select(node, NodeIDs),
    case WithTemplates of
        false ->
            lists:filter(fun(X) -> wm_entity:get_attr(is_template, X) == false end, Nodes);
        true ->
            Nodes
    end;
do_get_tree_nodes(_, #mstate{rh = RH}) ->
    ?LOG_DEBUG("RH has not been constructed yet: ~p", [RH]),
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
        {error, not_found} ->  % assume cluster without parent
            Path1 = find_child_rh_path(ToNodeId, RH, []),
            Path2 = lists:filter(fun(X) -> X =/= FromNodeId end, Path1),
            Path3 = lists:reverse(Path2),
            Path3;
        {ok, ToNodeId} ->
            [ToNodeId];
        _ ->
            [Root] = maps:keys(RH), % RH should have only one root
            RootRH = maps:get(Root, RH),
            {true, NodeRH} = get_node_rh({Root, RootRH}, FromNodeId, {false, #{}}),
            Neighbours = lists:map(fun({X, _}) -> X end, maps:to_list(NodeRH)),
            CheckNeightbours =
                fun ({node, Id}) ->
                        {ok, Node} = wm_conf:select(node, {id, Id}),
                        wm_entity:get_attr(id, Node) == ToNodeId;
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

-spec get_node_rh({{atom(), string()}, map()}, node_id(), {boolean(), map()}) -> map().
get_node_rh({{Division, Id}, SubRH}, NodeId, {false, LastSubRH}) when Division =/= node ->
    {ok, DivisionEntity} = wm_conf:select(Division, {id, Id}),
    MgrName = wm_entity:get_attr(manager, DivisionEntity),
    {ok, Node} = wm_conf:select_node(MgrName),
    case wm_entity:get_attr(id, Node) of
        NodeId ->
            {true, LastSubRH};
        _ ->
            F = fun(P) -> get_node_rh(P, NodeId, {false, SubRH}) end,
            case lists:flatten(
                     lists:map(F, maps:to_list(SubRH)))
            of
                [] ->
                    {false, #{}};
                List ->
                    UniqueList = lists:usort(List), % remove duplicates
                    case lists:filter(fun({B, _}) -> B =:= true end, UniqueList) of
                        [] ->
                            {false, #{}};
                        [{true, RH}] ->
                            {true, RH}
                    end
            end
    end;
get_node_rh({{_, Id}, _}, NodeId, {false, LastSubRH}) when Id == NodeId ->
    {true, LastSubRH};
get_node_rh({{_, _}, SubRH}, NodeId, {false, LastSubRH}) ->
    F = fun(P, Acc) -> get_node_rh(P, NodeId, Acc) end,
    lists:foldl(F, {false, LastSubRH}, maps:to_list(SubRH));
get_node_rh({{_, _}, _}, _, {true, LastSubRH}) ->
    {true, LastSubRH}.

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
    MgrName = wm_entity:get_attr(manager, Entity),
    {ok, Node} = wm_conf:select_node(MgrName),
    case wm_entity:get_attr(id, Node) of
        NodeId ->
            true;
        OtherId ->
            {false, OtherId}
    end.

-spec get_parent_id(node_id()) -> {ok, node_id()} | {error, not_found}.
get_parent_id(NodeId) ->
    case wm_conf:select(node, {id, NodeId}) of
        {error, _} ->
            {error, not_found};
        {ok, Node} ->
            ParentName = wm_entity:get_attr(parent, Node),
            case wm_conf:select_node(ParentName) of
                {ok, Parent} ->
                    case wm_entity:get_attr(id, Parent) of
                        [] ->
                            {error, not_found};
                        ParentId ->
                            {ok, ParentId}
                    end;
                _ ->
                    {error, not_found}
            end
    end.

%% ============================================================================
%% Tests
%% ============================================================================

-ifdef(EUNIT).

-include_lib("eunit/include/eunit.hrl").

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

init_ct_test() ->
    MState = get_mock_ct(),
    RefCt =
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0, 0, 15, 66, 64, 0, 0, 0, 0,
          0, 0, 0, 0>>,
    ?LOG_DEBUG("~p", MState#mstate.ct),
    ?assert(MState#mstate.ct == RefCt).

get_value_from_cl_test() ->
    CT = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
           0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 7,
           0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
           0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1>>,
    ?assert(get_integer_by_pos(0, 0, 4, CT) == 0),
    ?assert(get_integer_by_pos(2, 1, 4, CT) == 8),
    ?assert(get_integer_by_pos(3, 3, 4, CT) == 72340172838076673).

search_path_test() ->
    % In this test a node id is also its name (for simplification),
    % grid, cluster and partition manager nodes have names/ids equals
    % to its subdivision id plus "_n0". All non-manager node names/ids
    % are formed as SUBDIVISION_ID plus "_nX", where X > 0.
    RH = #{{grid, "g1"} =>
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
                 {cluster, "c3"} => #{}}},
    SetParent =
        fun ("c1_n0", Node) ->
                wm_entity:set_attr([{parent, "g1_n0"}], Node);
            ("p11_n0", Node) ->
                wm_entity:set_attr([{parent, "c1_n0"}], Node);
            ("c2_n0", Node) ->
                wm_entity:set_attr([{parent, "g1_n0"}], Node);
            ("p21_n0", Node) ->
                wm_entity:set_attr([{parent, "c2_n0"}], Node);
            ("p21_n1", Node) ->
                wm_entity:set_attr([{parent, "p21_n0"}], Node);
            ("p21_n2", Node) ->
                wm_entity:set_attr([{parent, "p21_n0"}], Node);
            ("p211_n0", Node) ->
                wm_entity:set_attr([{parent, "p21_n0"}], Node);
            ("p211_n1", Node) ->
                wm_entity:set_attr([{parent, "p211_n0"}], Node);
            ("p211_n2", Node) ->
                wm_entity:set_attr([{parent, "p211_n0"}], Node);
            ("p211_n3", Node) ->
                wm_entity:set_attr([{parent, "p211_n0"}], Node);
            ("p2111_n0", Node) ->
                wm_entity:set_attr([{parent, "p211_n0"}], Node);
            ("p22_n0", Node) ->
                wm_entity:set_attr([{parent, "c2_n0"}], Node);
            ("p221_n0", Node) ->
                wm_entity:set_attr([{parent, "p22_n0"}], Node);
            ("p2211_n0", Node) ->
                wm_entity:set_attr([{parent, "p221_n0"}], Node);
            ("p22111_n0", Node) ->
                wm_entity:set_attr([{parent, "p2211_n0"}], Node);
            ("p22111_n1", Node) ->
                wm_entity:set_attr([{parent, "p22111_n0"}], Node);
            ("c3_n0", Node) ->
                wm_entity:set_attr([{parent, "g1_n0"}], Node);
            (_, Node) ->
                Node
        end,
    SelectById =
        fun (node, {id, Id}) ->
                Node = wm_entity:set_attr([{id, Id}, {name, Id}], wm_entity:new(node)),
                {ok, SetParent(Id, Node)};
            (SubDiv, {id, Id}) ->
                {ok, wm_entity:set_attr([{id, Id}, {name, Id}, {manager, Id ++ "_n0"}], wm_entity:new(SubDiv))}
        end,
    SelectByName = fun(NameIsAlsoId) -> SelectById(node, {id, NameIsAlsoId}) end,
    meck:new(wm_conf),
    meck:expect(wm_conf, select, SelectById),
    meck:expect(wm_conf, select_node, SelectByName),
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
    ?assertEqual([], find_rh_path("p211_n3", "c1_n0", RH)).

-endif.
