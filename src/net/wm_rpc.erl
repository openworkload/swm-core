-module(wm_rpc).

-export([call/3, call/4, cast/3, cast/4]).

-include("../lib/wm_log.hrl").
-include("../lib/wm_entity.hrl").
-include("../../include/wm_general.hrl").

%TODO: Implement batch JSON-RPC calls
%TODO: Return JSON-RPC errors

%% ============================================================================
%% API functions
%% ============================================================================

-spec call(module(), fun(), list()) -> term().
call(Module, Function, Args) ->
    case wm_utils:get_env("SWM_API_HOST") of
        undefined ->
            call(Module, Function, Args, {"localhost"});
        Host ->
            case wm_utils:get_env("SWM_API_PORT") of
                undefined ->
                    call(Module, Function, Args, Host);
                Port ->
                    call(Module, Function, Args, {Host, Port})
            end
    end.

-spec call(module(), fun(), list(), #node{} | atom()) -> term().
call(Module, Function, Args, Node) when is_tuple(Node) ->
    ?LOG_DEBUG("m=~p f=~p, a=~P, n=~p", [Module, Function, Args, 3, Node]),
    case wm_tcp_client:connect(get_connection_args(Node)) of
        {ok, Socket} ->
            RPC = {call, Module, Function, Args},
            Reply = wm_tcp_client:rpc(RPC, Socket),
            wm_tcp_client:disconnect(Socket),
            Reply;
        Error ->
            Error
    end;
call(Module, Function, Args, Node) ->
    case wm_conf:select_node(Node) of
        {error, need_maint} ->
            {error, not_found};
        {ok, NodeRec} ->
            ?MODULE:call(Module, Function, Args, NodeRec)
    end.

-spec cast(module(), fun(), list()) -> {ok, any()} | {error, term()}.
cast(Module, Function, Args) ->
    cast(Module, Function, Args, {localhost}).

-spec cast(atom(), fun(), list(), node_address()) -> ok | {error, term()}.
cast(Module, Function, Args, FinalAddr = {_, _}) ->
    ?LOG_DEBUG("m=~p f=~p, a=~P, n=~1000p", [Module, Function, Args, 3, FinalAddr]),
    case get_next_destination(FinalAddr) of
        not_found ->
            ?LOG_ERROR("Cannot cast ~p:~p, no route to ~p (parent unknown)", [Module, Function, FinalAddr]),
            {error, not_found};
        {error, Reason} = Error ->
            ?LOG_ERROR("Cannot cast ~p:~p to ~p: ~p", [Module, Function, FinalAddr, Reason]),
            Error;
        NextAddr = {_, _} ->
            ?LOG_DEBUG("Next destination address: ~p", [NextAddr]),
            ConnArgs = get_connection_args(NextAddr),
            case wm_tcp_client:connect(ConnArgs) of
                {ok, Socket} ->
                    Tag = wm_utils:uuid(v4),
                    RPC = {cast, Module, Function, Args, Tag, FinalAddr},
                    send_metrics_to_mon(NextAddr),
                    wm_tcp_client:rpc(RPC, Socket),
                    ok = wm_tcp_client:disconnect(Socket),
                    ok;
                Error ->
                    Error
            end
    end.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec send_metrics_to_mon(node_address()) -> ok.
send_metrics_to_mon(DestAddr = {_, _}) ->
    case wm_conf:select_node(DestAddr) of
        {ok, Rec} ->
            DestName = wm_utils:node_to_fullname(Rec),
            wm_mon:update(msg_route, {node(), DestName});
        _ ->
            ok
    end.

-spec get_connection_args({localhost} | node_address() | {#node{}, pos_integer()} | #node{}) -> map().
get_connection_args({localhost}) ->
    DefaultCert = filename:join([?DEFAULT_CERT_DIR, "cert.pem"]),
    DefaultKey = filename:join([?DEFAULT_CERT_DIR, "key.pem"]),
    Cert = wm_conf:g(node_cert, {DefaultCert, string}),
    Key = wm_conf:g(node_key, {DefaultKey, string}),
    ConnArgs = maps:put(cert, Cert, maps:new()),
    maps:put(key, Key, ConnArgs);
get_connection_args({Host, Port}) when is_list(Host) ->
    DefaultCert = filename:join([?DEFAULT_CERT_DIR, "cert.pem"]),
    DefaultKey = filename:join([?DEFAULT_CERT_DIR, "key.pem"]),
    Cert = wm_conf:g(node_cert, {DefaultCert, string}),
    Key = wm_conf:g(node_key, {DefaultKey, string}),
    ConnArgs1 = maps:put(server, Host, maps:new()),
    ConnArgs2 = maps:put(port, Port, ConnArgs1),
    ConnArgs3 = maps:put(cert, Cert, ConnArgs2),
    maps:put(key, Key, ConnArgs3);
get_connection_args({Node, Port}) when is_tuple(Node) ->
    Host = wm_entity:get(host, Node),
    get_connection_args({Host, Port});
get_connection_args(Node) when is_tuple(Node) ->
    Host = wm_entity:get(host, Node),
    Port = wm_entity:get(api_port, Node),
    DefaultCert = filename:join([?DEFAULT_CERT_DIR, "cert.pem"]),
    DefaultKey = filename:join([?DEFAULT_CERT_DIR, "key.pem"]),
    Cert = wm_conf:g(node_cert, {DefaultCert, string}),
    Key = wm_conf:g(node_key, {DefaultKey, string}),
    ConnArgs1 = maps:put(server, Host, maps:new()),
    ConnArgs2 = maps:put(port, Port, ConnArgs1),
    ConnArgs3 = maps:put(cert, Cert, ConnArgs2),
    maps:put(key, Key, ConnArgs3).

-spec is_local_address(node_address()) -> boolean().
is_local_address({"localhost", _}) ->
    true;
is_local_address(_) ->
    false.

%% True when this node has the SSH reverse tunnel to SkyPort on
%% localhost:parent_api_port (cloud job main). Cloud computes do not.
-spec has_reverse_tunnel_to_parent() -> boolean().
has_reverse_tunnel_to_parent() ->
    case wm_self:get_node() of
        {ok, #node{gateway = Gw} = Node} ->
            case wm_utils:is_cloud_node(Node) of
                true ->
                    Gw =/= [];
                false ->
                    false
            end;
        _ ->
            %% Early boot on job main: parent is the tunnel endpoint.
            case wm_core:get_parent() of
                {"localhost", _} ->
                    true;
                _ ->
                    false
            end
    end.

%% Resolve parent to a reachable VNet address (prefer host IP over sname).
-spec parent_hop_for_tunnel() -> node_address() | not_found.
parent_hop_for_tunnel() ->
    case wm_core:get_parent() of
        not_found ->
            not_found;
        ParentAddr = {Host, _Port} ->
            case wm_conf:select_node(ParentAddr) of
                {ok, ParentNode} ->
                    {wm_entity:get(host, ParentNode), wm_entity:get(api_port, ParentNode)};
                _ ->
                    case wm_conf:select_node(Host) of
                        {ok, ParentNode} ->
                            {wm_entity:get(host, ParentNode), wm_entity:get(api_port, ParentNode)};
                        _ ->
                            ParentAddr
                    end
            end
    end.

%% SkyPort (non-cloud) must not TCP-connect to a cloud node's private host.
%% Direct connect is allowed only to that node's public gateway (or when the
%% sender is also a cloud node on the same VNet).
-spec direct_connect_ok(node_address()) -> boolean().
direct_connect_ok(FinalAddr) ->
    case {wm_self:get_node(), wm_conf:select_node(FinalAddr)} of
        {{ok, Me}, {ok, Dest}} ->
            case {wm_utils:is_cloud_node(Me), wm_utils:is_cloud_node(Dest)} of
                {false, true} ->
                    case wm_entity:get(gateway, Dest) of
                        [] ->
                            false;
                        Gw ->
                            FinalAddr =:= {Gw, wm_entity:get(api_port, Dest)}
                    end;
                _ ->
                    true
            end;
        _ ->
            true
    end.

-spec route_toward(node_address()) -> node_address() | not_found | {error, not_found}.
route_toward(FinalAddr) ->
    case wm_self:get_node() of
        {ok, MyNode} ->
            route_toward_from(FinalAddr, wm_entity:get(id, MyNode));
        _ ->
            wm_core:get_parent()
    end.

-spec get_next_destination(node_address()) -> node_address() | not_found | {error, not_found}.
get_next_destination(FinalAddr = {"localhost", Port}) ->
    ParentPort = wm_conf:g(parent_api_port, {?DEFAULT_PARENT_API_PORT, integer}),
    case Port == ParentPort of
        true ->
            case has_reverse_tunnel_to_parent() of
                true ->
                    %% Job main: connect to the local reverse-tunnel endpoint.
                    FinalAddr;
                false ->
                    %% Cloud compute: no local tunnel — hop via job main, which
                    %% forwards into its tunnel. FinalAddr stays localhost so
                    %% main's session continues toward SkyPort.
                    Next = parent_hop_for_tunnel(),
                    ?LOG_DEBUG("No local parent tunnel; hop via ~p toward ~p", [Next, FinalAddr]),
                    Next
            end;
        false ->
            get_next_destination_general(FinalAddr)
    end;
get_next_destination(FinalAddr = {_, _}) ->
    get_next_destination_general(FinalAddr).

-spec get_next_destination_general(node_address()) -> node_address() | not_found | {error, not_found}.
get_next_destination_general(FinalAddr = {_, _}) ->
    ?LOG_DEBUG("Find next node when forwarding to ~p", [FinalAddr]),
    case wm_conf:is_my_address(FinalAddr) of
        true ->
            FinalAddr;
        false ->
            ?LOG_DEBUG("Address is not mine: ~p", [FinalAddr]),
            MyAddr = wm_conf:get_my_relative_address(FinalAddr),
            Neighbours = wm_topology:get_my_neighbour_addresses(),
            case lists:any(fun(X) -> X =:= FinalAddr end, Neighbours) andalso direct_connect_ok(FinalAddr) of
                true ->
                    FinalAddr;
                false ->
                    Children = wm_topology:get_children(),
                    case lists:any(fun(Y) -> Y =:= FinalAddr end, Children) andalso direct_connect_ok(FinalAddr) of
                        true ->
                            FinalAddr;
                        false ->
                            % The idea here is to find a path from final node back to the
                            % grid manager node. If one of the nodes in the path is the
                            % source node, then we just send the message along the path
                            % (to the node next in the path toward the destination node).
                            % Otherwise we send the message up to the parent.
                            %
                            % When MyAddr is localhost, that is SkyPort's reverse-tunnel
                            % identity toward cloud nodes — not proof that FinalAddr is
                            % locally reachable (cloud compute hosts are private).
                            case is_local_address(MyAddr) of
                                true ->
                                    Next = route_toward(FinalAddr),
                                    ?LOG_DEBUG("Tunnel-relative self; next hop toward ~p: ~p", [FinalAddr, Next]),
                                    Next;
                                false ->
                                    case wm_conf:select_node(MyAddr) of
                                        {ok, MyNode} ->
                                            route_toward_from(FinalAddr, wm_entity:get(id, MyNode));
                                        {error, not_found} ->
                                            wm_core:get_parent()
                                    end
                            end
                    end
            end
    end.

-spec route_toward_from(node_address(), string()) -> node_address() | not_found | {error, not_found}.
route_toward_from(FinalAddr, MyNodeId) ->
    case wm_conf:select_node(FinalAddr) of
        {ok, FinalNode} ->
            get_next_relative_destination(FinalNode, MyNodeId);
        {error, found_multiple, Nodes} ->
            % Partitions on separate networks can share the same private address range.
            GetMyNode = fun(X) -> wm_entity:get(id, X) == MyNodeId end,
            case lists:filter(GetMyNode, Nodes) of
                [MyNode] when is_tuple(MyNode) ->
                    wm_conf:get_my_relative_address(FinalAddr);
                _ ->
                    wm_core:get_parent()
            end;
        _ ->
            wm_core:get_parent()
    end.

-spec get_next_relative_destination(#node{}, string()) -> node_address() | not_found.
get_next_relative_destination(FinalNode, MyNodeId) ->
    FinalNodeId = wm_entity:get(id, FinalNode),
    case wm_topology:on_path(MyNodeId, FinalNodeId) of
        {ok, NodeId} ->
            {ok, Node} = wm_conf:select(node, {id, NodeId}),
            {ok, SelfNode} = wm_conf:select(node, {id, MyNodeId}),
            wm_conf:get_relative_address(Node, SelfNode);
        _ ->
            wm_core:get_parent()
    end.
