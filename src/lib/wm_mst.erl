-module(wm_mst).

-behaviour(gen_statem).

-export([start_link/1, activate/1]).
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([sleeping/3, find/3, found/3]).

-include("wm_log.hrl").

-record(mstate,
        {fragm_id :: atom(),
         level :: integer(),
         edge_states = maps:new() :: map(),
         best_edge :: atom(),
         best_wt :: atom() | integer(),
         test_edge :: atom(),
         in_branch :: atom(),
         find_count :: integer(),
         state :: atom(),
         requests_queue = [] :: list(),
         nodes :: list(),
         mst_id :: string()}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_statem:start_link(?MODULE, Args, []).

%% @doc Activate a new MST construction
-spec activate(pid()) -> ok.
activate(Pid) ->
    ?LOG_DEBUG("Activate ~p", [Pid]),
    gen_statem:cast(Pid, wakeup).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec callback_mode() -> state_functions.
-spec init(term()) ->
              {ok, atom(), term()} |
              {ok, atom(), term(), hibernate | infinity | non_neg_integer()} |
              {stop, term()} |
              ignore.
-spec code_change(term(), atom(), term(), term()) -> {ok, term()}.
-spec terminate(term(), atom(), term()) -> ok.
callback_mode() ->
    state_functions.

init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("MST module has been started (~p)", [MState#mstate.mst_id]),
    wm_factory:notify_initiated(mst, MState#mstate.mst_id),
    {ok, sleeping, MState}.

code_change(_OldVsn, StateName, MState, _Extra) ->
    {ok, StateName, MState}.

terminate(Status, StateName, MState) ->
    Msg = io_lib:format("MST ~p has been terminated (status=~p, state=~p)", [MState#mstate.mst_id, Status, StateName]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% State machine transitions
%% ============================================================================

-spec sleeping({call, pid()} | cast, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
sleeping(cast, {connect, From, Level}, MState) ->
    ?LOG_DEBUG("Received connect from ~p => wake up [sleeping]", [From]),
    MState2 = wakeup(set_state(found, MState)),
    MState3 = do_connect_resp(From, Level, get_state(MState2), MState2),
    {next_state, get_state(MState3), MState3};
sleeping(Event, Msg, MState) ->
    ?LOG_DEBUG("Received ~p, ~p => wake up [sleeping]", [Event, Msg]),
    MState2 = wakeup(set_state(found, MState)),
    {next_state, get_state(MState2), MState2}.

-spec find({call, pid()} | cast, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
find(cast, {connect, From, Level}, MState) ->
    ?LOG_DEBUG("Received 'connect' (E=~p, L=~p) [find]", [From, Level]),
    MState2 = do_connect_resp(From, Level, find, set_state(find, MState)),
    {next_state, get_state(MState2), MState2};
find(cast, {initiate, From, Level, FID, NodeState}, MState) ->
    ?LOG_DEBUG("Received 'initiate' (E=~p, L=~p) [find]", [From, Level]),
    MState2 = set_state(find, MState),
    MState3 = do_initiate_resp(From, Level, FID, NodeState, MState2),
    {next_state, get_state(MState3), MState3};
find(cast, {test, From, Level, FID}, MState) ->
    ?LOG_DEBUG("Received 'test' from ~p (L=~p, F=~p) [find]", [From, Level, FID]),
    MState2 = do_test_resp(From, Level, FID, set_state(find, MState)),
    {next_state, get_state(MState2), MState2};
find(cast, {accept, From}, MState) ->
    ?LOG_DEBUG("Received 'accept' from ~p [find]", [From]),
    MState2 = do_accept_resp(From, set_state(find, MState)),
    {next_state, get_state(MState2), MState2};
find(cast, {reject, From}, MState) ->
    ?LOG_DEBUG("Received 'accept' from ~p [find]", [From]),
    MState2 = do_reject_resp(From, set_state(find, MState)),
    {next_state, get_state(MState2), MState2};
find(cast, {report, From, BestWeight}, MState) ->
    ?LOG_DEBUG("Received 'report' from ~p, W=~p [find]", [From, BestWeight]),
    MState2 = do_report_resp(From, BestWeight, set_state(find, MState)),
    {next_state, get_state(MState2), MState2};
find(cast, {change_root, From}, MState) ->
    ?LOG_DEBUG("Received 'change_root' from ~p [find]", [From]),
    MState2 = do_change_root_resp(From, set_state(find, MState)),
    {next_state, get_state(MState2), MState2};
find(cast, wakeup, MState) ->
    {next_state, get_state(MState), MState}.

-spec found({call, pid()} | cast, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
found(cast, {connect, From, Level}, MState) ->
    ?LOG_DEBUG("Received 'connect' (E=~p, L=~p) [found]", [From, Level]),
    MState2 = do_connect_resp(From, Level, found, set_state(found, MState)),
    {next_state, get_state(MState2), MState2};
found(cast, {initiate, From, Level, Weight, NodeState}, MState) ->
    ?LOG_DEBUG("Received 'initiate' (E=~p, L=~p) [found]", [From, Level]),
    MState2 = set_state(found, MState),
    MState3 = do_initiate_resp(From, Level, Weight, NodeState, MState2),
    {next_state, get_state(MState3), MState3};
found(cast, {test, From, Level, FID}, MState) ->
    ?LOG_DEBUG("Received 'test' (E=~p, L=~p, F=~p) [found]", [From, Level, FID]),
    MState2 = do_test_resp(From, Level, FID, set_state(found, MState)),
    {next_state, get_state(MState2), MState2};
found(cast, {accept, From}, MState) ->
    ?LOG_DEBUG("Received 'accept' from ~p [found]", [From]),
    MState2 = do_accept_resp(From, set_state(found, MState)),
    {next_state, get_state(MState2), MState2};
found(cast, {reject, From}, MState) ->
    ?LOG_DEBUG("Received 'accept' from ~p [found]", [From]),
    MState2 = do_reject_resp(From, set_state(found, MState)),
    {next_state, get_state(MState2), MState2};
found(cast, {report, From, BestWeight}, MState) ->
    ?LOG_DEBUG("Received 'report' from ~p, W=~p [found]", [From, BestWeight]),
    MState2 = do_report_resp(From, BestWeight, set_state(found, MState)),
    {next_state, get_state(MState2), MState2};
found(cast, {change_root, From}, MState) ->
    ?LOG_DEBUG("Received 'change_root' from ~p [found]", [From]),
    MState2 = do_change_root_resp(From, set_state(found, MState)),
    {next_state, get_state(MState2), MState2};
found(cast, wakeup, MState) ->
    {next_state, get_state(MState), MState}.

%% ============================================================================
%% GHS implementation functions
%% ============================================================================

-spec wakeup(#mstate{}) -> #mstate{}.
wakeup(MState) ->
    ?LOG_INFO("Wake up and explore nodes constructing new MST"),
    case MState#mstate.nodes of
        [] ->
            do_halt(MState);
        Edges ->
            MState2 = init_edge_states(Edges, MState),
            MState3 =
                MState2#mstate{level = 0,
                               find_count = 0,
                               fragm_id = node()},
            case try_connect(Edges, unknown, MState3) of
                {connected, MState4} ->
                    ?LOG_DEBUG("Connected, MState=~s", [format_mstate(MState4)]),
                    MState4;
                {not_connected, MState4} ->
                    ?LOG_DEBUG("Cannot send 'connect' to any of ~p", [Edges]),
                    do_halt(MState4)
            end
    end.

%------------------------------- CONNECT

-spec try_connect([atom()], term(), #mstate{}) -> {connected, #mstate{}} | {not_connected, #mstate{}}.
try_connect(_, {true, Edge}, MState) ->
    {connected, set_edge_state(Edge, branch, MState)};
try_connect([], _, MState) ->
    {not_connected, MState};
try_connect([Edge | T], _, MState) ->
    Result = send({connect, node(), MState#mstate.level}, Edge, MState),
    ?LOG_DEBUG("Sending 'connect' to ~p result: ~p", [Edge, Result]),
    try_connect(T, Result, MState).

-spec do_connect_resp(atom(), integer(), atom(), #mstate{}) -> #mstate{}.
do_connect_resp(Edge, Level, NodeState, MState) when Level < MState#mstate.level ->
    ?LOG_DEBUG("Connect respond: E=~p, L=~p<~p", [Edge, Level, MState#mstate.level]),
    MState2 = set_edge_state(Edge, branch, MState),
    try_initiate(Edge, NodeState, MState2),
    case NodeState of
        find ->
            MState2#mstate{find_count = MState2#mstate.find_count + 1};
        _ ->
            MState2
    end;
do_connect_resp(Edge,
                Level,
                _,
                MState) -> %% Level >= MState#mstate.level
    ?LOG_DEBUG("Connect respond: E=~p, L=~p", [Edge, Level]),
    case get_edge_state(Edge, MState) of
        basic ->
            queue_request({connect, Edge, Level}, MState);
        _ ->
            try_initiate(Edge, find, MState#mstate{level = MState#mstate.level + 1}),
            MState
    end.

%------------------------------- INITIATE

-spec try_initiate(atom(), atom(), #mstate{}) -> #mstate{}.
try_initiate(Edge, NodeState, MState) ->
    ?LOG_DEBUG("Initiate ~p (S=~p)", [Edge, NodeState]),
    FID = MState#mstate.fragm_id,
    send({initiate, node(), MState#mstate.level, FID, NodeState}, Edge, MState).

-spec do_initiate_resp(atom(), integer(), atom(), atom(), #mstate{}) -> #mstate{}.
do_initiate_resp(From, Level, FID, NodeState, MState) ->
    ?LOG_DEBUG("Respond to 'initiate' from ~p", [From]),
    {ok, RemoteNode} = wm_conf:select_node(atom_to_list(FID)),
    {ok, MyNodeId} = wm_self:get_node_id(),
    RemoteLeaderID = wm_entity:get(id, RemoteNode),
    {InBranch, NewFID, FC} =
        case RemoteLeaderID < MyNodeId of
            true ->
                {From, FID, MState#mstate.find_count};
            false ->
                {none, node(), MState#mstate.find_count + 1}
        end,
    ?LOG_DEBUG("New FID=~p (id2=~p, id1=~p)", [NewFID, RemoteLeaderID, MyNodeId]),
    ?LOG_DEBUG("Old/new levels: ~p/~p", [MState#mstate.level, Level]),
    MState2 =
        MState#mstate{fragm_id = NewFID,
                      level = Level,
                      in_branch = InBranch,
                      best_edge = none,
                      state = NodeState,
                      best_wt = infinity,
                      find_count = FC},
    MState3 =
        case MState#mstate.level =/= Level of
            true ->
                handle_queued_requests(MState2);
            _ ->
                MState2
        end,
    F = fun (Edge, branch, FindCount) when From =/= Edge ->
                try_initiate(Edge, NodeState, MState3),
                case NodeState of
                    find ->
                        FindCount + 1;
                    _ ->
                        FindCount
                end;
            (_, _, FindCount) ->
                FindCount
        end,
    FindCount = maps:fold(F, MState3#mstate.find_count, MState3#mstate.edge_states),
    MState4 = MState3#mstate{find_count = FindCount},
    case NodeState of
        find ->
            try_test(Level, NewFID, MState4);
        _ ->
            MState4
    end.

%------------------------------- TEST

-spec try_test(integer(), atom(), #mstate{}) -> #mstate{}.
try_test(Level, FID, MState) ->
    ?LOG_DEBUG("Run procedure 'test': L=~p, ID=~p", [Level, FID]),
    F = fun ({_, basic}) ->
                true;
            (_) ->
                false
        end,
    Pairs = lists:filter(F, maps:to_list(MState#mstate.edge_states)),
    EdgesBasic = [X || {X, _} <- Pairs],
    Msg = {test, node(), MState#mstate.level, MState#mstate.fragm_id},
    MState3 =
        case send_to_min_weight_edge(Msg, EdgesBasic, MState) of
            {false, NewMState} ->
                try_report(NewMState#mstate{test_edge = none});
            {true, NewMState} ->
                NewMState
        end,
    ?LOG_DEBUG("Test procedure finished, MState=~s", [format_mstate(MState3)]),
    MState3.

-spec do_test_resp(atom(), integer(), atom(), #mstate{}) -> #mstate{}.
do_test_resp(From, Level, FID, MState) when Level > MState#mstate.level ->
    ?LOG_DEBUG("Respond to 'test' from ~p (L=~p, FID=~p)", [From, Level, FID]),
    queue_request({test, From, Level, FID}, MState);
do_test_resp(From, Level, FID, MState) when FID =/= MState#mstate.fragm_id ->
    ?LOG_DEBUG("Respond to 'test' from ~p (L=~p, FID=~p)", [From, Level, FID]),
    try_accept(From, MState);
do_test_resp(From, Level, FID, MState) ->
    ?LOG_DEBUG("Respond to 'test' from ~p (L=~p, FID=~p)", [From, Level, FID]),
    MState2 = set_edge_rejected_if_basic(From, MState),
    case MState2#mstate.test_edge of
        From ->
            try_test(MState2#mstate.level, MState2#mstate.fragm_id, MState2);
        _ ->
            try_reject(From, MState2)
    end.

%------------------------------- ACCEPT

-spec try_accept(atom(), #mstate{}) -> #mstate{}.
try_accept(Edge, MState) ->
    ?LOG_DEBUG("Run procedure 'accept' on edge ~p", [Edge]),
    send({accept, node()}, Edge, MState),
    MState.

-spec do_accept_resp(atom(), #mstate{}) -> #mstate{}.
do_accept_resp(From, MState) ->
    ?LOG_DEBUG("Respond to 'accept' from ~p", [From]),
    MState2 = MState#mstate{test_edge = none},
    Weight = wm_topology:get_latency(node(), From),
    MState3 =
        if Weight < MState2#mstate.best_wt ->
               MState2#mstate{best_edge = From, best_wt = Weight};
           true ->
               MState2
        end,
    try_report(MState3).

%------------------------------- REJECT

-spec try_reject(atom(), #mstate{}) -> #mstate{}.
try_reject(Edge, MState) ->
    ?LOG_DEBUG("Run procedure 'reject' on edge ~p", [Edge]),
    send({reject, node()}, Edge, MState),
    MState.

-spec do_reject_resp(atom(), #mstate{}) -> #mstate{}.
do_reject_resp(From, MState) ->
    ?LOG_DEBUG("Respond to 'reject' from ~p", [From]),
    MState2 = set_edge_rejected_if_basic(From, MState),
    try_test(MState2#mstate.level, MState2#mstate.fragm_id, MState2).

%------------------------------- REPORT

-spec try_report(#mstate{}) -> #mstate{}.
try_report(MState) ->
    ?LOG_DEBUG("Run procedure 'report', mstate=~s", [format_mstate(MState)]),
    if MState#mstate.find_count == 0, MState#mstate.test_edge == none ->
           case MState#mstate.in_branch of
               none ->
                   ?LOG_DEBUG("My in-branch is looped and all find-branches"
                              ++ " were reported to me, so lets halt the algorithm"),
                   set_state(found, MState),
                   do_halt(MState);
               _ ->
                   ?LOG_DEBUG("Report ~p: links are tested", [MState#mstate.in_branch]),
                   Msg = {report, node(), MState#mstate.best_wt},
                   send(Msg, MState#mstate.in_branch, MState),
                   set_state(found, MState)
           end;
       true ->
           MState
    end.

-spec do_report_resp(atom(), atom() | integer(), #mstate{}) -> #mstate{}.
do_report_resp(From, RBestWeight, MState) when From =/= MState#mstate.in_branch ->
    ?LOG_DEBUG("Respond to 'report' from ~p (W=~p)", [From, RBestWeight]),
    MState2 = MState#mstate{find_count = MState#mstate.find_count - 1},
    MState3 =
        case RBestWeight < MState2#mstate.best_wt of
            true ->
                MState2#mstate{best_wt = RBestWeight, best_edge = From};
            _ ->
                MState2
        end,
    try_report(MState3);
do_report_resp(From, RBestWeight, MState) when MState#mstate.state == find ->
    ?LOG_DEBUG("Respond to 'report' from ~p (W=~p)", [From, RBestWeight]),
    queue_request({report, From, RBestWeight}, MState);
do_report_resp(From, RBestWeight, MState) ->
    ?LOG_DEBUG("Respond to 'report' from ~p (W=~p)", [From, RBestWeight]),
    case RBestWeight > MState#mstate.best_wt of
        true ->
            do_change_root(From, MState);
        _ ->
            case RBestWeight of
                infinity when MState#mstate.best_wt == infinity ->
                    do_halt(MState);
                _ ->
                    MState
            end
    end.

%------------------------------- CHANGE_ROOT

-spec do_change_root(atom(), #mstate{}) -> #mstate{}.
do_change_root(Edge, MState) ->
    ?LOG_DEBUG("Change root: ~p", [Edge]),
    case get_edge_state(Edge, MState) of
        branch ->
            send({change_root, Edge}, MState#mstate.best_edge, MState),
            MState;
        _ ->
            Me = node(),
            send({connect, Me, MState#mstate.level}, MState#mstate.best_edge, MState),
            set_edge_state(MState#mstate.best_edge, branch, MState)
    end.

-spec do_change_root_resp(atom(), #mstate{}) -> #mstate{}.
do_change_root_resp(From, MState) ->
    ?LOG_DEBUG("Respond to 'change_root' from ~p", [From]),
    do_change_root(From, MState).

-spec do_halt(#mstate{}) -> #mstate{}.
do_halt(MState) ->
    ?LOG_DEBUG("Do halt the algorithm, MST has been found with a single leader"),
    MyAddr = wm_conf:get_my_address(),
    wm_event:announce(wm_mst_done, {MState#mstate.mst_id, {node, MyAddr}}),
    MState.

%% ============================================================================
%% Helper functions
%% ============================================================================

-spec queue_request(term(), #mstate{}) -> #mstate{}.
queue_request(Msg, MState) ->
    ?LOG_DEBUG("Put the request back to events queue: ~p", [Msg]),
    NewQueue = [Msg | MState#mstate.requests_queue],
    MState#mstate{requests_queue = NewQueue}.

-spec handle_queued_requests(#mstate{}) -> #mstate{}.
handle_queued_requests(MState) ->
    ?LOG_DEBUG("Requests queue: ~p", [MState#mstate.requests_queue]),
    QueueSize = length(MState#mstate.requests_queue),
    ?LOG_DEBUG("Handle ~p queued requests", [QueueSize]),
    F = fun(QueuedRequest) -> ok = gen_statem:cast(self(), QueuedRequest) end,
    [F(X) || X <- lists:reverse(MState#mstate.requests_queue)],
    MState#mstate{requests_queue = []}.

-spec init_edge_states([atom()], #mstate{}) -> #mstate{}.
init_edge_states(Edges, MState) ->
    F = fun(E, MStateAcc) -> set_edge_state(E, basic, MStateAcc) end,
    lists:foldl(F, MState#mstate{edge_states = maps:new()}, Edges).

-spec send(term(), atom(), #mstate{}) -> {term(), atom()}.
send(Msg, Edge, MState) ->
    Result = wm_factory:send_confirm(mst, one_state, MState#mstate.mst_id, Msg, [Edge]),
    {Result, Edge}.

-spec send_to_min_weight_edge(term(), [atom()], #mstate{}) -> {boolean(), #mstate{}}.
send_to_min_weight_edge(Msg, [], MState2) ->
    ?LOG_DEBUG("No more min-weight edges are available to send ~p", Msg),
    {false, MState2};
send_to_min_weight_edge(Msg, Edges, MState) ->
    ?LOG_DEBUG("Send ~p to min-weight edge (edges set: ~p)", [Msg, Edges]),
    case wm_topology:get_min_latency_to(Edges) of
        {} ->
            ?LOG_DEBUG("No edges were found"),
            {false, MState};
        {Edge, Weight} ->
            ?LOG_DEBUG("Minimum weight edge is ~p (W=~p)", [Edge, Weight]),
            case send(Msg, Edge, MState) of
                {true, Edge} ->
                    {true, MState#mstate{test_edge = Edge}};
                Error ->
                    RemainingEdges = Edges -- [Edge],
                    ?LOG_DEBUG("Failed to send ~p to ~p: ~p (remaining edges: ~p)", [Msg, Edge, Error, RemainingEdges]),
                    MState2 = set_edge_state(Edge, rejected, MState),
                    send_to_min_weight_edge(Msg, RemainingEdges, MState2)
            end
    end.

-spec get_edge_state(atom(), #mstate{}) -> map().
get_edge_state(Edge, MState) ->
    maps:get(Edge, MState#mstate.edge_states).

-spec set_edge_rejected_if_basic(atom(), #mstate{}) -> #mstate{}.
set_edge_rejected_if_basic(Edge, MState) ->
    case get_edge_state(Edge, MState) of
        basic ->
            set_edge_state(Edge, rejected, MState);
        _ ->
            MState
    end.

-spec set_edge_state(atom(), atom(), #mstate{}) -> #mstate{}.
set_edge_state(Edge, basic, MState) ->
    NewMap = maps:put(Edge, basic, MState#mstate.edge_states),
    MState#mstate{edge_states = NewMap};
set_edge_state(Edge, EdgeState, MState) ->
    MState2 = handle_queued_requests(MState),
    NewMap = maps:put(Edge, EdgeState, MState2#mstate.edge_states),
    MState#mstate{edge_states = NewMap}.

-spec get_state(#mstate{}) -> atom().
get_state(MState) ->
    MState#mstate.state.

-spec set_state(atom(), #mstate{}) -> #mstate{}.
set_state(State, MState) ->
    MState2 = MState#mstate{state = State},
    case MState#mstate.state =/= MState2#mstate.state of
        true ->
            handle_queued_requests(MState2);
        false ->
            MState2
    end.

-spec format_mstate(#mstate{}) -> string().
format_mstate(MState) ->
    io_lib:format("fragm_id=~p level=~p edge_states=~p best_edge=~p best_wt=~p test_edge=~p "
                  "in_branch=~p find_count=~p state=~p queuesize=~p id=~p",
                  [MState#mstate.fragm_id,
                   MState#mstate.level,
                   maps:to_list(MState#mstate.edge_states),
                   MState#mstate.best_edge,
                   MState#mstate.best_wt,
                   MState#mstate.test_edge,
                   MState#mstate.in_branch,
                   MState#mstate.find_count,
                   MState#mstate.state,
                   length(MState#mstate.requests_queue),
                   MState#mstate.mst_id]).

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{nodes, Nodes} | T], MState) ->
    parse_args(T, MState#mstate{nodes = Nodes});
parse_args([{task_id, ID} | T], MState) ->
    parse_args(T, MState#mstate{mst_id = ID});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).
