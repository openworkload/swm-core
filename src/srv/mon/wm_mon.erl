-module(wm_mon).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([new/2, update/2, get_values/2, import_data/2, export_data/0]).

-include("../../lib/wm_log.hrl").

-include_lib("folsom/include/folsom.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-record(mstate, {}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec new(atom(), atom()) -> term().
new(MetricType, MetricName) ->
    gen_server:cast(?MODULE, {new, MetricType, MetricName}).

-spec update(atom(), term()) -> term().
update(MetricName, Value) ->
    gen_server:cast(?MODULE, {update, MetricName, Value}).

-spec get_values(atom(), {number(), number()}) -> term().
get_values(MetricName, Conditions) ->
    wm_utils:protected_call(?MODULE, {get_values, MetricName, Conditions}, []).

-spec export_data() -> {tuple(), atom(), binary(), term()}.
export_data() ->
    wm_utils:protected_call(?MODULE, export_data, []).

-spec import_data(term(), binary()) -> ok.
import_data(Meta, Data) ->
    wm_utils:protected_call(?MODULE, {import_data, Meta, Data}, []).

%% ============================================================================
%% Callbacks
%% ============================================================================

init(Args) ->
    ?LOG_INFO("Load monitoring service"),
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    wm_event:subscribe(http_started, node(), ?MODULE),
    wm_event:announce(mon_started),
    {ok, MState}.

handle_call({import_data, Meta, Data}, _, #mstate{} = MState) ->
    ?LOG_DEBUG("Import data (meta=~p)", [Meta]),
    {reply, do_import_data(Meta, Data), MState};
handle_call(export_data, _, #mstate{} = MState) ->
    ?LOG_DEBUG("Export data"),
    {reply, do_export_data(), MState};
handle_call({get_values, Name, {Begin, End, Limit}}, _, #mstate{} = MState) ->
    ?LOG_DEBUG("Get metric ~p values for [~p; ~p] ~p", [Name, Begin, End, Limit]),
    Values = do_get_values_in_interval(Name, Begin, End, Limit),
    {reply, Values, MState};
handle_call(Msg, From, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown call from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast({new, history, Name}, #mstate{} = MState) ->
    ?LOG_DEBUG("Add new history metric ~p", [Name]),
    folsom_metrics:new_history(Name),
    {noreply, MState};
handle_cast({update, Name, Value}, #mstate{} = MState) ->
    ?LOG_DEBUG("Update metric ~p: ~p", [Name, Value]),
    ok = folsom_metrics:notify(Name, Value),
    {noreply, MState};
handle_cast({event, EventType, EventData}, MState) ->
    {noreply, handle_event(EventType, EventData, MState)};
handle_cast(Msg, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown cast: ~p", [Msg]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

handle_info(Msg, #mstate{} = MState) ->
    ?LOG_DEBUG("Received info message: ~p", [Msg]),
    {noreply, MState}.

code_change(_, Data, _) ->
    {ok, Data}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

handle_event(http_started, _, #mstate{} = MState) ->
    ?LOG_INFO("Initialize REST API resources"),
    wm_http:add_route({api, wm_mon_rest}, "/mon"),
    MState.

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, #mstate{} = MState).

do_export_data() ->
    case wm_self:has_role("grid") of
        true ->
            ?LOG_DEBUG("Grid manager role is assigned => do "
                       "not export metrics"),
            [];
        false ->
            MetricNames = folsom_metrics:get_metrics(),
            ?LOG_DEBUG("Exporting metrics: ~p", [MetricNames]),
            F = fun(MetricName) ->
                   #history{tid = Tid} = folsom_metrics_history:get_value(MetricName),
                   Rows =
                       case ets:info(Tid) of
                           undefined ->
                               ?LOG_DEBUG("No values found for metric ~p", [MetricName]),
                               [];
                           _ ->
                               TabRows = ets:tab2list(Tid),
                               true = ets:delete_all_objects(Tid),
                               TabRows
                       end,
                   {MetricName, Rows}
                end,
            All = lists:map(F, MetricNames),
            %?LOG_DEBUG("Export metrics: ~p", [All]),
            Bin = wm_utils:encode_to_binary(All),
            Addr = wm_core:get_parent(),
            {Addr, ?MODULE, Bin, metrics_transferring}
    end.

do_import_data(metrics_transferring, Bin) when is_binary(Bin) ->
    ?LOG_DEBUG("Importing metrics from binary of size ~p", [byte_size(Bin)]),
    All = wm_utils:decode_from_binary(Bin),
    F1 = fun({MetricName, Rows}) ->
            #history{tid = Tid} = folsom_metrics_history:get_value(MetricName),
            F2 = fun({Key, Value}) ->
                    %?LOG_DEBUG("Import metric: {~p, ~p}", [Key, Value]),
                    case ets:lookup(Tid, Key) of
                        [{Key, List}] ->
                            true = ets:insert(Tid, {Key, List ++ Value});
                        _ ->
                            true = ets:insert(Tid, {Key, Value})
                    end
                 end,
            lists:map(F2, Rows)
         end,
    Results = lists:map(F1, All),
    ?LOG_DEBUG("Importing results: ~p", [Results]),
    Results.

do_get_values_in_interval(Name, BeginTime, EndTime, Limit) ->
    MS1 = ets:fun2ms(fun({T, _} = A) when T > BeginTime, T < EndTime -> A end),
    #history{tid = Tid} = folsom_metrics_history:get_value(Name),
    case ets:select(Tid, MS1, Limit) of
        {Xs1, '$end_of_table'} ->
            Xs1;
        {Xs1, _} ->
            ?LOG_DEBUG("Not all metrics were selected for [~p; "
                       "~p])",
                       [BeginTime, EndTime]),
            Xs1;
        '$end_of_table' ->
            ?LOG_DEBUG("No metrics were selected for [~p; ~p])", [BeginTime, EndTime]),
            []
    end.
