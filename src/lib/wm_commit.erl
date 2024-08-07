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
         my_addr :: node_address()}).

-define(TRANSACTION_TIMEOUT, 120000).

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
    ?LOG_DEBUG("Commit module has been started (state: ~P)", [MState2, 10]),
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
    ?LOG_DEBUG("Start E3PC"),
    Msg = {transaction,
           {MyAddr, MState#mstate.nodes, MState#mstate.records},
           MState#mstate.last_elected,
           MState#mstate.last_attempt},
    send_all(Msg, MState),
    wm_utils:wake_up_after(?TRANSACTION_TIMEOUT, check_transaction),
    MState2 = MState#mstate{leader = MyAddr},
    {next_state, phase1, clean_replies(MState2)};
phase1(cast, {transaction, Data, LastElected, LastAttempt}, #mstate{my_addr = MyAddr} = MState) ->
    {Leader, Nodes, Records} = Data,
    MState2 =
        MState#mstate{records = Records,
                      nodes = Nodes,
                      leader = Leader},
    log_phase(1, {transaction, Data, LastElected, LastAttempt}, MState2),
    Reply = {yes, MyAddr},
    send_reply(Reply, Leader, MState2),
    {next_state, phase2, MState2};
phase1(cast, {yes, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(1, {yes, From}, MState),
    MState2 = add_reply(yes, From, MState),
    case all_replied(MState2) of
        true ->
            Msg = {pre_commit, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
            send_all(Msg, MState2),
            {next_state, phase2, clean_replies(MState2)};
        false ->
            {next_state, phase1, MState2}
    end;
phase1(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
phase1(cast, Msg, MState) ->
    log_phase(1, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec phase2({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
phase2(cast, {pre_commit, LastElected, LastAttempt, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(2, {pre_commit, LastElected, LastAttempt, From}, MState),
    case MState#mstate.leader of
        From ->
            Reply = {pre_committed, MyAddr},
            case wm_core:has_malfunction(e3pc_phase2) of
                not_found ->
                    send_reply(Reply, From, MState);
                no_answer ->
                    ok
            end,
            {next_state, phase3, MState};
        Other ->
            ?LOG_DEBUG("New transaction leader has been detected: ~p", [Other]),
            recover(),
            {next_state, recovering, MState}
    end;
phase2(cast, {pre_committed, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(2, {pre_committed, From}, MState),
    MState2 = add_reply(pre_committed, From, MState),
    case quorum_of(pre_committed, MState2) of
        true ->
            Msg = {commit, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
            send_all(Msg, MState2),
            {next_state, phase3, clean_replies(MState2)};
        false ->
            Replies = MState2#mstate.replies,
            ?LOG_ERROR("E3PC[2]: no quorum, replies: ~10000p", [Replies]),
            case all_replied(MState2) of
                true ->
                    Msg = {abort, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
                    send_all(Msg, MState2);
                false ->
                    ?LOG_ERROR("E3PC[2]: not all nodes replied"),
                    ignore
            end,
            {next_state, phase3, MState2}
    end;
phase2(cast, {pre_aborted, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(2, {pre_aborted, From}, MState),
    MState2 = add_reply(pre_aborted, From, MState),
    case quorum_of(pre_aborted, MState2) of
        true ->
            Msg = {abort, MState2#mstate.last_elected, MState2#mstate.last_attempt, MyAddr},
            send_all(Msg, MState2),
            {next_state, phase3, clean_replies(MState2)};
        false ->
            {next_state, phase3, MState2}
    end;
phase2(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
phase2(cast, Msg, MState) ->
    log_phase(2, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec phase3({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
phase3(cast, {commit, LastElected, LastAttempt, From}, #mstate{my_addr = MyAddr} = MState) ->
    log_phase(3, {commit, LastElected, LastAttempt, From}, MState),
    case MState#mstate.leader of
        From ->
            do_final_local_commit(MState),
            send_reply({commited, MyAddr}, From, MState),
            {next_state, phase3, MState};
        _ ->
            ?LOG_DEBUG("New transaction leader is detected"),
            recover(),
            {next_state, recovering, MState}
    end;
phase3(cast, {commited, From}, MState) ->
    log_phase(3, {commited, From}, MState),
    MState2 = add_reply(yes, From, MState),
    case all_replied(MState2) of
        true ->
            do_halt(committed, MState2);
        false ->
            ignore
    end,
    {next_state, phase3, MState2};
phase3(cast, {aborted, From}, MState) ->
    log_phase(3, {aborted, From}, MState),
    MState2 = add_reply(aborted, From, MState),
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
    log_phase(3, Msg, MState),
    handle_event(Msg, ?FUNCTION_NAME, MState).

-spec recovering({call, pid()} | cast | info, term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
recovering(cast, recover_transaction, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_INFO("Transaction ~p will be recovered", [MState#mstate.tid]),
    case MState#mstate.leader == MyAddr of
        true ->
            ?LOG_DEBUG("I'm coordinating the transaction => don't elect a leader"),
            gen_statem:cast(self(), collect_lasts),
            {next_state, recovering, MState#mstate{election_id = none}};
        false ->
            ?LOG_DEBUG("Find out if leader ~p is alive", [MState#mstate.leader]),
            case wm_pinger:ping_sync(MState#mstate.leader) of
                {pong, _} ->
                    ?LOG_ERROR("Leader responded, wait for new requests from it"),
                    {next_state, recovering, MState#mstate{election_id = none}};
                {pang, _} ->
                    ?LOG_ERROR("Leader did not responce, elect a new leader"),
                    {ok, MST_ID} = wm_factory:new(mst, [], MState#mstate.nodes),
                    {next_state, recovering, MState#mstate{election_id = MST_ID}}
            end
    end;
recovering(cast, collect_lasts, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Collect lasts values"),
    send_all({request_lasts, MyAddr}, MState),
    {next_state, recovering, clean_replies(MState)};
recovering(cast, {lasts, LE, LA, From}, #mstate{my_addr = MyAddr} = MState) ->
    MState2 = add_reply(replied, From, MState),
    MaxLE = max(MState2#mstate.max_elected, LE),
    MaxLA = max(MState2#mstate.max_attempt, LA),
    LAs = maps:put(From, LA, MState#mstate.last_attempts),
    MState3 =
        MState2#mstate{max_attempt = MaxLA,
                       max_elected = MaxLE,
                       last_attempts = LAs},
    case all_replied(MState3) of
        true ->
            send_all({new_leader, MaxLE, MyAddr}, MState3),
            {next_state, recovering, clean_replies(MState3)};
        false ->
            {next_state, recovering, MState3}
    end;
recovering(cast, {state, State, From}, #mstate{my_addr = MyAddr} = MState) ->
    MState2 = add_reply(State, From, MState),
    case all_replied(MState2) of
        true ->
            MState3 = MState2#mstate{last_attempt = MState2#mstate.last_elected},
            LA = MState3#mstate.last_attempt,
            LE = MState3#mstate.last_elected,
            case make_decision(MState3) of
                pre_abort ->
                    ?LOG_DEBUG("Recovery decision is to pre abort [go to phase2]"),
                    send_all({pre_abort, LE, LA, MyAddr}, MState3),
                    {next_state, phase2, MState3};
                abort ->
                    ?LOG_DEBUG("Recovery decision is to abort [go to phase3]"),
                    send_all({abort, LE, LA, MyAddr}, MState3),
                    {next_state, phase3, MState3};
                pre_commit ->
                    ?LOG_DEBUG("Recovery decision is to pre commit [go to phase2]"),
                    send_all({pre_commit, LE, LA, MyAddr}, MState3),
                    {next_state, phase2, MState3};
                commit ->
                    ?LOG_DEBUG("Recovery decision is to commit [go to phase3]"),
                    send_all({commit, LE, LA, MyAddr}, MState3),
                    {next_state, phase3, MState3};
                block ->
                    ?LOG_DEBUG("Recovery decision is to block => just abort"),
                    send_all({abort, LE, LA, MyAddr}, MState3),
                    {next_state, phase3, MState3}
            end;
        false ->
            {next_state, recovering, MState2}
    end;
recovering(info, Msg, MState) ->
    handle_info(Msg, ?FUNCTION_NAME, MState);
recovering(cast, Msg, MState) ->
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
    wm_factory:send_confirm(commit, MState#mstate.tid, Msg, MState#mstate.nodes).

-spec send_reply(term(), node_address(), #mstate{}) -> term().
send_reply(Msg, Address, MState) ->
    wm_factory:send_confirm(commit, MState#mstate.tid, Msg, [Address]).

-spec log_phase(integer(), term(), #mstate{}) -> ok.
log_phase(Phase, Event, MState) ->
    Args = [Phase, Event, 10, MState#mstate.nodes],
    ?LOG_DEBUG("E3PC[~p]: ~P (~p)", Args).

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
    ?LOG_DEBUG("E3PC: commit ~p records", [length(MState#mstate.records)]),
    wm_db:ensure_tables_exist(MState#mstate.records),
    NoRevChangeRecs = [{X, false} || X <- MState#mstate.records],
    wm_db:update(NoRevChangeRecs),
    wm_db:create_the_rest_tables(),
    wm_conf:ensure_boot_info_deleted(),
    wm_self:update(),
    ?LOG_DEBUG("The subtransaction has been commited").

-spec do_halt(atom(), #mstate{}) -> ok.
do_halt(aborted, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Distributed transaction ~p has aborted", [MState#mstate.tid]),
    wm_event:announce(wm_commit_failed, {MState#mstate.tid, {node, MyAddr}});
do_halt(committed, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Distributed transaction ~p has committed", [MState#mstate.tid]),
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
    ?LOG_DEBUG("Received 'wm_mst_done': ~p, ~p (~p)", [MST_ID, Leader, MState#mstate.tid]),
    MState2 = MState#mstate{leader = Leader},
    case MState#mstate.leader == MyAddr of
        true ->
            gen_statem:cast(self(), collect_lasts);
        _ ->
            ?LOG_DEBUG("I'm not a leader in dist transaction ~p", [MState#mstate.tid])
    end,
    {next_state, recovering, MState2};
handle_event({request_lasts, Leader}, State, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Requested last values"),
    Reply = {lasts, MState#mstate.last_elected, MState#mstate.last_attempt, MyAddr},
    send_reply(Reply, Leader, MState),
    {next_state, State, MState};
handle_event({new_leader, MaxLE, Leader}, State, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Received 'new_leader' from ~p, max_elected=~p", [Leader, MaxLE]),
    MState2 = MState#mstate{leader = Leader, last_elected = MaxLE + 1},
    send_reply({state, State, MyAddr}, Leader, MState2),
    {next_state, State, MState};
handle_event({pre_abort, _, _, Leader}, _, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Received distributed transaction decision: pre_abort"),
    send_reply({pre_aborted, MyAddr}, Leader, MState),
    {next_state, phase3, MState};
handle_event({abort, _, _, Leader}, State, #mstate{my_addr = MyAddr} = MState) ->
    ?LOG_DEBUG("Received distributed transaction decision: abort"),
    send_reply({aborted, MyAddr}, Leader, MState),
    do_halt(aborted, MState),
    {next_state, State, MState};
handle_event(Event, State, MState) ->
    ?LOG_DEBUG("Unknown event received at state ~p: ~p", [State, Event]),
    recover(),
    {next_state, recovering, MState}.

-spec handle_info(atom(), term(), #mstate{}) -> {atom(), atom(), #mstate{}}.
handle_info(check_transaction, State, MState) ->
    TID = MState#mstate.tid,
    case MState#mstate.nodes of
        [] ->
            ?LOG_DEBUG("Transaction ~p has already finished (good)", [TID]),
            {next_state, State, MState};
        _ ->
            ?LOG_WARN("Transaction ~p timeout has detected (not good)", [TID]),
            recover(),
            {next_state, recovering, MState}
    end;
handle_info(Msg, State, MState) ->
    ?LOG_DEBUG("Unknown event received at state ~p: ~p", [Msg, State]),
    recover(),
    {next_state, recovering, MState}.
