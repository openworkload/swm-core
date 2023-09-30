-module(wm_core).

-behaviour(gen_server).

-export([start_link/1, get_parent/0, start_slave/3, has_malfunction/1, allocate_port/0, get_my_gateway_address/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(FLOATING_PORT_BEGIN, 50000).
-define(FLOATING_PORT_LAST, 50000).
-define(FLOATING_PORT_END, 51000).

-record(mstate,
        {sups,                     % map: service_id --> supervisor_pid
         mon_nodes,                % map: {host, port} --> milliseconds
         pstack = [],              % parents stack
         boot_parent_sname :: string(),
         boot_parent_host :: string(),
         boot_parent_port = 0 :: integer(),
         spool,
         root,
         mst_id}).

%% ============================================================================
%% API
%% ============================================================================

%% @doc Start core service
-spec start_link(term()) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Get current parent node full name
-spec get_parent() -> node_address() | not_found.
get_parent() ->
    wm_utils:protected_call(?MODULE, get_parent, none).

%% @doc Start slave node on the same host (parent or simulation node)
-spec start_slave(atom(), list(), list()) -> {ok, term()} | {error, term()}.
start_slave(ShortName, SlaveArgs, AppArgs) ->
    do_start_slave(ShortName, SlaveArgs, AppArgs).

%% @doc Return value associated with failure type or not_found if not set
-spec has_malfunction(atom()) -> term() | not_found.
has_malfunction(FailureType) ->
    wm_utils:protected_call(?MODULE, {has_malfunction, FailureType}, not_found).

%% @doc Return allocated port number
-spec allocate_port() -> number().
allocate_port() ->
    wm_utils:protected_call(?MODULE, allocate_port, 0).

%% @doc Try to get self node gateway property
get_my_gateway_address() ->
    %%TODO: move to wm_self
    case wm_self:get_node() of
        {ok, MyNode} ->
            MyGateway = wm_entity:get(gateway, MyNode),
            MyPort = wm_entity:get(api_port, MyNode),
            {MyGateway, MyPort};
        _ ->
            []
    end.

%% ============================================================================
%% Callbacks
%% ============================================================================

init(Args) ->
    ?LOG_INFO("Load core service"),
    wm_state:enter(loading),
    MState1 = parse_args(Args, #mstate{sups = maps:new()}),
    process_flag(trap_exit, true),
    MState2 = fill_pstack(MState1),
    subscribe_me(),
    wm_conf:set_node_state(power, up, node()),
    add_parent_to_pinger(MState2),
    check_required_mode(),
    set_default_nodes_states(),
    ?LOG_DEBUG("Core state: ~10000p", [MState2]),
    start_heavy_works(Args, MState2).

handle_call(allocate_port, _, #mstate{} = MState) ->
    {reply, do_allocate_port(), MState};
handle_call({has_malfunction, FailureType}, _, #mstate{} = MState) ->
    {reply, do_has_malfunction(FailureType), MState};
handle_call(get_parent, _From, MState) ->
    {reply, wm_parent:get_current(MState#mstate.pstack), #mstate{} = MState};
handle_call(_Msg, _From, #mstate{} = MState) ->
    ?LOG_ERROR("Unknown request: ~p (from ~p)", [_Msg, _From]),
    {reply, {error, unknown_handle}, MState}.

handle_cast({event, EventType, EventData}, #mstate{} = MState) ->
    {noreply, handle_event(EventType, EventData, MState)};
handle_cast({reload_services}, MState) ->
    ?LOG_INFO("Reload services"),
    ask_root_sup_restart_all(),
    {noreply, MState}.

handle_info(Info, MState) ->
    ?LOG_DEBUG("Not handling the info message: ~p", [Info]),
    {noreply, MState}.

terminate(Reason, MState) ->
    wm_utils:terminate_msg(?MODULE, Reason),
    wm_works:disable(),
    wm_pinger:del(
        wm_parent:get_current(MState#mstate.pstack)).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], MState) ->
    MState;
parse_args([{spool, Spool} | T], MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{root, Root} | T], MState) ->
    parse_args(T, MState#mstate{root = Root});
parse_args([{parent_sname, Parent} | T], MState) ->
    parse_args(T, MState#mstate{boot_parent_sname = Parent});
parse_args([{parent_host, Host} | T], MState) ->
    parse_args(T, MState#mstate{boot_parent_host = Host});
parse_args([{parent_port, Port} | T], MState) ->
    parse_args(T, MState#mstate{boot_parent_port = Port});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

subscribe_me() ->
    Me = node(),
    wm_event:subscribe(topology_constructed, Me, ?MODULE),
    wm_event:subscribe(reconfigured_node, Me, ?MODULE),
    wm_event:subscribe(nodeup, Me, ?MODULE),
    wm_event:subscribe(nodedown, Me, ?MODULE),
    wm_event:subscribe(schema_updated, Me, ?MODULE),
    wm_event:subscribe(need_tabs_update, Me, ?MODULE),
    wm_event:subscribe(wm_mst_done, Me, ?MODULE),
    wm_event:subscribe(new_node_state, Me, ?MODULE),
    wm_event:subscribe(new_parent, Me, ?MODULE).

load_services(MState, Args) ->
    ?LOG_DEBUG("Load services"),
    {ok, NodeName} = wm_self:get_sname(),
    {ok, Host} = wm_self:get_host(),
    case wm_utils:get_my_vnode_name(short, string, NodeName, Host) of
        {ok, SName} ->
            ?LOG_DEBUG("My short node name is ~s", [SName]),
            case wm_conf:select_node(SName) of
                {error, need_maint} ->
                    ?LOG_DEBUG("Could not load services, maintanance is required"),
                    MState2 = start_modules([wm_admin], Args, 0, MState),
                    {error, MState2};
                {ok, Node} ->
                    ?LOG_INFO("My node: ~10000p", [Node]),
                    RoleIDs = wm_entity:get(roles, Node),
                    ?LOG_INFO("My role IDs: ~p", [RoleIDs]),
                    Roles = wm_conf:select(role, RoleIDs),
                    ?LOG_INFO("My roles: ~10000p", [Roles]),
                    ServiceIDs = [wm_entity:get(services, Role) || Role <- Roles],
                    ?LOG_INFO("My service IDs: ~w", [ServiceIDs]),
                    Services = wm_conf:select(service, lists:flatten(ServiceIDs)),
                    NewState = start_services_suspended(Services, Args, MState),
                    resume_services(Services),
                    set_local_node_state(Node),
                    {ok, NewState}
            end;
        {error, E2} ->
            ?LOG_ERROR("Could not get my short node name: ~p", [E2]),
            {error, MState}
    end.

start_services_suspended([], _, #mstate{} = MState) ->
    MState;
start_services_suspended([Service | T], Args, #mstate{} = MState) ->
    ServiceModules = wm_entity:get(modules, Service),
    AtomModules = [list_to_atom(X) || X <- ServiceModules],
    ServiceName = wm_entity:get(name, Service),
    ServiceID = wm_entity:get(id, Service),
    ?LOG_INFO("Start modules for service ~p: ~p (ID=~p)", [ServiceName, AtomModules, ServiceID]),
    MState2 = start_modules(AtomModules, Args, ServiceID, MState),
    [ok = sys:suspend(X) || X <- AtomModules],
    start_services_suspended(T, Args, MState2).

resume_services([]) ->
    ok;
resume_services([Service | T]) ->
    ServiceModules = wm_entity:get(modules, Service),
    AtomModules = [list_to_atom(X) || X <- ServiceModules],
    ?LOG_DEBUG("Resume modules: ~p", [AtomModules]),
    [ok = sys:resume(M) || M <- AtomModules],
    resume_services(T).

handle_event(wm_mst_done, {ID, Name}, MState) when ID == MState#mstate.mst_id ->
    ?LOG_DEBUG("Parent assistant is chosen: ~p", [Name]),
    case node() of
        Name ->
            start_parent(MState);
        _ ->
            MState
    end;
handle_event(new_boot_info, BootInfo, MState) ->
    ?LOG_DEBUG("New boot info: ~p", [BootInfo]),
    set_boot_info(BootInfo, MState);
handle_event(new_parent, {ParentName, Port}, MState) ->
    ?LOG_DEBUG("New parent is announced: ~p", [ParentName]),
    add_parent({ParentName, Port}, MState);
handle_event(nodeup, {AllocState, NodeName}, MState) ->
    ?LOG_DEBUG("New node power state: ~p is UP now (~p)", [NodeName, AllocState]),
    wm_conf:set_node_state(power, up, NodeName),
    wm_conf:set_node_state(alloc, AllocState, NodeName),
    handle_maint_state(AllocState, NodeName, MState),
    case wm_parent:get_current(MState#mstate.pstack) of
        not_found ->  % assume this is a grid manager node
            ?LOG_DEBUG("Parent will not be notified about state change (not set): ~p", [NodeName]);
        Parent ->
            ?LOG_DEBUG("Notify parent (~p) about node ~p state change: ~p", [Parent, NodeName, AllocState]),
            wm_api:cast_self({event, nodeup, {AllocState, NodeName}}, [Parent])
    end,
    MState;
handle_event(nodedown, {AllocState, NodeName}, MState) ->
    ?LOG_DEBUG("New node power state: ~p is DOWN now", [NodeName]),
    wm_conf:set_node_state(power, down, NodeName),
    wm_conf:set_node_state(alloc, AllocState, NodeName),
    MState2 = ensure_parent_alive(NodeName, MState),
    Parent = wm_parent:get_current(MState2#mstate.pstack),
    wm_api:cast_self({event, nodedown, {AllocState, NodeName}}, [Parent]),
    MState2;
handle_event(started_slave, Node, MState) ->
    ?LOG_DEBUG("Received event: virtual node ~p has been spawned", [Node]),
    wm_conf:set_node_state(power, up, Node),
    wm_pinger:add(
        wm_utils:get_address(Node)),
    MState;
handle_event(stopped_slave, Node, MState) ->
    ?LOG_DEBUG("Received event: virtual node ~p has been stopped", [Node]),
    wm_conf:set_node_state(power, down, Node),
    wm_pinger:del(
        wm_utils:get_address(Node)),
    MState;
handle_event(new_node_state, {Node, NodeState}, MState) ->
    ?LOG_DEBUG("Received event: node ~p state now is ~p", [Node, NodeState]),
    case NodeState of
        stopped ->
            wm_conf:set_node_state(power, down, Node);
        _ ->
            wm_conf:set_node_state(power, up, Node)
    end,
    wm_conf:set_node_state(alloc, NodeState, Node),
    Parent = wm_parent:get_current(MState#mstate.pstack),
    wm_api:cast_self({event, new_node_state, {Node, NodeState}}, [Parent]),
    MState;
handle_event(need_tabs_update, {Node, Tabs}, MState) when Node =/= node() ->
    ?LOG_DEBUG("Received event: node ~p needs tabs update: ~p", [Node, Tabs]),
    wm_conf:propagate_config(Tabs, Node),
    MState;
handle_event(reconfigured_node, Nodes, MState) when is_list(Nodes) ->
    ?LOG_DEBUG("Received event: nodes ~p have been reconfigured", [Nodes]),
    wm_api:cast_self(reload_services, Nodes),
    MState;
handle_event(schema_updated, Node, MState) ->
    case wm_parent:get_current(MState#mstate.pstack) of
        {_, _} ->
            ?LOG_DEBUG("Received event: schema updated on ~p", [Node]),
            Me = node(),
            case Node of
                Me ->
                    ChildrenNodes = wm_conf:get_nodes_with_state({state_power, up}),
                    NodeNames = wm_utils:nodes_to_names(ChildrenNodes),
                    ?LOG_DEBUG("Children nodes: ~p", [NodeNames]),
                    wm_api:cast_self(reload_services, NodeNames);
                _ ->
                    Parent = wm_parent:get_current(MState#mstate.pstack),
                    wm_conf:pull_async(Parent)
            end;
        _ ->
            ok
    end,
    MState;
handle_event(topology_constructed, _, MState) ->
    add_children_to_pinger(),
    MState;
handle_event(OtherType, EventData, MState) ->
    ?LOG_DEBUG("Received unknown event: ~p data=~p", [OtherType, EventData]),
    MState.

set_default_nodes_states() ->
    ?LOG_INFO("Set default node states"),
    NodesUp = wm_conf:get_nodes_with_state({state_power, up}),
    NodesDown = wm_conf:get_nodes_with_state({state_power, down}),
    L = length(NodesUp) + length(NodesDown),
    ?LOG_DEBUG("Set default node states for ~p nodes", [L]),
    F3 = fun (#node{is_template = true}) ->
                 ok;
             (Node) ->
                 case wm_self:is_local_node(Node) of
                     true ->
                         set_local_node_state(Node);
                     false ->
                         wm_conf:update(
                             wm_entity:set([{state_power, down}, {state_alloc, offline}], Node))
                 end
         end,
    [F3(X) || X <- NodesDown ++ NodesUp].

-spec set_local_node_state(#node{}) -> ok.
set_local_node_state(Node) ->
    ?LOG_DEBUG("Set local node state"),
    case wm_self:has_role("compute") of
        true ->
            wm_conf:update(
                wm_entity:set([{state_power, up}, {state_alloc, idle}], Node));
        false ->
            wm_conf:update(
                wm_entity:set([{state_power, up}, {state_alloc, offline}], Node))
    end.

add_children_to_pinger() ->
    case wm_self:get_node() of
        {ok, #node{id = NodeId} = MyNode} ->
            ChildrenNodes = wm_topology:get_children_nodes(NodeId),
            NodeNames = [wm_entity:get(name, Node) || Node <- ChildrenNodes],
            ?LOG_DEBUG("Children nodes to ping: ~10000p", [NodeNames]),
            Add = fun(ChildNode) ->
                     Addr = wm_conf:get_relative_address(ChildNode, MyNode),
                     wm_pinger:add(Addr)
                  end,
            lists:map(Add, ChildrenNodes);
        Error ->
            ?LOG_ERROR("Cannot get my node, no nodes will be pinged"),
            Error
    end.

ensure_parent_alive(NodeName, MState) ->
    case wm_parent:get_current(MState#mstate.pstack) of
        NodeName ->
            Addresses = wm_topology:get_my_neighbour_addresses(),
            {ok, MST_ID} = wm_factory:new(mst, [], Addresses),
            MState#mstate{mst_id = MST_ID};
        _ ->
            MState
    end.

add_parent({_, 0}, #mstate{} = MState) ->
    MState;
add_parent({"", _}, #mstate{} = MState) ->
    MState;
add_parent(not_found, #mstate{} = MState) ->
    MState;
add_parent({ParentHost, ParentPort}, #mstate{} = MState) ->
    ?LOG_DEBUG("Add new parent to pstack: ~p:~p", [ParentHost, ParentPort]),
    case wm_parent:get_current(MState#mstate.pstack) of
        not_found ->
            monitor_parent(ParentHost, ParentPort, MState);
        {ParentHost, ParentPort} ->
            ?LOG_DEBUG("Don't add parent, it is already in the pstack"),
            MState;
        OldAddr ->
            ?LOG_DEBUG("Stop monitoring and subscription for ~p", [OldAddr]),
            wm_pinger:del(OldAddr),
            monitor_parent(ParentHost, ParentPort, MState)
    end;
add_parent(ParentShortName, #mstate{} = MState) when is_list(ParentShortName) ->
    ?LOG_DEBUG("Add new parent to pstack by its short name: ~p", [ParentShortName]),
    case wm_conf:select_node(ParentShortName) of
        {ok, ParentTuple} ->
            ParentHost = wm_entity:get(host, ParentTuple),
            ParentPort = wm_entity:get(api_port, ParentTuple),
            add_parent({ParentHost, ParentPort}, MState);
        {error, _} ->
            ?LOG_DEBUG("Parent not found (will not be added): ~p", [ParentShortName]),
            MState
    end.

do_start_slave(ShortName, SlaveArgs, AppArgs) ->
    Host = wm_utils:get_my_fqdn(),
    ?LOG_DEBUG("Starting new node ~s@~s: erl~s", [ShortName, Host, SlaveArgs]),
    case slave:start(Host, ShortName, SlaveArgs, self(), "erl") of
        {ok, Node} ->
            wm_event:announce(started_slave, Node),
            Pid = spawn(Node, wm_root_sup, start_slave, [AppArgs]),
            ?LOG_DEBUG("Slave node ~p has been spawned (supervisor: ~p)", [Node, Pid]),
            {ok, Node};
        {error, Reason} ->
            error_logger:error_msg(Reason),
            {error, Reason}
    end.

start_parent(MState) ->
    ?LOG_DEBUG("Lets start a new parent"),
    ParentStr = wm_parent:get_current(MState#mstate.pstack),
    ParentParts = string:tokens(ParentStr, "@"),
    OldParentName = hd(ParentParts),
    Suffix = "new1", %FIXME Imcrement index each time when new parent is started
    NewParentName = OldParentName ++ Suffix,
    {ok, MyNode} = wm_self:get_node(),
    MyPort = wm_entity:get(api_port, MyNode),
    Port = do_allocate_port(),
    add_parent_to_db(OldParentName, NewParentName, Port),
    AppArgs =
        [{spool, MState#mstate.spool},
         {boot_type, clean},
         {printer, file},
         {parent_sname, atom_to_list(node())},
         {parent_port, MyPort},
         {root, MState#mstate.root},
         {api_port, Port},
         {sname, NewParentName}],
    SlaveArgs = get_parent_slave_args(),
    FullName = lists:flatten(NewParentName ++ "@" ++ tl(ParentParts)),
    ?LOG_INFO("Start new parent: ~p", [NewParentName]),
    ?LOG_DEBUG("New parent app args: ~p", [AppArgs]),
    ?LOG_DEBUG("New parent node args: ~p", [SlaveArgs]),
    case do_start_slave(NewParentName, SlaveArgs, AppArgs) of
        {ok, _} ->
            wm_event:announce(new_parent, {FullName, Port}),
            wm_event:announce_neighbours(new_parent, {FullName, Port});
        {error, Reason} ->
            ?LOG_ERROR("Cannot start ~p:~p ~p", [FullName, Port, Reason]),
            wm_state:enter(maint)
    end,
    MState.

add_parent_to_db(OldParentName, NewParentName, Port) ->
    {ok, Node1} = wm_conf:select_node(OldParentName),
    NewID = rand:uniform(1000) + 100, %FIXME we should assign some unique ID (how to get unique one?)
    Node2 = wm_entity:set({id, NewID}, Node1),
    Node3 = wm_entity:set({name, NewParentName}, Node2),
    Node4 = wm_entity:set({api_port, Port}, Node3),
    Node5 = wm_entity:set({revision, 0}, Node4),
    Node6 = wm_entity:set({host, wm_self:get_host()}, Node5),
    case wm_conf:select_node(NewParentName) of
        {ok, ExistingNode} ->
            wm_conf:delete(ExistingNode);
        _ ->
            ok
    end,
    wm_conf:update(Node6),
    add_parent_to_subdiv(Node6).

add_parent_to_subdiv(Node) ->
    FullName = wm_utils:node_to_fullname(Node),
    {ok, SelfNode} = wm_self:get_node(),
    SubDiv1 = wm_topology:get_direct_subdiv(SelfNode),
    SubDiv2 = wm_entity:set({manager, FullName}, SubDiv1),
    wm_conf:update(SubDiv2).

get_parent_slave_args() ->
    %TODO Make these parameters configurable
    AppConf = wm_utils:get_env("SWM_SYS_CONFIG"),
    Config = "'" ++ AppConf ++ "'",
    Boot = " -boot start_sasl -config " ++ Config,
    Hidden = " -hidden",
    %SaslLogDir = "\"/opt/swm/spool-sim/" ++ FullNodeName ++ "/log/sasl/\"",
    %SaslConf = " -sasl errlog_type error",
    Pa = " -pa " ++ wm_utils:get_module_dir(wm_root_sup),
    E = " -env DISPLAY " ++ wm_self:get_host() ++ ":0 ",
    RSH = " -rsh ssh",
    Cookie = " -setcookie " ++ atom_to_list(erlang:get_cookie()),
    Extra = " -eval 'application:ensure_all_started(folsom)'",
    Boot ++ Hidden ++ Pa ++ E ++ RSH ++ Cookie ++ Extra.

do_allocate_port() ->
    NextAfterEnd = wm_conf:g(floating_port_end, {?FLOATING_PORT_END, integer}) + 1,
    NextPort = wm_conf:g(floating_port_last, {?FLOATING_PORT_LAST, integer}) + 1,
    case NextPort of
        NextAfterEnd ->
            ?LOG_DEBUG("No free port is in the range, lets check deallocated ones"),
            case get_free_deallocated_ports() of
                [] ->
                    ?LOG_ERROR("No free port available, please increase port range"),
                    0;
                FreePorts ->
                    [FreePort | FreePortsRest] = FreePorts,
                    set_free_deallocated_ports(FreePortsRest),
                    FreePort
            end;
        Port ->
            wm_conf:set_global(floating_port_last, Port),
            Port
    end.

deallocate_port(Port) when is_integer(Port) ->
    LastPort = wm_conf:g(floating_port_last, {?FLOATING_PORT_LAST, integer}),
    FreePorts = get_free_deallocated_ports(),
    PortBegin = wm_conf:g(floating_port_begin, {?FLOATING_PORT_BEGIN, integer}),
    case Port of
        LastPort ->
            case Port + 1 of
                PortBegin ->
                    ?LOG_ERROR("Cannot deallocate port ~p (out of range)", [Port]);
                _ ->
                    wm_conf:set_global(floating_port_last, Port - 1)
            end;
        _PortFromMiddleOfRange ->
            FreePorts2 =
                case lists:any(fun(X) -> X =:= Port end, FreePorts) of
                    true ->
                        FreePorts;
                    _ ->
                        [Port | FreePorts]
                end,
            set_free_deallocated_ports(FreePorts2)
    end.

get_free_deallocated_ports() ->
    FreePortsStr = wm_conf:g(floating_port_free, {"", string}),
    [list_to_integer(P) || P <- string:tokens(FreePortsStr, ",")].

set_free_deallocated_ports(Ports) ->
    Ports2 = [integer_to_list(X) || X <- Ports],
    wm_conf:set_global(floating_port_free, lists:flatten(Ports2)).

ask_root_sup_restart_all() ->
    Msg = {restart_all, self()},
    ?LOG_DEBUG("Send message to the restarting process: ~p", [Msg]),
    wm_restarter ! Msg.

do_has_malfunction(FailureType) ->
    case wm_self:get_node() of
        {error, _} ->
            not_found;
        {ok, Node} ->
            MfsIDs = wm_entity:get(malfunctions, Node),
            Mfs = wm_conf:select(malfunction, MfsIDs),
            Failures = lists:flatten([wm_entity:get(failures, X) || X <- Mfs]),
            case lists:keysearch(FailureType, 1, Failures) of
                false ->
                    not_found;
                {value, {FailureType, Value}} ->
                    ?LOG_DEBUG("Controlled failure found: {~p,~p}", [FailureType, Value]),
                    Value
            end
    end.

check_required_mode() ->
    case wm_utils:get_env("SWM_MODE") of
        "MAINT" ->
            wm_state:enter(maint);
        _ ->
            ok
    end.

start_modules(Modules, Args, ID, MState) when is_list(Modules) ->
    case lists:filter(fun(X) -> wm_utils:module_exists(X) == false end, Modules) of
        [] ->
            ?LOG_DEBUG("Load modules: ~p", [Modules]),
            case wm_sup:start_link({Modules, Args}) of
                {ok, SupPid} ->
                    Sups = maps:put(ID, SupPid, MState#mstate.sups),
                    MState#mstate{sups = Sups};
                {error, shutdown} ->
                    ?LOG_ERROR("Cannot start module: ~p", [Modules]),
                    MState
            end;
        List ->
            ?LOG_ERROR("~p modules were not found (out of ~p)", [length(List), length(Modules)]),
            MState
    end.

monitor_parent(ParentHost, ParentPort, MState) ->
    Address = {ParentHost, ParentPort},
    wm_pinger:del(Address),
    NewPStack = [Address | lists:delete(Address, MState#mstate.pstack)],
    ?LOG_DEBUG("New pstack: ~p", [NewPStack]),
    MState#mstate{pstack = NewPStack}.

fill_pstack(#mstate{} = MState) ->
    {ok, SName} = wm_self:get_sname(),
    List =
        wm_parent:find_my_parents(MState#mstate.boot_parent_sname,
                                  MState#mstate.boot_parent_host,
                                  MState#mstate.boot_parent_port,
                                  SName),
    F = fun(Addr, MStateAcc) -> add_parent(Addr, MStateAcc) end,
    lists:foldl(F, MState, List).

start_heavy_works(Args, MState) ->
    case wm_state:get_current() of
        maint ->
            ?LOG_INFO("Don't load node services (maint mode has been enabled)"),
            MState2 = start_modules([wm_admin], Args, 0, MState),
            wm_works:enable(),
            {ok, MState2};
        _ ->
            case load_services(MState, Args) of
                {ok, MState2} ->
                    wm_state:enter(idle),
                    wm_works:enable(),
                    {ok, MState2};
                {error, MState2} ->
                    wm_state:enter(maint),
                    wm_works:enable(),
                    {ok, MState2}
            end
    end.

add_parent_to_pinger(#mstate{pstack = PStack} = MState) ->
    case PStack of
        [] ->
            ?LOG_INFO("Parent will not be pinged (absent)");
        _ ->
            ParentAddr = wm_parent:get_current(MState#mstate.pstack),
            ?LOG_DEBUG("Current known parent: ~p", [ParentAddr]),
            wm_pinger:add(ParentAddr)
    end.

handle_maint_state(maint, NodeAddr, #mstate{}) ->
    ?LOG_DEBUG("Handle maint state of node ~p", [NodeAddr]),
    case wm_conf:select_node(NodeAddr) of
        {ok, Node} ->
            NodeId = wm_entity:get(id, Node),
            case wm_topology:is_my_direct_child(NodeId) of
                true ->
                    BootInfo = get_child_boot_info(NodeAddr),
                    ?LOG_DEBUG("Child boot info: ~p", [BootInfo]),
                    wm_api:cast_self({event, new_boot_info, BootInfo}, [NodeAddr]);
                false ->
                    ?LOG_DEBUG("Node ~p is not a direct child, no new boot info for it", [NodeId])
            end;
        {error, _} ->
            ?LOG_ERROR("Cannot handle maint state: node not known: ~p", [NodeAddr])
    end;
handle_maint_state(_, _, _) ->
    ok.

get_child_boot_info({NodeHost, NodePort}) ->
    {MyHost, MyPort} = wm_conf:get_my_relative_address({NodeHost, NodePort}),
    wm_entity:set([{node_host, NodeHost}, {node_port, NodePort}, {parent_host, MyHost}, {parent_port, MyPort}],
                  wm_entity:new(boot_info)).

set_boot_info(BootInfo, MState) ->
    Node =
        case wm_conf:select_node("boot_node") of
            {ok, X} ->
                ?LOG_DEBUG("Boot node entity is already defined => update"),
                X;
            {error, _} ->
                ?LOG_DEBUG("Boot node entity is not defined => create"),
                wm_entity:set({id, wm_utils:uuid(v4)}, wm_entity:new(node))
        end,
    NodeHost = wm_entity:get(node_host, BootInfo),
    NodePort = wm_entity:get(node_port, BootInfo),
    ParentHost = wm_entity:get(parent_host, BootInfo),
    ParentPort = wm_entity:get(parent_port, BootInfo),
    NewNode =
        wm_entity:set([{name, "boot_node"},
                       {host, NodeHost},
                       {api_port, NodePort},
                       {parent, {ParentHost, ParentPort}},
                       {comment, "Temporary boot settings"}],
                      Node),
    wm_conf:update(NewNode),
    add_parent({ParentHost, ParentPort}, MState).
