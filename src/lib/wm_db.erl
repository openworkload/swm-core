-module(wm_db).

-behavior(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([is_running/0, wait_for_table/1, ensure_tables_exist/1, ensure_table_exists/3, ensure_stopped/0,
         ensure_running/0, get_all/1, get_all/2, get_one/3, get_one_2keys/3, get_many/3, get_less_equal/3,
         update_exist/4, update/1, upgrade_schema/1, clear_table/1, force_load_tables/0, table_exists/1,
         get_all_tab_names/0, propagate_tables/2, propagate_tables/3, delete_by_key/2, delete/1, get_hashes/1,
         compare_hashes/2, get_tables_meta/1, create_the_rest_tables/0, get_global/3, get_address/1]).
-export([get_many_pred/2]).
-export([with_transaction/1]).

-include("wm_log.hrl").

-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("stdlib/include/qlc.hrl").

-define(MNESIA_DEFAULT_TIMEOUT, 15000).
-define(MNESIA_DEFAULT_SAVE_PERIOD, 30000).
-define(DEFAULT_PROPAGATION_TIMEOUT, 60000).

-record(mstate, {propagations = maps:new()}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

is_running() ->
    mnesia:system_info(is_running).

ensure_running() ->
    do_ensure_running().

ensure_stopped() ->
    case is_running() of
        yes ->
            stop_db();
        _ ->
            ok
    end.

wait_for_table(TabName) ->
    do_wait_for_table(TabName).

get_all(Tab) ->
    get_records(Tab).

get_all(Tab, MaxReturnedListSize) ->
    get_records({Tab, MaxReturnedListSize}).

get_one(Tab, Attr, Value) ->
    do_get_one(Tab, Attr, Value).

get_one_2keys(Tab, {Attr1, Value1}, {Attr2, Value2}) ->
    do(qlc:q([X
              || X <- mnesia:table(Tab),
                 wm_entity:get_attr(Attr1, X) =:= Value1,
                 wm_entity:get_attr(Attr2, X) =:= Value2])).

get_many(Tab, Attr, Values) ->
    do_get_many(Tab, Attr, Values).

get_less_equal(Tab, Attr, Value) ->
    do(qlc:q([X || X <- mnesia:table(Tab), wm_entity:get_attr(Attr, X) =< Value])).

update_exist(Tab, {KeyName, KeyVal}, Attr, AttrVal) ->
    do_update_exist(Tab, KeyName, KeyVal, Attr, AttrVal).

update(Records) when is_list(Records) ->
    do_update(Records, 0).

upgrade_schema(Json) ->
    ?LOG_DEBUG("Upgrade schema call: ~P", [Json, 10]),
    case do_upgrade_schema(Json, []) of
        [] ->
            ?LOG_DEBUG("Schema is up-to-dated"),
            [];
        Results ->
            ?LOG_DEBUG("Schema is not up-to-dated: ~p", [Results]),
            ExistingTabBins = [wm_entity:get_attr(name, X) || X <- get_records(table)],
            ExistingTabs = [binary_to_atom(X, utf8) || X <- ExistingTabBins],
            NeedTabs = [X || {_, X} <- Results],
            RmTabs = lists:subtract(ExistingTabs, NeedTabs),
            ?LOG_DEBUG("Remove tabs that are not in the new "
                       "schema: ~p",
                       [RmTabs]),
            F = fun() ->
                   [mnesia:delete_table(X) || X <- RmTabs],
                   [mnesia:delete({table, list_to_binary(atom_to_list(X))}) || X <- RmTabs]
                end,
            transaction(F),
            wm_event:announce(schema_updated, node()),
            Results
    end.

force_load_tables() ->
    [mnesia:force_load_table(Tab) || Tab <- mnesia:system_info(tables)].

table_exists(TabName) ->
    do_table_exists(TabName).

get_all_tab_names() ->
    mnesia:system_info(tables).

ensure_table_exists(TabName, Index, Type) when is_atom(TabName) ->
    do_ensure_table(TabName, Index, Type).

ensure_tables_exist(Records) ->
    do_ensure_tables(Records).

propagate_tables(Nodes, MyAddr) ->
    wm_event:subscribe(wm_commit_done, node(), ?MODULE),
    gen_server:cast(?MODULE, {propagate, Nodes, MyAddr}).

propagate_tables(TabNames, Node, MyAddr) ->
    wm_event:subscribe(wm_commit_done, node(), ?MODULE),
    gen_server:cast(?MODULE, {propagate, TabNames, Node, MyAddr}).

-spec delete(term()) -> ok.
delete(Record) ->
    transaction(fun() -> mnesia:delete_object(Record) end).

delete_by_key(TabName, KeyVal) ->
    ?LOG_DEBUG("Delete from ~p where key is ~p", [TabName, KeyVal]),
    transaction(fun() -> mnesia:delete({TabName, KeyVal}) end).

clear_table(TabName) ->
    ?LOG_DEBUG("Clear table ~p", [TabName]),
    mnesia:clear_table(TabName).

get_hashes(schema) ->
    ?LOG_DEBUG("Get schema hashes"),
    AllTabNames = mnesia:system_info(tables),
    NonReplicableTabNames = [schema | wm_entity:get_names(non_replicable)],
    ReplicableTabNames = lists:subtract(AllTabNames, NonReplicableTabNames),
    do_get_tab_attr_hash(ReplicableTabNames, []);
get_hashes(tables) ->
    ?LOG_DEBUG("Get tables content hashes"),
    AllTabNames = mnesia:system_info(tables),
    NonReplicableTabNames = [schema | wm_entity:get_names(non_replicable)],
    ReplicableTabNames = lists:subtract(AllTabNames, NonReplicableTabNames),
    do_get_tab_content_hash(ReplicableTabNames, []).

compare_hashes(content, Hashes) ->
    DifferentTabs = do_compare_hashes(content, Hashes, []),
    ?LOG_DEBUG("Tables, which content differs:  ~p", [DifferentTabs]),
    DifferentTabs.

%% @doc Return fields structures for tables with different hashes
get_tables_meta(Hs) ->
    ?LOG_DEBUG("Get tables meta"),
    Meta = do_get_tables_meta(Hs, []),
    AllTabNames = mnesia:system_info(tables),
    NonReplicableTabNames = [schema | wm_entity:get_names(non_replicable)],
    ReplicableTabNames = lists:subtract(AllTabNames, NonReplicableTabNames),
    ?LOG_DEBUG("Replicable tab names: ~p", [ReplicableTabNames]),
    RemainTabs = do_get_remain_meta(ReplicableTabNames, Hs, []),
    ?LOG_DEBUG("New unknown tables: ~p", [RemainTabs]),
    do_get_tables_meta(RemainTabs, Meta).

%% @doc Create tables that don't exist in db but should
create_the_rest_tables() ->
    do_create_the_rest_tables().

get_global(Name, Type, Default) ->
    do_get_global(Name, Type, Default).

get_address(NodeStr) when is_list(NodeStr) ->
    do_get_address(NodeStr).

-spec get_many_pred(atom(), fun((term()) -> boolean())) -> list().
get_many_pred(Tab, Fun) ->
    do(qlc:q([X || X <- mnesia:table(Tab), Fun(X)])).

-spec with_transaction(fun(() -> term())) -> {ok, term()} | {error, term()}.
with_transaction(Fun) ->
    case mnesia:transaction(Fun) of
        {atomic, Result} ->
            {ok, Result};
        {aborted, Reason} ->
            ?LOG_ERROR("Transaction has aborted: ~p", [Reason]),
            {error, Reason}
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
init(_Args) ->
    process_flag(trap_exit, true),
    MState = #mstate{},
    MnesiaDir = mnesia:system_info(directory),
    ?LOG_INFO("Load DB service (~p)", [MnesiaDir]),
    {ok, MState}.

handle_call(Msg, From, MState) ->
    ?LOG_DEBUG("Unknown call from ~p: ~p", [From, Msg]),
    {reply, error, MState}.

handle_cast({propagate, Node, MyAddr}, MState) ->
    wm_api:cast_self({reset_db_request, MyAddr}, [Node]),
    {noreply, MState};
handle_cast({reset_db_request, From, MyAddr}, MState) ->
    ?LOG_INFO("Recevied reset_db request from ~p", [From]),
    case do_ensure_running() of
        {error, Reason} ->
            wm_api:cast_self({reset_db_reply, {error, Reason}, MyAddr}, [From]);
        _ ->
            try
                Tabs1 = wm_entity:get_names(local),
                Tabs2 = wm_entity:get_names(local_bag),
                Tabs3 = mnesia:system_info(tables),
                Tables = lists:subtract(Tabs3, Tabs1 ++ Tabs2 ++ [schema, table, subscriber]),
                ?LOG_DEBUG("Remove tables: ~p", [Tables]),
                F = fun(T) ->
                       Result = mnesia:delete_table(T),
                       ?LOG_DEBUG("Removing ~p result: ~p", [T, Result])
                    end,
                lists:map(F, Tables),
                ?LOG_DEBUG("Tables have been deleted"),
                wm_api:cast_self({reset_db_reply, ok, MyAddr}, [From])
            catch
                E1:E2 ->
                    ?LOG_ERROR("Tables removal failed: ~p:~p", [E1, E2]),
                    wm_api:cast_self({reset_db_reply, {error, E2}, MyAddr}, [From])
            end
    end,
    {noreply, MState};
handle_cast({reset_db_reply, Result, From}, MState) ->
    case Result of
        {error, Error} ->
            ?LOG_DEBUG("Cannot reset db on node ~p: ~p", [From, Error]),
            {noreply, MState};
        ok ->
            ?LOG_DEBUG("Function reset_db() on node ~p has finished", [From]),
            All = wm_entity:get_names(all),
            NonReplTabs = wm_entity:get_names(non_replicable),
            ReplTabs = lists:subtract(All, NonReplTabs),
            MState2 = do_propagate_tables(ReplTabs, [From], MState),
            {noreply, MState2}
    end;
handle_cast({propagate, TabNames, Node, MyAddr}, MState) ->
    wm_api:cast_self({reset_tabs_request, TabNames, MyAddr}, [Node]),
    {noreply, MState};
handle_cast({reset_tabs_request, TabNames, From}, MState) ->
    MyAddr = wm_conf:get_my_relative_address(From),
    ?LOG_INFO("Received reset_tabs request from ~p: ~p", [From, TabNames]),
    case do_ensure_running() of
        {error, Reason} ->
            wm_api:cast_self({reset_tabs_reply, {error, Reason}, MyAddr}, [From]);
        _ ->
            try
                F = fun (node) ->
                            ?LOG_INFO("Preserve nodes table from removal");
                        (T) ->
                            Result = mnesia:delete_table(T),
                            ?LOG_DEBUG("Removing ~p result: ~p", [T, Result])
                    end,
                lists:map(F, TabNames),
                ?LOG_DEBUG("Tables have been deleted: ~p", [TabNames]),
                wm_api:cast_self({reset_tabs_reply, {ok, TabNames}, MyAddr}, [From])
            catch
                E1:E2 ->
                    ?LOG_ERROR("Tables removal has failed: ~p:~p", [E1, E2]),
                    wm_api:cast_self({reset_tabs_reply, {error, E2}, MyAddr}, [From])
            end
    end,
    {noreply, MState};
handle_cast({reset_tabs_reply, Result, From}, MState) ->
    case Result of
        {error, Error} ->
            ?LOG_DEBUG("Couldn't reset tables on ~p: ~p", [From, Error]),
            {noreply, MState};
        {ok, TabNames} ->
            ?LOG_DEBUG("reset_tabs call to node ~p has finished", [From]),
            MState2 = do_propagate_tables(TabNames, [From], MState),
            {noreply, MState2}
    end;
handle_cast({event, EventType, EventData}, MState) ->
    {noreply, handle_event(EventType, EventData, MState)};
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Received unknown cast message: ~p", [Msg]),
    {noreply, MState}.

handle_info({check_propagation, COMMIT_ID}, MState) ->
    case maps:is_key(COMMIT_ID, MState#mstate.propagations) of
        true ->
            ?LOG_DEBUG("Propagation ~p timeout detected", [COMMIT_ID]),
            Map = maps:remove(COMMIT_ID, MState#mstate.propagations),
            {noreply, MState#mstate{propagations = Map}};
        false ->
            ?LOG_DEBUG("Propagation ~p has already finished", [COMMIT_ID]),
            {noreply, MState}
    end;
handle_info({mnesia_table_event, {Type, X, Y}}, MState) ->
    ?LOG_DEBUG("Got mnesia table ~p-event: ~p, ~p", [Type, X, Y]),
    {noreply, MState};
handle_info(Other, MState) ->
    ?LOG_DEBUG("Got unknown message: ~p", [Other]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, Data, _Extra) ->
    {ok, Data}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

handle_event(wm_commit_done, {COMMIT_ID, _}, MState) ->
    ?LOG_DEBUG("Some commit ~p finish has detected", [COMMIT_ID]),
    case maps:is_key(COMMIT_ID, MState#mstate.propagations) of
        false ->
            MState;
        true ->
            ?LOG_DEBUG("Propagation ~p has finished", [COMMIT_ID]),
            Nodes = maps:get(COMMIT_ID, MState#mstate.propagations),
            wm_event:announce(reconfigured_node, Nodes),
            Map = maps:remove(COMMIT_ID, MState#mstate.propagations),
            MState#mstate{propagations = Map}
    end.

start_db() ->
    case mnesia:system_info(is_running) of
        no ->
            case mnesia:start() of
                {error, Reason} ->
                    ?LOG_DEBUG("Mnesia could not be started: ~p", [Reason]),
                    {error, Reason};
                ok ->
                    ok
            end;
        yes ->
            ok
    end.

do_ensure_running() ->
    case mnesia:system_info(use_dir) of
        false ->
            mnesia:stop(),
            ?LOG_DEBUG("Schema does not exist: create schema"),
            case mnesia:create_schema([node()]) of
                ok ->
                    ?LOG_DEBUG("Schema has been created successfully"),
                    start_db();
                {error, Reason} ->
                    ?LOG_DEBUG("Could not create schema: ~p", [Reason]),
                    {error, Reason}
            end;
        true ->
            ?LOG_DEBUG("Configuration exists"),
            start_db()
    end.

do(Q) ->
    F = fun() -> qlc:e(Q) end,
    transaction(F).

get_many_tabs_records([], AllRecords) ->
    AllRecords;
get_many_tabs_records([TabName | RestTabNames], AllRecords) ->
    TabRecords = do(qlc:q([X || X <- mnesia:table(TabName)])),
    get_many_tabs_records(RestTabNames, lists:append(TabRecords, AllRecords)).

get_records(TabNames) when is_list(TabNames) ->
    get_many_tabs_records(TabNames, []);
get_records({TabName, MaxReturnedListSize}) ->
    CatchAll = [{'_', [], ['$_']}],
    F = fun() -> mnesia:select(TabName, CatchAll, MaxReturnedListSize, read) end,
    case transaction(F) of
        {Objects, _} ->
            Objects;
        [] ->
            []
    end;
get_records(TabName) ->
    do(qlc:q([X || X <- mnesia:table(TabName)])).

do_update([], Result) ->
    Result;
do_update([{Rec, false} | T], Result) ->
    ?LOG_DEBUG("Update DB with record: ~P (no revision "
               "change)",
               [Rec, 10]),
    F = fun() -> ok = mnesia:write(Rec) end,
    transaction(F),
    do_update(T, Result + 1);
do_update([Rec | T], Result) ->
    ?LOG_DEBUG("Update DB with record: ~P", [Rec, 10]),
    %Revision = wm_entity:get_attr(revision, Rec),
    %NewRec = wm_entity:set_attr({revision, Revision+1}, Rec),
    %?LOG_DEBUG("Changed revision record: ~P", [NewRec, 10]),
    F = fun() -> ok = mnesia:write(Rec) end,
    transaction(F),
    do_update(T, Result + 1).

%% TODO: for error try return error atom,
%% or specify on_error argument in transaction function contract
-spec transaction(term()) -> term() | [].
transaction(F) ->
    case mnesia:transaction(F) of
        {atomic, Val} ->
            Val;
        {aborted, Reason} ->
            ?LOG_ERROR("Transaction has aborted: ~p", [Reason]),
            []
    end.

create_table(TabName, Index, Type) ->
    ?LOG_DEBUG("Create table ~p (index=~p, type=~p)", [TabName, Index, Type]),
    Opts =
        case Type of
            shared ->
                get_tab_opts(TabName, Index, shared);
            local ->
                get_tab_opts(TabName, Index, local);
            local_bag ->
                get_tab_opts(TabName, Index, local_bag)
        end,
    ?LOG_DEBUG("Create table ~p with options: ~p", [TabName, Opts]),
    case mnesia:create_table(TabName, Opts) of
        {atomic, ok} ->
            ?LOG_DEBUG("Empty ~p table has been created: ~w", [Type, TabName]);
        {aborted, Reason} ->
            ?LOG_ERROR("Cannot create ~p table ~w: ~p", [Type, TabName, Reason])
    end.

get_shared_tab_opts(TabName, Index, Type) ->
    AutoSave = get_global("db_save_period", integer, ?MNESIA_DEFAULT_SAVE_PERIOD),
    [{attributes, wm_entity:get_fields(TabName)},
     {disc_copies, [node()]},
     {index, Index},
     {type, Type},
     {storage_properties, [{ets, []}, {dets, [{auto_save, AutoSave}]}]},
     {local_content, false}].

get_local_tab_opts(TabName, Index, Type) ->
    AutoSave = get_global("db_save_period", integer, ?MNESIA_DEFAULT_SAVE_PERIOD),
    [{attributes, wm_entity:get_fields(TabName)},
     {disc_copies, [node()]},
     {index, Index},
     {type, Type},
     {storage_properties, [{ets, []}, {dets, [{auto_save, AutoSave}]}]},
     {local_content, true}].

do_ensure_table(TabName, Index, Type) ->
    case table_exists(TabName) of
        true ->
            ok;
        false ->
            create_table(TabName, Index, Type),
            wait_for_table(TabName)
    end.

do_ensure_tables([]) ->
    ok;
do_ensure_tables([Tab | T]) ->
    TabName = element(1, Tab),
    ExtraIndexes = [],
    do_ensure_table(TabName, ExtraIndexes, local),
    do_ensure_tables(T).

get_tab_opts(Tab, Index, local_bag) ->
    get_local_tab_opts(Tab, Index, bag);
get_tab_opts(Tab, Index, local) ->
    get_local_tab_opts(Tab, Index, set);
get_tab_opts(Tab, Index, shared) ->
    get_shared_tab_opts(Tab, Index, set).

stop_db() ->
    ?LOG_INFO("Stop database"),
    case mnesia:system_info(is_running) of
        yes ->
            {ok, mnesia:stop()};
        starting ->
            {ok, mnesia:stop()};
        _ ->
            ?LOG_INFO("Database has already stopped"),
            {ok, stopped}
    end.

do_propagate_tables(TabNames, Nodes, MState) ->
    ?LOG_DEBUG("Do propagate ~p to ~w", [TabNames, Nodes]),
    Records = get_records(TabNames),
    ?LOG_DEBUG("Do propagate tables to ~p", [Nodes]),
    case wm_factory:new(commit, Records, Nodes) of
        {ok, COMMIT_ID} ->
            Map = maps:put(COMMIT_ID, Nodes, MState#mstate.propagations),
            wm_utils:wake_up_after(?DEFAULT_PROPAGATION_TIMEOUT, {check_propagation, COMMIT_ID}),
            MState#mstate{propagations = Map};
        timeout ->
            ?LOG_ERROR("Propagation cannot be started right "
                       "now"),
            MState
    end.

do_table_exists(TabName) ->
    Tables = mnesia:system_info(tables),
    lists:member(TabName, Tables).

do_wait_for_table(TabName) ->
    MnesiaTimeout = get_global("db_timeout", integer, ?MNESIA_DEFAULT_TIMEOUT),
    case do_table_exists(TabName) of
        false ->
            {error, table_not_found};
        true ->
            case mnesia:wait_for_tables([TabName], MnesiaTimeout) of
                ok ->
                    ok;
                {timeout, TabName} ->
                    ?LOG_ERROR("Timeout: we've been waiting for table "
                               "~w more then ~ps.",
                               [TabName, MnesiaTimeout / 1000]),
                    {error, timeout};
                {error, Reason} ->
                    ?LOG_ERROR("Error when waiting for table ~p: ~p", [TabName, Reason]),
                    {error, Reason};
                Error ->
                    ?LOG_ERROR("Error when waiting for table ~p: ~p", [TabName, Error]),
                    {error, Error}
            end
    end.

do_get_many(Tab, Attr, Values) ->
    Result =
        do(qlc:q([X || X <- mnesia:table(Tab), lists:any(fun(Y) -> wm_entity:get_attr(Attr, X) =:= Y end, Values)])),
    Result.

do_get_tables_meta([], Meta) ->
    Meta;
do_get_tables_meta([{TabName, ReqHash} | T], Meta) ->
    case do_get_tab_attr_hash(TabName) of
        ReqHash ->
            ?LOG_DEBUG("Requested hash is the same: ~p (~p)", [ReqHash, TabName]),
            do_get_tables_meta(T, Meta);
        Other ->
            ?LOG_DEBUG("Req hash ~p differs from ~p (~p)", [ReqHash, Other, TabName]),
            TabNameBin = list_to_binary(atom_to_list(TabName)),
            M = try
                    do(qlc:q([X || X <- mnesia:table(table), wm_entity:get_attr(name, X) =:= TabNameBin]))
                catch
                    E1:E2 ->
                        ?LOG_ERROR("Transaction failed: ~p:~p", [E1, E2]),
                        []
                end,
            case M of
                [] ->
                    ?LOG_ERROR("Could not get table ~p meta (not found)", [TabName]),
                    do_get_tables_meta(T, Meta);
                _ ->
                    R = hd(M),
                    Fields = wm_entity:get_attr(fields, R),
                    Name = wm_entity:get_attr(name, R),
                    S = {Name, {struct, Fields}},
                    ?LOG_DEBUG("Got meta for table ~p: ~P", [TabNameBin, R, 10]),
                    do_get_tables_meta(T, [S | Meta])
            end
    end.

do_get_remain_meta([], _, Remain) ->
    Remain;
do_get_remain_meta([Tab | T], RemoteHashes, Remain) ->
    case lists:keyfind(Tab, 1, RemoteHashes) of
        false ->
            do_get_remain_meta(T, RemoteHashes, [{Tab, <<0>>} | Remain]);
        _ ->
            do_get_remain_meta(T, RemoteHashes, Remain)
    end.

do_compare_hashes(content, [], DifferentTabs) ->
    DifferentTabs;
do_compare_hashes(content, [{TabName, CheckHash} | T], DifferentTabs) ->
    LocalHash = do_get_tab_content_hash(TabName),
    case LocalHash of
        CheckHash ->
            ?LOG_DEBUG("Hash is the same: ~p (~p)", [CheckHash, TabName]),
            do_compare_hashes(content, T, DifferentTabs);
        _ ->
            ?LOG_DEBUG("Hashes differ: ~p != ~p (~p)", [CheckHash, LocalHash, TabName]),
            do_compare_hashes(content, T, [TabName | DifferentTabs])
    end.

do_get_tab_content_hash([], Hs) ->
    Hs;
do_get_tab_content_hash([TabName | T], Hs) ->
    ?LOG_DEBUG("Do get tables content hashes: ~p", [TabName]),
    H = do_get_tab_content_hash(TabName),
    do_get_tab_content_hash(T, [{TabName, H} | Hs]).

do_get_tab_content_hash(TabName) ->
    L1 = try
             get_records(TabName)
         catch
             E1:E2 ->
                 ?LOG_ERROR("Could not get content of table ~p: ~p:~p", [TabName, E1, E2]),
                 []
         end,
    L2 = replace_incomparible_fields(TabName, L1),
    F = fun(X, Y) -> wm_entity:get_attr(name, X) < wm_entity:get_attr(name, Y) end,
    L3 = lists:sort(F, L2),
    Data =
        lists:flatten(
            io_lib:format("~p", [L3])),
    crypto:hash(md5, Data).

replace_incomparible_fields(TabName, Records) ->
    IncomFields = wm_entity:get_incomparible_fields(TabName),
    F1 = fun(Field, Rec) -> wm_entity:set_attr({Field, incomparible}, Rec) end,
    F2 = fun(Rec) -> lists:foldr(F1, Rec, IncomFields) end,
    [F2(X) || X <- Records].

do_get_tab_attr_hash([], Hs) ->
    Hs;
do_get_tab_attr_hash([TabName | T], Hs) ->
    ?LOG_DEBUG("Do get tables hashes: ~p", [TabName]),
    H = do_get_tab_attr_hash(TabName),
    do_get_tab_attr_hash(T, [{TabName, H} | Hs]).

do_get_tab_attr_hash(TabName) ->
    L = try
            mnesia:table_info(TabName, attributes)
        catch
            E1:E2 ->
                ?LOG_ERROR("Could not get attrs for ~p: ~p:~p", [TabName, E1, E2]),
                []
        end,
    Data =
        lists:flatten(
            io_lib:format("~p", [L])),
    crypto:hash(md5, Data).

do_upgrade_schema([], Result) ->
    Result;
do_upgrade_schema([RecordJson | T], Result) ->
    case do_update_tables_table(RecordJson) of
        ok ->
            R = do_transform_table(RecordJson),
            do_upgrade_schema(T, [{atom, R} | Result]);
        {error, Error} ->
            ?LOG_ERROR("Upgrade schema error: ~p", [Error]),
            do_upgrade_schema(T, [{string, Error} | Result]);
        Other ->
            ?LOG_ERROR("Unrecognized result: ~p", [Other])
    end.

do_update_tables_table({NameBin, {struct, Fields}}) ->
    ?LOG_DEBUG("Update table 'table'"),
    ensure_table_exists(table, [], local),
    R1 = wm_entity:new(<<"table">>),
    R2 = wm_entity:set_attr({name, NameBin}, R1),
    R3 = wm_entity:set_attr({fields, Fields}, R2),
    ?LOG_DEBUG("Meta information for table ~p: ~P", [NameBin, R3, 10]),
    case do_update([R3], 0) of
        1 ->
            ?LOG_DEBUG("Meta information for table ~p has been "
                       "updated",
                       [NameBin]),
            ok;
        Other ->
            ?LOG_DEBUG("Error in updating meta information for "
                       "table ~p",
                       [NameBin]),
            {error, Other}
    end.

do_transform_table({NameBin, {struct, Fields}}) ->
    ?LOG_DEBUG("Transform table ~p", [NameBin]),
    Name = binary_to_atom(NameBin, utf8),
    {New, NewFields, Defaults} = record_from_json(Fields, wm_entity:new(NameBin), [], []),
    OldFields =
        try
            mnesia:table_info(Name, attributes)
        catch
            _:_ ->
                []
        end,
    T = fun(Old) ->
           OldMap = get_attr_map(Old, OldFields, 2, maps:new()),
           ?LOG_DEBUG("Map for old record ~p: ~p", [Name, maps:to_list(OldMap)]),
           NewRec = merge_records(Old, New, OldMap, NewFields, Defaults),
           ?LOG_DEBUG("Merged record: ~P", [NewRec, 5]),
           NewRec
        end,
    ?LOG_DEBUG("New default record: ~p", [New]),
    ?LOG_DEBUG("Old fields: ~p", [OldFields]),
    ?LOG_DEBUG("New fields: ~p", [NewFields]),
    case table_exists(Name) of
        true ->
            case mnesia:transform_table(Name, T, NewFields, Name) of
                {atomic, ok} ->
                    ?LOG_DEBUG("Transformation of table '~p' has completed", [Name]),
                    Name;
                {aborted, Error} ->
                    ?LOG_ERROR("Transformation of '~s' has aborted: ~p", [Name, Error]),
                    {error, Error};
                Error ->
                    ?LOG_ERROR("Failed to transform table '~s': ~p", [Name, Error]),
                    {error, Error}
            end;
        false ->
            ExtraIndexes = [],
            ensure_table_exists(Name, ExtraIndexes, local),
            Name
    end.

record_from_json([], NewRec, NewFields, Defaults) ->
    {NewRec, lists:reverse(NewFields), lists:reverse(Defaults)};
record_from_json([JsonRecordField | T], NewRec, NewFields, Defaults) ->
    {FieldName, Default, _} = wm_entity:extract_json_field_info(JsonRecordField),
    NewRec2 =
        try
            wm_entity:set_attr({FieldName, Default}, NewRec)
        catch
            E1:E2 ->
                ?LOG_ERROR("Set attribute exception: ~p:~p (should "
                           "schema be imported?)",
                           [E1, E2]),
                []
        end,
    record_from_json(T, NewRec2, [FieldName | NewFields], [{FieldName, Default} | Defaults]).

merge_records(_, New, _, [], _) ->
    ?LOG_DEBUG("New particular record: ~P", [New, 5]),
    New;
merge_records(Old, New, OldMap, [NewField | NewFields], [{NewField, Default} | Defaults]) ->
    ?LOG_DEBUG("Merge records ~P and ~P", [Old, 5, New, 5]),
    NewValue = maps:get(NewField, OldMap, Default),
    ?LOG_DEBUG("Field '~p' will be merged with value: ~P", [NewField, NewValue, 5]),
    merge_records(Old, wm_entity:set_attr({NewField, NewValue}, New), OldMap, NewFields, Defaults).

get_attr_map(_, [], _, Map) ->
    Map;
get_attr_map(Rec, [Name | T], Next, Map) ->
    Value = erlang:element(Next, Rec),
    get_attr_map(Rec, T, Next + 1, maps:put(Name, Value, Map)).

do_get_global(Name, string, Default) ->
    try
        Q = qlc:q([X || X <- mnesia:table(global), wm_entity:get_attr(name, X) =:= Name]),
        {atomic, Rs} = mnesia:transaction(fun() -> qlc:e(Q) end),
        case wm_entity:get_attr(value, hd(Rs)) of
            "" ->
                Default;
            X ->
                X
        end
    catch
        _:_ ->
            Default
    end;
do_get_global(Name, record, Default) ->
    try
        Q = qlc:q([X || X <- mnesia:table(global), wm_entity:get_attr(name, X) =:= Name]),
        {atomic, Rs} = mnesia:transaction(fun() -> qlc:e(Q) end),
        hd(Rs)
    catch
        _:_ ->
            Default
    end;
do_get_global(Name, integer, Default) ->
    try
        Q = qlc:q([X || X <- mnesia:table(global), wm_entity:get_attr(name, X) =:= Name]),
        {atomic, Rs} = mnesia:transaction(fun() -> qlc:e(Q) end),
        X = wm_entity:get_attr(value, hd(Rs)),
        list_to_integer(X)
    catch
        _:_ ->
            Default
    end.

do_create_the_rest_tables() ->
    ?LOG_DEBUG("Create the rest tables"),
    NeedTabs = wm_entity:get_names(all),
    LocalTabs = wm_entity:get_names(local),
    LocalBagTabs = wm_entity:get_names(local_bag),
    HaveTabs = get_all_tab_names(),
    AbsentTabs = lists:subtract(NeedTabs, HaveTabs),
    SharedTabs = lists:subtract(AbsentTabs, LocalTabs),
    SharedTabs2 = lists:subtract(SharedTabs, LocalBagTabs),
    ?LOG_DEBUG("Absent tables: ~w", [AbsentTabs]),
    ?LOG_DEBUG("Create empty shared tables: ~w", [SharedTabs2]),
    ?LOG_DEBUG("Create empty local tables: ~w", [LocalTabs]),
    ?LOG_DEBUG("Create empty local_bag tables: ~w", [LocalBagTabs]),
    ExtraIndexes = [],
    lists:foreach(fun(T) -> ensure_table_exists(T, ExtraIndexes, shared) end, SharedTabs2),
    lists:foreach(fun(T) -> ensure_table_exists(T, ExtraIndexes, local) end, LocalTabs),
    lists:foreach(fun(T) -> ensure_table_exists(T, ExtraIndexes, local_bag) end, LocalBagTabs),
    Num = length(AbsentTabs),
    ?LOG_DEBUG("The rest tables were created: ~p", [Num]),
    Num.

do_get_one(Tab, Attr, Value) ->
    do(qlc:q([X || X <- mnesia:table(Tab), wm_entity:get_attr(Attr, X) =:= Value])).

do_get_address(NodeStr) when is_list(NodeStr) ->
    X = case lists:any(fun ($@) ->
                               true;
                           (_) ->
                               false
                       end,
                       NodeStr)
        of
            true ->
                [Part1, Part2] = string:tokens(NodeStr, "@"),
                do(qlc:q([X
                          || X <- mnesia:table(node),
                             wm_entity:get_attr(name, X) =:= Part1,
                             wm_entity:get_attr(host, X) =:= Part2]));
            false ->
                do(qlc:q([X || X <- mnesia:table(node), wm_entity:get_attr(name, X) =:= NodeStr]))
        end,
    case X of
        [Rec] ->
            Host = wm_entity:get_attr(host, Rec),
            Port = wm_entity:get_attr(api_port, Rec),
            {Host, Port};
        E ->
            ?LOG_ERROR("Could not get address (got ~p)", [E]),
            not_found
    end.

do_update_exist(Tab, KeyName, KeyVal, Attr, AttrVal) ->
    F = fun() ->
           Q = qlc:q([X || X <- mnesia:table(Tab), wm_entity:get_attr(KeyName, X) =:= KeyVal]),
           case qlc:eval(Q) of
               [OldRec | _] ->
                   NewRec = wm_entity:set_attr({Attr, AttrVal}, OldRec),
                   mnesia:write(Tab, NewRec, sticky_write);
               Other ->
                   ?LOG_DEBUG("Weird search result: ~p", [Other])
           end
        end,
    transaction(F).
