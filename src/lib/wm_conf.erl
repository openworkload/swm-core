-module(wm_conf).

-behavior(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([g/2, set_global/2, select/2, select_node/1, select_many/3, ensure_boot_info_deleted/0, get_nodes_with_state/1,
         update/1, update/3, import/2, delete/1, delete/2, propagate_config/1, propagate_config/2, pull_async/1,
         set_node_state/3, set_nodes_state/3, get_my_address/0, get_my_relative_address/1, get_relative_address/2,
         is_my_address/1, get_size/1]).

-include("wm_entity.hrl").
-include("wm_log.hrl").
-include("../../include/wm_general.hrl").

-define(DEFAULT_SYCN_INTERVAL, 60000).
-define(DEFAULT_PULL_TIMEOUT, 10000).

-record(mstate, {spool = "" :: string(), default_port = unknown :: integer() | atom(), sync = false :: atom()}).

%% ============================================================================
%% Module API
%% ============================================================================

%% @doc Start configuration server
-spec start_link(term()) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Pull configuration (if changed) from parent node
-spec pull_async(node()) -> ok | {error, term()}.
pull_async(Node) ->
    ?LOG_DEBUG("Pull (async) data from ~p", [Node]),
    gen_server:cast(?MODULE, {pull_config, Node}).

%% @doc Get global parameter value
-spec g(string(), {term(), atom()}) -> term().
g(Name, {Default, ConvertTo}) ->
    do_get_global(Name, Default, ConvertTo).

%% @doc Set global parameter value
-spec set_global(string(), term()) -> pos_integer().
set_global(Name, Value) ->
    do_set_global(Name, Value).

% @doc Return amount of records in the table
-spec get_size(atom()) -> pos_integer().
get_size(Tab) ->
    wm_db:get_size(Tab).

%% @doc Select one, several or all (IDs=all) entities from db.
-spec select(atom(), tuple() | term() | fun((term) -> boolean())) -> {ok, term()} | {error, not_found} | [].
select(Tab, {Key, Value}) ->
    do_select(Tab, {Key, Value});
select(Tab, Fun) when is_function(Fun) ->
    do_select(Tab, Fun);
select(Tab, Condition) ->
    do_select(Tab, Condition).

%% @doc Search for node by name
-spec select_node(string() | tuple() | atom()) -> {ok, #node{}} | {error, atom()}.
select_node(Name) when is_atom(Name) ->
    NameStr = atom_to_list(Name),
    select_node(NameStr);
select_node(Name) ->
    case wm_db:is_running() of
        yes ->
            do_select_node(Name);
        no ->
            {error, need_maint}
    end.

%% @doc Search for nodes by parameter
-spec select_many(atom, attr, list()) -> list().
select_many(Tab, Attr, Values) ->
    wm_db:get_many(Tab, Attr, Values).

%% @doc Get all children nodes with specified state
-spec get_nodes_with_state({atom(), atom()}) -> term().
get_nodes_with_state(NodesState) ->
    wm_utils:protected_call(?MODULE, {get_nodes_with_state, NodesState}, []).

%% @doc Update existing record in the configuration
-spec update(atom(), {atom(), term()}, {atom(), term()}) -> {atomic, term()} | {aborted, term()}.
update(Tab, {KeyName, KeyVal}, {Attr, NewValue}) ->
    Arg = {update, Tab, {KeyName, KeyVal, Attr, NewValue}},
    wm_utils:protected_call(?MODULE, Arg).

%% @doc Add new or update record if exists
-spec update([term()]) -> pos_integer().
update(Records) when is_list(Records) ->
    wm_utils:protected_call(?MODULE, {set, Records});
update(Entity) ->
    wm_utils:protected_call(?MODULE, {set, [Entity]}).

%% @doc Delete existing record from configuration
-spec delete(term()) -> ok.
delete(Record) ->
    wm_utils:protected_call(?MODULE, {delete, Record}).

%% @doc Delete existing record by key from configuration
-spec delete(term(), term()) -> ok.
delete(Tab, KeyVal) ->
    wm_utils:protected_call(?MODULE, {delete, Tab, KeyVal}).

-spec import([term()], integer()) -> {integer, integer()}.
import([], Count) ->
    ?LOG_DEBUG("Imported ~p tables", [Count]),
    {integer, Count + wm_db:create_the_rest_tables()};
import([Term | T], Count) ->
    update(Term),
    import(T, Count + 1).

-spec propagate_config([atom()], atom()) -> ok.
propagate_config(Tabs, Node) ->
    gen_server:cast(?MODULE, {propagate, Tabs, Node}).

-spec propagate_config([atom()]) -> ok.
propagate_config(Nodes) ->
    %TODO use mnesia checkpointings (to get a consistent config or rollback?)
    gen_server:cast(?MODULE, {propagate, Nodes}).

-spec set_node_state(atom(), atom(), atom | node_address()) -> ok.
set_node_state(power, State, Node) ->
    gen_server:cast(?MODULE, {set_state, state_power, State, Node});
set_node_state(alloc, State, Node) ->
    gen_server:cast(?MODULE, {set_state, state_alloc, State, Node}).

-spec set_nodes_state(atom(), atom(), [#node{}]) -> pos_integer().
set_nodes_state(StateType, StateName, Nodes) ->
    NewNodes = [wm_entity:set({StateType, StateName}, Z) || Z <- Nodes],
    update(NewNodes).

-spec get_my_address() -> node_address() | not_found.
get_my_address() ->
    case wm_db:get_one(node, name, wm_utils:get_short_name(node())) of
        [] ->
            wm_utils:protected_call(?MODULE, get_my_address, not_found);
        [SelfNode] ->
            wm_utils:get_address(SelfNode)
    end.

-spec is_my_address(string() | {string(), integer()}) -> true | false.
is_my_address({"localhost", Port}) ->
    Port == wm_conf:g(parent_api_port, {?DEFAULT_PARENT_API_PORT, integer});
is_my_address(Addr) ->
    case get_my_address() of
        not_found ->
            true; % if db is empty => consider the address is mine
        Addr ->
            true;
        Other ->
            ?LOG_DEBUG("Address ~p is not ~p, check gateway", [Addr, Other]),
            IsGw = wm_core:get_my_gateway_address() == Addr,
            ?LOG_DEBUG("Is gateway mine: ~p (~p vs ~p)", [IsGw, wm_core:get_my_gateway_address(), Addr]),
            IsGw
    end.

%% @doc Get "not my" node address that depends on what self node requests it
-spec get_relative_address(#node{}, #node{}) -> {string(), integer()}.
get_relative_address(_To = #node{gateway = [],
                                 host = Host,
                                 api_port = Port},
                     _From) ->
    {Host, Port};
get_relative_address(_To = #node{host = Host, api_port = Port}, _From = #node{gateway = []}) ->
    {Host, Port};
get_relative_address(_To = #node{gateway = Gateway, api_port = Port}, _) ->
    {Gateway, Port}.

%% @doc Get self address that depends on what exact node it is going to communicate
-spec get_my_relative_address({string(), integer()}) -> {string(), integer()} | {error, not_found}.
get_my_relative_address(DestAddr = {_, _}) ->
    case do_select_node(DestAddr) of
        {ok, Node} ->
            NodeId = wm_entity:get(id, Node),
            case wm_topology:is_my_direct_child(NodeId) of
                true ->
                    get_my_relative_direct_address(Node);
                false ->
                    case select_my_node() of
                        {ok, MyNode} ->
                            MyNodeId = wm_entity:get(id, MyNode),
                            case wm_topology:on_path(MyNodeId, NodeId) of
                                {ok, NextNodeId} ->
                                    case select_one({node, id}, NextNodeId) of
                                        [NextNode] ->
                                            get_my_relative_direct_address(NextNode);
                                        _ ->
                                            do_get_my_address()
                                    end;
                                _ ->
                                    do_get_my_address()
                            end;
                        {error, not_found} ->
                            do_get_my_address()
                    end
            end;
        _ ->
            do_get_my_address()
    end.

-spec select_my_node() -> {ok, #node{}} | {error, not_found}.
select_my_node() ->
    Name = wm_utils:get_short_name(node()),
    case do_select_node(Name) of
        {ok, Node} ->
            {ok, Node};
        _ ->
            {error, not_found}
    end.

-spec get_my_relative_direct_address(#node{}) -> node_address().
get_my_relative_direct_address(DestNode) ->
    case wm_entity:get(remote_id, DestNode) of
        [] ->
            do_get_my_address();
        _ ->
            MySName = wm_utils:get_short_name(node()),
            case select_node(MySName) of
                {ok, MyNode} ->
                    MyHost = wm_entity:get(host, MyNode),
                    MyPort = wm_entity:get(api_port, MyNode),
                    case wm_entity:get(gateway, MyNode) of
                        [] ->
                            {MyHost, MyPort};
                        MyGateway ->
                            {MyGateway, MyPort}
                    end;
                _ ->
                    do_get_my_address()
            end
    end.

-spec select_node_apply(node_address(), function()) -> {error, not_found} | term().
select_node_apply({Host, Port}, Func) ->
    case wm_db:get_one_2keys(node, {host, Host}, {api_port, Port}) of
        Nodes when length(Nodes) > 1 ->
            ?LOG_ERROR("Multiple nodes with address ~p:~p found: ~p", [Host, Port, Nodes]),
            {error, found_multiple, Nodes};
        [Node] when is_tuple(Node) ->
            ?LOG_DEBUG("Node ~p:~p found by host", [Host, Port]),
            Func({ok, Node});
        [] ->
            ?LOG_DEBUG("Node by host ~p (~p) not found, look at gateway", [Host, Port]),
            case wm_db:get_one_2keys(node, {gateway, Host}, {api_port, Port}) of
                Nodes when length(Nodes) > 1 ->
                    ?LOG_ERROR("Multiple nodes with gateway ~p:~p found: ~p", [Host, Port, Nodes]),
                    {error, not_found};
                [Node] when is_tuple(Node) ->
                    ?LOG_DEBUG("Node ~p:~p found by gateway", [Host, Port]),
                    Func({ok, Node});
                [] ->
                    ?LOG_INFO("Node ~p:~p not found", [Host, Port]),
                    {error, not_found}
            end
    end.

-spec ensure_boot_info_deleted() -> {atomic, term()} | {aborted, term()} | ok.
ensure_boot_info_deleted() ->
    ?LOG_DEBUG("Ensure the boot info is deleted (not needed any more)"),
    case select(node, {name, "boot_node"}) of
        {ok, BootNode} ->
            delete(BootNode);
        _ ->
            ok
    end.

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
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("Load configuration management module"),
    process_flag(trap_exit, true),
    ?LOG_INFO("Using spool directory: ~p", [MState#mstate.spool]),
    DBDir = filename:join([MState#mstate.spool, atom_to_list(node()), "confdb"]),
    filelib:ensure_dir([DBDir]),
    file:make_dir(DBDir),
    wm_db:ensure_running(),
    wm_db:force_load_tables(),
    schedule_sync_check(),
    {ok, MState}.

handle_call(get_my_address, _From, MState) ->
    {reply, do_get_my_address(), MState};
handle_call({delete, Record}, _From, MState) ->
    {reply, wm_db:delete(Record), MState};
handle_call({delete, Tab, KeyVal}, _From, MState) ->
    {reply, wm_db:delete_by_key(Tab, KeyVal), MState};
handle_call({update, Tab, {Key, KeyVal, Attr, Value}}, _From, MState) ->
    {reply, wm_db:update_existing(Tab, {Key, KeyVal}, Attr, Value), MState};
handle_call({get_nodes_with_state, {StateType, St}}, _From, MState) ->
    case wm_db:get_many(node, StateType, [St]) of
        [] ->
            ?LOG_DEBUG("No one node found with ~p state '~p'", [StateType, St]),
            {reply, [], MState};
        Ns1 ->
            DelMe = fun(X) -> wm_utils:node_to_fullname(X) =/= node() end,
            Ns2 = lists:filter(DelMe, Ns1),
            L = length(Ns2),
            ?LOG_DEBUG("Found ~p children with ~p state '~p'", [L, StateType, St]),
            {reply, Ns2, MState}
    end;
handle_call({select_api_port, NodeName}, _From, MState) ->
    case select_one({node, name}, NodeName) of
        [] ->
            ?LOG_DEBUG("Found 0 entities with name=~s", [NodeName]),
            {reply, {error, not_found}, MState};
        X when is_list(X) ->
            Port = wm_entity:get(api_port, hd(X)),
            ?LOG_DEBUG("Requested port of ~p: ~p", [NodeName, Port]),
            {reply, {port, Port}, MState}
    end;
handle_call({set, Records}, _From, MState) ->
    wm_db:ensure_tables_exist(Records),
    {reply, wm_db:update(Records), MState}.

handle_cast({pull_config, Node}, MState) when MState#mstate.sync == false ->
    NewSyncId = wm_utils:uuid(v4),
    Timeout = ?MODULE:g(sync_timeout, {?DEFAULT_PULL_TIMEOUT, integer}),
    wm_utils:wake_up_after(Timeout, {sync_timeout, NewSyncId}),
    Hashes = wm_db:get_hashes(schema),
    ?LOG_DEBUG("Pull hashes: ~p from ~p", [Hashes, Node]),
    case get_my_relative_address(Node) of
        {error, not_found} ->
            ?LOG_DEBUG("Self address unknown => do not pull config for now"),
            {noreply, MState};
        MyAddr ->
            wm_api:cast_self({sync_schema_request, Hashes, MyAddr}, [Node]),
            {noreply, MState#mstate{sync = NewSyncId}}
    end;
handle_cast({sync_schema_request, TabHashes, From}, MState) ->
    ?LOG_DEBUG("Request to sync schema received from ~p", [From]),
    MyAddr = get_my_relative_address(From),
    Meta =
        case wm_state:get_current() of
            idle ->
                wm_db:get_tables_meta(TabHashes);
            _ ->
                not_ready
        end,
    wm_api:cast_self({sync_schema_reply, Meta, MyAddr}, [From]),
    {noreply, MState};
handle_cast({sync_schema_reply, not_ready, Parent}, MState) ->
    ?LOG_DEBUG("Reply on sync schema request received (~p not ready)", [Parent]),
    {noreply, MState#mstate{sync = false}};
handle_cast({sync_schema_reply, Meta, Parent}, MState) when MState#mstate.sync =/= false ->
    ?LOG_DEBUG("Reply on sync schema request received (N=~p, parent=~p)", [length(Meta), Parent]),
    wm_db:upgrade_schema(Meta),
    Hashes = wm_db:get_hashes(tables),
    ?LOG_DEBUG("Pull configuration data from ~p", [Parent]),
    MyAddr = get_my_relative_address(Parent),
    wm_api:cast_self({sync_config_request, Hashes, MyAddr, Parent}, [Parent]),
    {noreply, MState};
handle_cast({sync_config_request, TabHashes, From, Me}, MState) ->
    DifferentTabs =
        case wm_state:get_current() of
            idle ->
                wm_db:compare_hashes(TabHashes);
            _ ->
                not_ready
        end,
    wm_api:cast_self({sync_config_reply, DifferentTabs, Me}, [From]),
    {noreply, MState};
handle_cast({sync_config_reply, not_ready, Parent}, MState) ->
    ?LOG_DEBUG("Reply on sync config update request received (~p not ready)", [Parent]),
    {noreply, MState#mstate{sync = false}};
handle_cast({sync_config_reply, DifferentTabs, Parent}, MState) when MState#mstate.sync =/= false ->
    ?LOG_DEBUG("Reply on sync config request received "
               "(N=~p, parent=~p)",
               [length(DifferentTabs), Parent]),
    case DifferentTabs of
        [] ->
            ?LOG_DEBUG("No tabs to update (sync_config_request returned [])");
        DifferentTabs when is_list(DifferentTabs) ->
            ?LOG_INFO("The local and parent's tabs differ: ~p", [DifferentTabs]),
            wm_state:enter(maint),
            % Special case of event sending. When a new node starts,
            % then it does not have nodes data and cannot announce the
            % event to subscribers. Thus we send the message to parent directly.
            % If we had Node we could use wm_event:announce(need_tabs_update, Data)
            % on child node, but we have to ask parent to generate the event locally.
            MyAddr = get_my_relative_address(Parent),
            EventData = {MyAddr, DifferentTabs},
            wm_api:cast_self({event, need_tabs_update, EventData}, [Parent])
    end,
    {noreply, MState#mstate{sync = done}};
handle_cast({event, need_tabs_update, Data}, MState) ->
    wm_event:announce(need_tabs_update, Data),
    {noreply, MState};
handle_cast({set_state, state_power, down, Node}, MState) ->
    ?LOG_DEBUG("Set node ~p power/alloc states to down/stopped", [Node]),
    do_set_state(state_power, down, Node),
    do_set_state(state_alloc, stopped, Node),
    {noreply, MState};
handle_cast({set_state, Type, State, Node}, MState) ->
    ?LOG_DEBUG("Set node ~p ~p state to ~p", [Node, Type, State]),
    do_set_state(Type, State, Node),
    {noreply, MState};
handle_cast({propagate, Nodes}, MState) when is_list(Nodes) ->
    ?LOG_DEBUG("Propagate config to nodes ~p", [wm_utils:join_atoms(Nodes, ",")]),
    MyAddr = get_my_address(),
    wm_db:propagate_tables(Nodes, MyAddr),
    {noreply, MState};
handle_cast({propagate, Tabs, Node}, MState) ->
    ?LOG_DEBUG("Propagate tabs ~p to ~p", [Tabs, Node]),
    MyAddr = get_my_relative_address(Node),
    wm_db:propagate_tables(Tabs, Node, MyAddr),
    {noreply, MState};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Unknown cast: ~p", [Msg]),
    {noreply, MState}.

handle_info({sync_timeout, TimeoutSyncId}, MState) ->
    case MState#mstate.sync of
        TimeoutSyncId ->
            ?LOG_DEBUG("Sync ~p will be finished by timeout", [TimeoutSyncId]),
            schedule_sync_check(),
            {noreply, MState#mstate{sync = false}};
        _ ->
            {noreply, MState}
    end;
handle_info(sync_check, MState) ->
    ?LOG_DEBUG("Check sync"),
    case MState#mstate.sync of
        false ->
            case wm_core:get_parent() of
                not_found ->
                    ?LOG_DEBUG("No parent defined => will not sync");
                ParentAddr ->
                    wm_pinger:send_if_pinged(ParentAddr, ?MODULE, {pull_config, ParentAddr})
            end,
            schedule_sync_check();
        done ->
            ?LOG_DEBUG("Sync is finished");
        SyncId ->
            ?LOG_DEBUG("Sync ~p is in progress", [SyncId])
    end,
    {noreply, MState};
handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{spool, Dir} | T], MState) ->
    parse_args(T, MState#mstate{spool = Dir});
parse_args([{default_api_port, Port} | T], #mstate{} = MState) when is_list(Port) ->
    parse_args(T, MState#mstate{default_port = list_to_integer(Port)});
parse_args([{default_api_port, Port} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{default_port = Port});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec select_several({[atom()], atom()}, term()) -> [term()].
select_several({Tabs, _}, all) when is_list(Tabs) ->
    lists:flatten(select_several(Tabs, []));
select_several({Tab, _}, {all, MaxReturnedListSize}) ->
    wm_db:get_all(Tab, MaxReturnedListSize);
select_several({Tab, _}, all) ->
    wm_db:get_all(Tab);
select_several({Tab, Attr}, SearchValues) when is_list(SearchValues) ->
    wm_db:get_many(Tab, Attr, SearchValues);
select_several([], Acc) ->
    Acc;
select_several([Tab | T], Acc) ->
    select_several(T, [select_several({Tab, []}, all) | Acc]).

-spec select_one({atom(), atom()}, term()) -> term().
select_one({Tab, Attr}, Val) ->
    wm_db:get_one(Tab, Attr, Val).

-spec do_set_state(atom(), atom(), atom() | node_address()) -> pos_integer().
do_set_state(Type, State, Node) when is_atom(Node) ->
    case wm_db:table_exists(node) of
        false ->
            ?LOG_DEBUG("Table 'node' not found, don't set node ~p state ~p", [Node, State]),
            0;
        true ->
            NodeNameStr = atom_to_list(Node),
            [ShortName, Host] = string:tokens(NodeNameStr, "@"),
            case select_one({node, name}, ShortName) of
                [] ->
                    ?LOG_DEBUG("The node is unknown: ~p", [ShortName]),
                    0;
                Nodes when is_list(Nodes) ->
                    F = fun(Nd) -> wm_entity:get(host, Nd) =:= Host end,
                    {NodesOnHost, _} = lists:partition(F, Nodes),
                    case NodesOnHost of
                        [] ->
                            ?LOG_DEBUG("Node ~p not found on host: ~p", [ShortName, Host]),
                            0;
                        SatisfyingNodes ->
                            Node1 = hd(SatisfyingNodes), % should be one only
                            Node2 = wm_entity:set({Type, State}, Node1),
                            wm_db:update([{Node2, false}])
                    end
            end
    end;
do_set_state(Type, State, {Host, Port}) when is_list(Host) ->
    F = fun({ok, Node}) ->
           NodeUpdated = wm_entity:set({Type, State}, Node),
           wm_db:update([{NodeUpdated, false}])
        end,
    select_node_apply({Host, Port}, F).

-spec do_get_global(string(), term(), atom()) -> term().
do_get_global(Name, Default, Type) ->
    wm_db:get_global(Name, Type, Default).

-spec do_set_global(string(), term()) -> integer().
do_set_global(Name, Value) when is_integer(Value) ->
    do_set_global(Name, integer_to_list(Value));
do_set_global(Name, Value) ->
    X2 = case wm_db:get_global(Name, record, {}) of
             {} ->
                 wm_entity:new(list_to_binary(Name));
             X1 ->
                 X1
         end,
    X3 = wm_entity:set({value, Value}, X2),
    wm_utils:protected_call(?MODULE, {set, [X3]}).

-spec schedule_sync_check() -> reference().
schedule_sync_check() ->
    N = ?MODULE:g(sync_interval, {?DEFAULT_SYCN_INTERVAL, integer}),
    ?LOG_DEBUG("Schedule new sync check in ~p ms", [N]),
    wm_utils:wake_up_after(N, sync_check).

-spec do_get_my_address() -> node_address().
do_get_my_address() ->
    Addr =
        case wm_db:get_one(node, name, wm_utils:get_short_name(node())) of
            [] ->
                ?LOG_DEBUG("Could not get my node => look at boot node"),
                case wm_db:get_one(node, name, "boot_node") of
                    [] ->
                        ?LOG_DEBUG("Could not get any nodes => my address is unknown"),
                        {error, not_found};
                    [BootNode] ->
                        NodeHost = wm_entity:get(host, BootNode),
                        NodePort = wm_entity:get(api_port, BootNode),
                        {NodeHost, NodePort}
                end;
            [SelfNode] ->
                wm_utils:get_address(SelfNode)
        end,
    ?LOG_DEBUG("Get my address result: ~p", [Addr]),
    Addr.

-spec do_select(atom(), {atom(), term()} | function() | list() | atom()) -> {ok, term()} | {error, not_found}.
do_select(Tab, {Key, Value}) when Key =/= all ->
    case select_one({Tab, Key}, Value) of
        [] ->
            ?LOG_ERROR("Found 0 ~p entities with ~p=~p", [Tab, Key, Value]),
            {error, not_found};
        [X] ->
            {ok, X};
        Xs ->
            {ok, Xs}
    end;
do_select(Tab, Fun) when is_function(Fun) ->
    case wm_db:get_many_pred(Tab, Fun) of
        [] ->
            {error, not_found};
        Xs ->
            {ok, Xs}
    end;
do_select(Tab, IDs) when is_list(IDs) ->
    select_several({Tab, id}, IDs);
do_select(Tab, Condition) ->
    select_several({Tab, id}, Condition).

-spec do_select_node(node_address()) -> {ok, #node{}} | {error, atom()}.
do_select_node({Host, Port}) ->
    select_node_apply({Host, Port}, fun(X) -> X end);
do_select_node(Name) when is_list(Name) ->
    Tab = node,
    case wm_db:table_exists(Tab) of
        true ->
            Node =
                case lists:any(fun ($@) ->
                                       true;
                                   (_) ->
                                       false
                               end,
                               Name)
                of
                    true ->
                        [ShortName, Host] = string:tokens(Name, "@"),
                        wm_db:get_one_2keys(Tab, {name, ShortName}, {host, Host});
                    false ->
                        select_one({Tab, name}, Name)
                end,
            case Node of
                [] ->
                    ?LOG_DEBUG("Node not found: ~p", [Name]),
                    {error, need_maint};
                Records ->
                    {ok, hd(Records)}
            end;
        _ ->
            ?LOG_ERROR("Table not found: ~p", [Tab]),
            {error, need_maint}
    end.
