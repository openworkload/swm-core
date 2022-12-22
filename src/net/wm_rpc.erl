-module(wm_rpc).

-export([call/3, call/4, cast/3, cast/4]).

-include("../lib/wm_log.hrl").
-include("../lib/wm_entity.hrl").

%TODO: When DB does not exist we need to define default global values in a file
%TODO: Implement batch JSON-RPC calls
%TODO: Return JSON-RPC errors

-define(DEFAULT_CERT_DIR, "/opt/swm/spool/secure/node/").

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

-spec cast(atom(), fun(), list(), node_address()) -> {ok, any()} | {error, term()}.
cast(Module, Function, Args, FinalAddr = {_, _}) ->
    ?LOG_DEBUG("m=~p f=~p, a=~P, n=~p", [Module, Function, Args, 3, FinalAddr]),
    NextAddr = get_next_destination(FinalAddr),
    ?LOG_DEBUG("Next destination address: ~p", [NextAddr]),
    ConnArgs = get_connection_args(NextAddr),
    case wm_tcp_client:connect(ConnArgs) of
        {ok, Socket} ->
            Tag = wm_utils:uuid(v4),
            RPC = {cast, Module, Function, Args, Tag, FinalAddr},
            send_metrics_to_mon(NextAddr),
            wm_tcp_client:rpc(RPC, Socket),
            wm_tcp_client:disconnect(Socket);
        Error ->
            Error
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

-spec get_next_destination(node_address()) -> node_address().
get_next_destination(FinalAddr = {_, _}) ->
    ?LOG_DEBUG("Find next node when forwarding to ~p", [FinalAddr]),
    case wm_conf:is_my_address(FinalAddr) of
        true ->
            FinalAddr;
        false ->
            ?LOG_DEBUG("Address is not mine: ~p", [FinalAddr]),
            MyAddr = wm_conf:get_my_relative_address(FinalAddr),
            Neighbours = wm_topology:get_neighbours(nosort),
            case lists:any(fun(X) -> X =:= FinalAddr end, Neighbours) of
                true ->
                    FinalAddr;
                false ->
                    Children = wm_topology:get_children(nosort),
                    case lists:any(fun(Y) -> Y =:= FinalAddr end, Children) of
                        true ->
                            FinalAddr;
                        false ->
                            % The idea here is to find a path from final node back to the
                            % grid manager node. If one of the nodes in the path is the
                            % source node, then we just send the message along the path
                            % (to the node next in the path toward the destination node).
                            % Otherwise we send the message up to the parent.
                            case wm_conf:select_node(MyAddr) of
                                {ok, MyNode} ->
                                    MyNodeId = wm_entity:get(id, MyNode),
                                    case wm_conf:select_node(FinalAddr) of
                                        {ok, FinalNode} ->
                                            get_next_relative_destination(FinalNode, MyNodeId);
                                        {error, found_multiple, Nodes} ->
                                            % This scenario happens when partitions work on separate networks
                                            % with the same network address range. In this case we have more
                                            % than one compute nodes on different networks with same address.
                                            GetMyNode = fun(X) -> wm_entity:get(id, X) == MyNodeId end,
                                            case lists:filter(GetMyNode, Nodes) of
                                                [MyNode] when is_tuple(MyNode) ->
                                                    wm_conf:get_my_relative_address(FinalAddr);
                                                _ ->
                                                    wm_core:get_parent()
                                            end;
                                        _ ->
                                            wm_core:get_parent()
                                    end;
                                _ ->
                                    wm_core:get_parent()
                            end
                    end
            end
    end.

-spec get_next_relative_destination(#node{}, node_id()) -> node_address() | not_found.
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
