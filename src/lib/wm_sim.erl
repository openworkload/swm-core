-module(wm_sim).

-behaviour(gen_server).

-export([start_link/1]).
-export([start_all/0, stop_all/0, start_node/1, stop_node/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(mstate,
        {nodes = maps:new() :: map(), sim_type = none :: atom(), sim_spool = "." :: string(), root = "." :: string()}).

-include("wm_log.hrl").
-include("wm_entity.hrl").

%% ============================================================================
%% API functions
%% ============================================================================

%% @doc Start simulation service
-spec start_link(term()) -> {ok, pid()}.
start_link(Args) ->
    ?LOG_DEBUG("Simulation arguments: ~p", [Args]),
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Start all nodes (in configuration) simulation
-spec start_all() -> ok.
start_all() ->
    gen_server:cast(?MODULE, start_all).

%% @doc Stop all nodes (in configuration) simulation
-spec stop_all() -> ok.
stop_all() ->
    gen_server:cast(?MODULE, stop_all).

%% @doc Start inividual node simulation
-spec start_node(atom()) -> ok.
start_node(NodeName) ->
    gen_server:cast(?MODULE, {start, NodeName}).

%% @doc Stop inividual node simulation
-spec stop_node(atom()) -> ok.
stop_node(NodeName) ->
    gen_server:cast(?MODULE, {stop, NodeName}).

%% ============================================================================
%% Callbacks
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
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_DEBUG("Module state: ~p", [MState]),
    {ok, MState}.

handle_call(_, _From, MState) ->
    {reply, ok, MState}.

handle_cast(init_stop, MState) ->
    ?LOG_DEBUG("Stop the node!"),
    init:stop(),
    {noreply, MState};
handle_cast(start_all, MState) ->
    {noreply, do_start_all(MState)};
handle_cast(stop_all, MState) ->
    {noreply, do_stop_all(MState)};
handle_cast({start, NodeName}, MState) ->
    ?LOG_DEBUG("Received request to start ~p", [NodeName]),
    {noreply, try_start_slave(NodeName, MState)};
handle_cast({stop, NodeName}, MState) ->
    ?LOG_DEBUG("Received request to stop ~p", [NodeName]),
    {noreply, try_stop_slave(NodeName, MState)}.

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
parse_args([{root, Root} | T], MState) ->
    parse_args(T, MState#mstate{root = Root});
parse_args([{sim_type, Type} | T], MState) ->
    parse_args(T, MState#mstate{sim_type = Type});
parse_args([{sim_spool, SimSpool} | T], MState) ->
    parse_args(T, MState#mstate{sim_spool = SimSpool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec do_start_all(#mstate{}) -> #mstate{}.
do_start_all(MState = #mstate{sim_type = partition_per_node}) ->
    %TODO Take sim_type into account
    case wm_conf:select(node, all) of
        {error, need_maint} ->
            wm_state:enter(maint),
            MState;
        Nodes ->
            ?LOG_DEBUG("Start simulation for ~p nodes", [length(Nodes)]),
            F = fun(NodeName, AccMState) -> try_start_slave(NodeName, AccMState) end,
            lists:foldl(F, MState, Nodes)
    end.

-spec do_stop_all(#mstate{}) -> #mstate{}.
do_stop_all(MState) ->
    case wm_conf:get_children({state_power, up}) of
        Nodes when is_list(Nodes) ->
            ?LOG_DEBUG("~p: stop simulation for ~p nodes", [node(), length(Nodes)]),
            F = fun(Node) ->
                   NodeName = wm_utils:node_to_fullname(Node),
                   ?LOG_DEBUG("Stop node ~w", [NodeName]),
                   %TODO Get rid of the remote call (use cast with reply waiting):
                   wm_api:call_self(init_stop, NodeName)
                end,
            [F(X) || X <- Nodes]
    end,
    MState#mstate{nodes = maps:new()}.

-spec get_slave_args(string(), string(), #mstate{}) -> string().
get_slave_args(SName, Host, #mstate{sim_spool = Spool}) ->
    Name = SName ++ "@" ++ Host,
    SaslDir = filename:join([Spool, Name, "log/sasl"]),
    CA = filename:join([Spool, "secure/cluster/cert.pem"]),
    Cert = filename:join([Spool, "secure/node/cert.pem"]),
    Key = filename:join([Spool, "secure/node/key.pem"]),
    MnesiaDir = filename:join([Spool, Name ++ "/confdb"]),
    LibDir = wm_utils:get_env("SWM_LIB"),
    " -hidden"
    ++ " -setcookie devcookie"
    ++ " -rsh ssh"
    ++ " -connect_all false"
    ++ " -proto_dist inet_tls"
    ++ " -ssl_dist_opt server_cacertfile "
    ++ CA
    ++ " -ssl_dist_opt server_certfile "
    ++ Cert
    ++ " -ssl_dist_opt server_keyfile "
    ++ Key
    ++ " -boot start_sasl"
    ++ " -sasl errlog_type error"
    ++ " -sasl error_logger_mf_dir '\""
    ++ SaslDir
    ++ "\"'"
    ++ " -sasl error_logger_mf_maxbytes 10485760"
    ++ " -sasl error_logger_mf_maxfiles 5"
    ++ " -env DISPLAY "
    ++ Host
    ++ ":0 "
    ++ " -mnesia dir '\""
    ++ MnesiaDir
    ++ "\"'"
    ++ " -pa "
    ++ LibDir.

-spec try_start_slave(#node{} | string(), #mstate{}) -> #mstate{}.
try_start_slave(Node, MState = #mstate{nodes = Nodes}) when is_tuple(Node) ->
    FullName = wm_utils:node_to_fullname(Node),
    case maps:is_key(FullName, Nodes) of
        true ->
            ?LOG_INFO("Node ~p simulation has already been started", [FullName]),
            MState;
        false ->
            do_start_slave(Node, MState)
    end;
try_start_slave(NodeName, MState) ->
    case wm_conf:select(node, {name, NodeName}) of
        {ok, Node} ->
            try_start_slave(Node, MState);
        {error, not_found} ->
            ?LOG_INFO("Node ~p not found in the configuration", [NodeName]),
            MState
    end.

-spec do_start_slave(#node{}, #mstate{}) -> #mstate{}.
do_start_slave(Node, MState = #mstate{sim_spool = Spool, root = RootDir}) ->
    SlaveShortName = wm_entity:get(name, Node),
    case wm_utils:get_parent_from_conf(Node) of
        {ParentHost, ParentPort} ->
            SlaveHost = wm_entity:get(host, Node),
            SlavePort = wm_entity:get(api_port, Node),
            SlaveArgs = get_slave_args(SlaveShortName, SlaveHost, MState),
            AppArgs =
                [{spool, Spool},
                 {parent_host, ParentHost},
                 {parent_port, ParentPort},
                 {boot_type, clean},
                 {printer, file},
                 {simulation, true},
                 {default_api_port, SlavePort},
                 {root, RootDir},
                 {sname, SlaveShortName}],
            ?LOG_DEBUG("Simulation arguments for ~p: ~p", [SlaveShortName, AppArgs]),
            case wm_core:start_slave(SlaveShortName, SlaveArgs, AppArgs) of
                {ok, self} ->
                    MState;
                {ok, _} ->
                    SlaveName = list_to_atom(SlaveShortName ++ "@" ++ SlaveHost),
                    NodesMap = maps:put(SlaveName, started, MState#mstate.nodes),
                    MState#mstate{nodes = NodesMap};
                {error, Reason} ->
                    ?LOG_ERROR("Cannot start ~p@~p: ~p", [SlaveShortName, SlaveHost, Reason]),
                    MState
            end;
        not_found ->
            ?LOG_INFO("Node will not be started, because of no parent: ~p", [SlaveShortName]),
            MState
    end.

-spec try_stop_slave(string(), #mstate{}) -> #mstate{}.
try_stop_slave(NodeName, MState) when is_list(NodeName) ->
    {ok, Node} = wm_conf:select(node, {name, NodeName}),
    try_stop_slave(Node, MState);
try_stop_slave(Node, MState) when is_tuple(Node) ->
    NodeName = wm_utils:node_to_fullname(Node),
    try_stop_slave(NodeName, MState);
try_stop_slave(NodeName, MState) when is_atom(NodeName) ->
    ?LOG_DEBUG("Stop node ~w", [NodeName]),
    wm_api:cast_self(init_stop, NodeName),
    case maps:is_key(NodeName, MState#mstate.nodes) of
        true ->
            MState#mstate{nodes = maps:remove(NodeName, MState#mstate.nodes)};
        false ->
            MState
    end.
