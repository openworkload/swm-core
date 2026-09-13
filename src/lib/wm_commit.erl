-module(wm_commit).

-behaviour(gen_statem).

-export([start_link/1]).
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([phase1/3, phase2/3, phase3/3, recovering/3]).

-include("wm_log.hrl").
-include("wm_entity.hrl").
-include("../../include/wm_general.hrl").

-record(mstate,
        {tid :: integer(),
         records :: [term()],
         nodes :: [node_address()],
         leader :: node_address(),
         election_id :: integer(),
         last_attempt = 0 :: integer(),
         last_elected = 1 :: integer(),
         max_attempt = 0 :: integer(),
         max_elected = 1 :: integer(),
         replies = maps:new() :: map(),
         last_attempts = maps:new() :: map(),
         my_addr :: node_address(),
         %% Invalidates stale check_transaction timers when timeout is re-armed.
         timeout_gen = 0 :: integer()}).

-define(TRANSACTION_TIMEOUT, 300000).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_statem:start_link(?MODULE, Args, []).

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
    MState1 = parse_args(Args, #mstate{}),
    TunnelParentAddr = {"localhost", wm_conf:g(parent_api_port, {?DEFAULT_PARENT_API_PORT, integer})},
    MyAddr =
        case wm_self:get_node() of
            {ok, MyNode} ->
                case wm_utils:is_cloud_node(MyNode) of
                    false ->
                        wm_conf:get_my_relative_address(hd(MState1#mstate.nodes));
                    true ->
                        wm_conf:get_my_relative_address(TunnelParentAddr)
                end;
            {error, not_found} ->  % nodes are unknown yet => assume cloud node is booting
                wm_conf:get_my_relative_address(TunnelParentAddr)
        end,
    MState2 = MState1#mstate{my_addr = MyAddr},
    ?LOG_INFO("E3PC tid=~p| Started my_addr=~p nodes=~p records=~p",
              [MState2#mstate.tid, MyAddr, MState2#mstate.nodes, length(MState2#mstate.records)]),
    wm_factory:subscribe(mst, MState2#mstate.tid, wm_mst_done),
    wm_factory:notify_initiated(commit, MState2#mstate.tid),
    {ok, phase1, MState2}.

code_change(_OldVsn, StateName, MState, _Extra) ->
    {ok, StateName, MState}.

terminate(Status, StateName, MState) ->
    Msg = io_lib:format("Commit ~p has been terminated (status=~p, state=~p)", [MState#mstate.tid, Status, StateName]),
    wm_utils:terminate_msg(?MODULE, Msg).

%% ============================================================================
%% State machine transitions
%% ============================================================================

-spec phase1({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
phase1(cast, activate, #mstate{my_addr = MyAddr} = MState) ->
    log_tx_info(MState,
                "Start E3PC as coordinator my_addr=~p nodes=~p records=~p",
                [MyAddr, MState#mstate.nodes, length(MState#mstate.records)]),
    Msg = {transaction,
           {MyAddr, MState#mstate.nodes, MState#mstate.records},
           MState#mstate.last_elected,
           MState#mstate.last_attempt},
    send_all(Msg, MState),
    %% Timeout is armed on {send_confirmed,...} so slow outbound RPCs do not
    %% consume the wait window for participant replies.
    MState2 = MState#mstate{leader = MyAddr},
    {next_state, phase1, clean_replies(MState2)};
phase1(cast, {send_confirmed, Result}, MState) ->
    log_tx(MState, "Outbound send confirmed (~p) -> arm timeout ~pms", [Result, ?TRANSACTION_TIMEOUT]),
    {next_state, phase1, arm_timeout(MState)};
phase1(cast, {transaction, Data, LastElected, LastAttempt}, #mstate{my_addr = MyAddr} = MState) ->
    {Leader, Nodes, Records} = Data,
    MState2 =
        MState#mstate{records = Records,
                      nodes = Nodes,
                      leader = Leader},
    log_phase(phase1, {transaction, Data, LastElected, LastAttempt}, MState2),
    log_tx(MState2,
           "Accept transaction from leader=~p nodes=~p records=~p -> phase2",
           [Leader, Nodes, length(Records)]),
    Reply = {yes, MyAddr},
    send_reply(Reply, Leader, MState2),
    {next_state, phase2, MState2};
phase1(cast, {yes, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(phase1, {yes, From}, MState),
    MState2 = add_reply(yes, From, MState),
    log_reply_progress(yes, MState2),
    case all_replied(MState2) of
        true ->
            log_tx(MState2, "All yes received -> send pre_commit, enter phase2", []),
            Msg = {pre_commit, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
            send_all(Msg, MState2),
            {next_state, phase2, clean_replies(MState2)};
        false ->
            {next_state, phase1, MState2}
    end;
phase1(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
phase1(cast, Msg, MState) ->
    log_phase(phase1, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec phase2({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
phase2(cast, {pre_commit, LastElected, LastAttempt, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(phase2, {pre_commit, LastElected, LastAttempt, From}, MState),
    case MState#mstate.leader of
        From ->
            Reply = {pre_committed, MyAddr},
            send_reply(Reply, From, MState),
            log_tx(MState, "Ack pre_commit from leader -> phase3", []),
            {next_state, phase3, MState};
        Other ->
            log_tx_warn(MState, "pre_commit from unexpected leader ~p (expected ~p) -> recover", [From, Other]),
            recover(),
            {next_state, recovering, MState}
    end;
phase2(cast, {send_confirmed, Result}, MState) ->
    log_tx(MState, "Outbound send confirmed (~p) -> arm timeout ~pms", [Result, ?TRANSACTION_TIMEOUT]),
    {next_state, phase2, arm_timeout(MState)};
phase2(cast, {pre_committed, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(phase2, {pre_committed, From}, MState),
    MState2 = add_reply(pre_committed, From, MState),
    log_reply_progress(pre_committed, MState2),
    case quorum_of(pre_committed, MState2) of
        true ->
            log_tx(MState2, "Quorum pre_committed -> send commit, enter phase3", []),
            Msg = {commit, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
            send_all(Msg, MState2),
            {next_state, phase3, clean_replies(MState2)};
        false ->
            Replies = MState2#mstate.replies,
            case all_replied(MState2) of
                true ->
                    log_tx_warn(MState2, "No pre_commit quorum after all replied -> abort, replies=~p", [Replies]),
                    Msg = {abort, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
                    send_all(Msg, MState2);
                false ->
                    log_tx(MState2, "Waiting for more pre_committed replies", [])
            end,
            {next_state, phase3, MState2}
    end;
phase2(cast, {pre_aborted, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(phase2, {pre_aborted, From}, MState),
    MState2 = add_reply(pre_aborted, From, MState),
    log_reply_progress(pre_aborted, MState2),
    case quorum_of(pre_aborted, MState2) of
        true ->
            log_tx_warn(MState2, "Quorum pre_aborted -> send abort, enter phase3", []),
            Msg = {abort, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
            send_all(Msg, MState2),
            {next_state, phase3, clean_replies(MState2)};
        false ->
            {next_state, phase3, MState2}
    end;
phase2(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
phase2(cast, Msg, MState) ->
    log_phase(phase2, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec phase3({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
phase3(cast, {commit, LastElected, LastAttempt, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(phase3, {commit, LastElected, LastAttempt, From}, MState),
    case MState#mstate.leader of
        From ->
            do_final_local_commit(MState),
            send_reply({commited, MyAddr}, From, MState),
            log_tx(MState, "Local commit done, acked leader", []),
            {next_state, phase3, MState};
        _ ->
            log_tx_warn(MState,
                        "commit from unexpected leader ~p (expected ~p) -> recover",
                        [From, MState#mstate.leader]),
            recover(),
            {next_state, recovering, MState}
    end;
phase3(cast, {send_confirmed, Result}, MState) ->
    log_tx(MState, "Outbound send confirmed (~p) -> arm timeout ~pms", [Result, ?TRANSACTION_TIMEOUT]),
    {next_state, phase3, arm_timeout(MState)};
phase3(cast, {commited, From}, MState) ->
    log_phase(phase3, {commited, From}, MState),
    MState2 = add_reply(yes, From, MState),
    log_reply_progress(commited, MState2),
    case all_replied(MState2) of
        true ->
            do_halt(committed, MState2);
        false ->
            ignore
    end,
    {next_state, phase3, MState2};
phase3(cast, {aborted, From}, MState) ->
    log_phase(phase3, {aborted, From}, MState),
    MState2 = add_reply(aborted, From, MState),
    log_reply_progress(aborted, MState2),
    case all_replied(MState2) of
        true ->
            do_halt(aborted, MState2);
        false ->
            ignore
    end,
    {next_state, phase3, MState2};
phase3(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
phase3(cast, Msg, MState) ->
    log_phase(phase3, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec recovering({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
recovering(cast, recover_transaction, #mstate{my_addr = MyAddr} = MState) ->
    log_tx_info(MState,
                "Enter recovering: my_addr=~p leader=~p nodes=~p LE=~p LA=~p replies=~p",
                [MyAddr,
                 MState#mstate.leader,
                 MState#mstate.nodes,
                 MState#mstate.last_elected,
                 MState#mstate.last_attempt,
                 MState#mstate.replies]),
    case MState#mstate.leader == MyAddr of
        true ->
            log_tx(MState, "I am coordinator -> collect lasts (no election)", []),
            gen_statem:cast(self(), collect_lasts),
            {next_state, recovering, MState#mstate{election_id = none}};
        false ->
            log_tx(MState, "Check if leader ~p is alive", [MState#mstate.leader]),
            case wm_pinger:ping_sync(MState#mstate.leader) of
                {pong, _} ->
                    log_tx(MState, "Leader ~p alive -> wait for its recovery requests", [MState#mstate.leader]),
                    {next_state, recovering, MState#mstate{election_id = none}};
                {pang, _} ->
                    log_tx_warn(MState, "Leader ~p dead -> elect a new leader", [MState#mstate.leader]),
                    {ok, MST_ID} = wm_factory:new(mst, [], MState#mstate.nodes),
                    {next_state, recovering, MState#mstate{election_id = MST_ID}}
            end
    end;
recovering(cast, collect_lasts, #mstate{my_addr = MyAddr} = MState) ->
    log_tx(MState, "Collect lasts from nodes=~p", [MState#mstate.nodes]),
    send_all({request_lasts, MyAddr}, MState),
    {next_state, recovering, clean_replies(MState)};
recovering(cast, {send_confirmed, Result}, MState) ->
    log_tx(MState, "Outbound send confirmed (~p) -> arm timeout ~pms", [Result, ?TRANSACTION_TIMEOUT]),
    {next_state, recovering, arm_timeout(MState)};
recovering(cast, {lasts, LE, LA, From}, #mstate{my_addr = MyAddr} = MState) ->
    MState2 = add_reply(replied, From, MState),
    MaxLE = max(MState2#mstate.max_elected, LE),
    MaxLA = max(MState2#mstate.max_attempt, LA),
    LAs = maps:put(From, LA, MState#mstate.last_attempts),
    MState3 =
        MState2#mstate{max_attempt = MaxLA,
                       max_elected = MaxLE,
                       last_attempts = LAs},
    log_tx(MState3, "Got lasts from ~p: LE=~p LA=~p (max_LE=~p max_LA=~p)", [From, LE, LA, MaxLE, MaxLA]),
    log_reply_progress(lasts, MState3),
    case all_replied(MState3) of
        true ->
            log_tx(MState3, "All lasts collected -> announce new_leader max_LE=~p", [MaxLE]),
            send_all({new_leader, MaxLE, MyAddr}, MState3),
            {next_state, recovering, clean_replies(MState3)};
        false ->
            {next_state, recovering, MState3}
    end;
recovering(cast, {state, RemoteState, From}, #mstate{my_addr = MyAddr} = MState) ->
    MState2 = add_reply(RemoteState, From, MState),
    log_tx(MState2, "Got state=~p from ~p", [RemoteState, From]),
    log_reply_progress(state, MState2),
    case all_replied(MState2) of
        true ->
            MState3 = MState2#mstate{last_attempt = MState2#mstate.last_elected},
            LA = MState3#mstate.last_attempt,
            LE = MState3#mstate.last_elected,
            Decision = make_decision(MState3),
            log_tx_info(MState3,
                        "Recovery decision=~p (LE=~p LA=~p replies=~p last_attempts=~p)",
                        [Decision, LE, LA, MState3#mstate.replies, MState3#mstate.last_attempts]),
            case Decision of
                pre_abort ->
                    send_all({pre_abort, LE, LA, MyAddr}, MState3),
                    {next_state, phase2, MState3};
                abort ->
                    send_all({abort, LE, LA, MyAddr}, MState3),
                    {next_state, phase3, MState3};
                pre_commit ->
                    send_all({pre_commit, LE, LA, MyAddr}, MState3),
                    {next_state, phase2, MState3};
                commit ->
                    send_all({commit, LE, LA, MyAddr}, MState3),
                    {next_state, phase3, MState3};
                block ->
                    send_all({abort, LE, LA, MyAddr}, MState3),
                    {next_state, phase3, MState3}
            end;
        false ->
            {next_state, recovering, MState2}
    end;
recovering(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
recovering(cast, Msg, MState) ->
    log_phase(recovering, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], MState) ->
    MState;
parse_args([{nodes, Nodes} | T], MState) ->
    parse_args(T, MState#mstate{nodes = Nodes});
parse_args([{task_id, ID} | T], MState) ->
    parse_args(T, MState#mstate{tid = ID});
parse_args([{extra, Records} | T], MState) ->
    parse_args(T, MState#mstate{records = Records});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec send_all(term(), #mstate{}) -> term().
send_all(Msg, MState) ->
    log_tx(MState, "Send to all ~p: ~p", [MState#mstate.nodes, Msg]),
    wm_factory:send_confirm(commit, MState#mstate.tid, Msg, MState#mstate.nodes).

-spec send_reply(term(), node_address(), #mstate{}) -> term().
send_reply(Msg, Address, MState) ->
    log_tx(MState, "Send reply to ~p: ~p", [Address, Msg]),
    wm_factory:send_confirm(commit, MState#mstate.tid, Msg, [Address]).

-spec log_tx(#mstate{}, string(), list()) -> ok.
log_tx(#mstate{tid = Tid}, Fmt, Args) ->
    ?LOG_DEBUG("E3PC tid=~p| ~s", [Tid, truncate_log(Fmt, Args)]).

-spec log_tx_info(#mstate{}, string(), list()) -> ok.
log_tx_info(#mstate{tid = Tid}, Fmt, Args) ->
    ?LOG_INFO("E3PC tid=~p| ~s", [Tid, truncate_log(Fmt, Args)]).

-spec log_tx_warn(#mstate{}, string(), list()) -> ok.
log_tx_warn(#mstate{tid = Tid}, Fmt, Args) ->
    ?LOG_WARN("E3PC tid=~p| ~s", [Tid, truncate_log(Fmt, Args)]).

-spec truncate_log(string(), list()) -> string().
truncate_log(Fmt, Args) ->
    Msg = lists:flatten(
              io_lib:format(Fmt, Args)),
    case length(Msg) > 100 of
        true ->
            lists:sublist(Msg, 100) ++ "...";
        false ->
            Msg
    end.

-spec log_phase(atom() | integer(), term(), #mstate{}) -> ok.
log_phase(Phase, Event, MState) ->
    log_tx(MState, "[~p] event=~p leader=~p replies=~p", [Phase, Event, MState#mstate.leader, MState#mstate.replies]).

-spec log_reply_progress(atom(), #mstate{}) -> ok.
log_reply_progress(Kind, #mstate{replies = Replies} = MState) ->
    Pending =
        maps:fold(fun (_, no, Acc) ->
                          Acc + 1;
                      (_, _, Acc) ->
                          Acc
                  end,
                  0,
                  Replies),
    Done = maps:size(Replies) - Pending,
    log_tx(MState,
           "Reply progress (~p): ~p/~p done, pending=~p, replies=~p",
           [Kind, Done, maps:size(Replies), Pending, Replies]).

-spec clean_replies(#mstate{}) -> #mstate{}.
clean_replies(MState) ->
    Map = maps:from_list([{X, no} || X <- MState#mstate.nodes]),
    MState#mstate{replies = Map}.

-spec add_reply(atom(), node_address(), #mstate{}) -> #mstate{}.
add_reply(Reply, From, MState) ->
    Replies = maps:put(From, Reply, MState#mstate.replies),
    MState#mstate{replies = Replies}.

-spec all_replied(#mstate{}) -> boolean().
all_replied(MState) ->
    error == maps:find(no, MState#mstate.replies).

-spec quorum_of(atom(), #mstate{}) -> boolean().
quorum_of(Element, #mstate{replies = Replies}) ->
    F = fun (_, V, Acc) when V == Element ->
                Acc + 1;
            (_, _, Acc) ->
                Acc
        end,
    YesN = maps:fold(F, 0, Replies),
    YesN >= trunc(maps:size(Replies) / 2 + 1).

-spec recover() -> ok.
recover() ->
    gen_statem:cast(self(), recover_transaction).

-spec do_final_local_commit(#mstate{}) -> ok.
do_final_local_commit(MState) ->
    log_tx(MState, "Apply local commit for ~p records", [length(MState#mstate.records)]),
    wm_db:ensure_tables_exist(MState#mstate.records),
    NoRevChangeRecs = [{X, false} || X <- MState#mstate.records],
    wm_db:update(NoRevChangeRecs),
    wm_db:create_the_rest_tables(),
    wm_conf:ensure_boot_info_deleted(),
    wm_self:update(),
    log_tx(MState, "Local subtransaction committed", []).

-spec do_halt(atom(), #mstate{}) -> ok.
do_halt(aborted, #mstate{my_addr = MyAddr} = MState) ->
    log_tx_info(MState, "ABORTED (my_addr=~p)", [MyAddr]),
    wm_event:announce(wm_commit_failed, {MState#mstate.tid, {node, MyAddr}});
do_halt(committed, #mstate{my_addr = MyAddr} = MState) ->
    log_tx_info(MState, "COMMITTED (my_addr=~p)", [MyAddr]),
    wm_event:announce(wm_commit_done, {MState#mstate.tid, {node, MyAddr}}).

-spec make_decision(#mstate{}) -> #mstate{}.
make_decision(MState) ->
    Q1 = fun() -> quorum_of(pre_committed, MState) end,
    Q2 = fun() -> quorum_of(pre_aborted, MState) end,
    Q3 = fun() ->
            F = fun (_, V, Acc) when V =/= MState#mstate.max_attempt ->
                        Acc + 1;
                    (_, _, Acc) ->
                        Acc
                end,
            B1 = maps:fold(F, 0, MState#mstate.last_attempts) == 0,
            B2 = error == maps:find(committed, MState#mstate.replies),
            B1 and B2
         end,
    C1 = fun() -> error == maps:find(aborted, MState#mstate.replies) end,
    C2 = fun() -> error == maps:find(committed, MState#mstate.replies) end,
    C3 = fun() -> Q1() and Q3() end,
    C4 = fun() -> Q2() and not Q3() end,
    case C1() of
        false ->
            abort;
        true ->
            case C2() of
                false ->
                    commit;
                true ->
                    case C3() of
                        true ->
                            pre_commit;
                        false ->
                            case C4() of
                                true ->
                                    pre_abort;
                                false ->
                                    block
                            end
                    end
            end
    end.

-spec handle_event(term(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
handle_event({event, wm_mst_done, {MST_ID, {node, Leader}}}, recovering, #mstate{my_addr = MyAddr} = MState)
    when MST_ID == MState#mstate.election_id ->
    log_tx(MState, "Election done: mst=~p leader=~p", [MST_ID, Leader]),
    MState2 = MState#mstate{leader = Leader},
    case MState#mstate.leader == MyAddr of
        true ->
            gen_statem:cast(self(), collect_lasts);
        _ ->
            log_tx(MState2, "Not elected leader (I am ~p)", [MyAddr])
    end,
    {next_state, recovering, MState2};
handle_event({request_lasts, Leader}, State, #mstate{my_addr = MyAddr} = MState) ->
    log_tx(MState,
           "request_lasts from ~p while in ~p -> reply LE=~p LA=~p",
           [Leader, State, MState#mstate.last_elected, MState#mstate.last_attempt]),
    Reply = {lasts, MState#mstate.last_elected, MState#mstate.last_attempt, MyAddr},
    send_reply(Reply, Leader, MState),
    {next_state, State, MState};
handle_event({new_leader, MaxLE, Leader}, State, #mstate{my_addr = MyAddr} = MState) ->
    log_tx(MState, "new_leader=~p max_elected=~p while in ~p -> reply state=~p", [Leader, MaxLE, State, State]),
    MState2 = MState#mstate{leader = Leader, last_elected = MaxLE + 1},
    send_reply({state, State, MyAddr}, Leader, MState2),
    {next_state, State, MState2};
handle_event({pre_abort, LE, LA, Leader}, _, #mstate{my_addr = MyAddr} = MState) ->
    log_tx(MState, "Decision pre_abort from ~p (LE=~p LA=~p)", [Leader, LE, LA]),
    send_reply({pre_aborted, MyAddr}, Leader, MState),
    {next_state, phase3, MState};
handle_event({abort, LE, LA, Leader}, State, #mstate{my_addr = MyAddr} = MState) ->
    log_tx_info(MState, "Decision abort from ~p (LE=~p LA=~p) while in ~p", [Leader, LE, LA, State]),
    send_reply({aborted, MyAddr}, Leader, MState),
    do_halt(aborted, MState),
    {next_state, State, MState};
%% Late recovery replies can arrive after the coordinator already left
%% 'recovering' (slow cloud/tunnel RPCs). Ignore them instead of restarting recovery.
handle_event({state, RemoteState, From}, State, MState) when State =/= recovering ->
    log_tx(MState, "Ignore late state=~p from ~p at ~p", [RemoteState, From, State]),
    {next_state, State, MState};
handle_event({lasts, LE, LA, From}, State, MState) when State =/= recovering ->
    log_tx(MState, "Ignore late lasts from ~p (LE=~p LA=~p) at ~p", [From, LE, LA, State]),
    {next_state, State, MState};
handle_event({yes, From}, State, MState) when State =/= phase1 ->
    log_tx(MState, "Ignore late yes from ~p at ~p", [From, State]),
    {next_state, State, MState};
handle_event(Event, State, MState) ->
    log_tx_warn(MState, "Unknown event at ~p: ~p -> recover", [State, Event]),
    recover(),
    {next_state, recovering, MState}.

-spec arm_timeout(#mstate{}) -> #mstate{}.
arm_timeout(MState) ->
    Gen = MState#mstate.timeout_gen + 1,
    wm_utils:wake_up_after(?TRANSACTION_TIMEOUT, {check_transaction, Gen}),
    MState#mstate{timeout_gen = Gen}.

-spec handle_info(atom(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
handle_info({check_transaction, Gen}, State, #mstate{timeout_gen = Gen} = MState) ->
    case MState#mstate.nodes of
        [] ->
            log_tx(MState, "Timeout check: transaction already finished (state=~p)", [State]),
            {next_state, State, MState};
        _ ->
            log_tx_warn(MState,
                        "TIMEOUT in ~p: nodes=~p replies=~p -> recover",
                        [State, MState#mstate.nodes, MState#mstate.replies]),
            recover(),
            {next_state, recovering, MState}
    end;
handle_info({check_transaction, StaleGen}, State, #mstate{timeout_gen = CurGen} = MState) ->
    log_tx(MState, "Ignore stale timeout gen=~p (current=~p) at ~p", [StaleGen, CurGen, State]),
    {next_state, State, MState};
handle_info(check_transaction, State, MState) ->
    %% Legacy timer from older code; treat as current generation.
    handle_info({check_transaction, MState#mstate.timeout_gen}, State, MState);
handle_info(Msg, State, MState) ->
    log_tx_warn(MState, "Unknown info at ~p: ~p -> recover", [State, Msg]),
    recover(),
    {next_state, recovering, MState}.
