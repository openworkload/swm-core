-module(wm_data).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_entity.hrl").
-include("wm_log.hrl").

-define(DEFAULT_COLLECT, 30000).

-record(mstate, {sources = [] :: [atom()], data = [] :: [term()]}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

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
    ?LOG_INFO("Data manager has been started (mstate=~p)", [MState]),
    wm_works:call_asap(?MODULE, start_collection),
    {ok, register_sources(MState)}.

handle_call(start_collection, _, #mstate{} = MState) ->
    ?LOG_DEBUG("Start data collection iterations"),
    N = wm_conf:g(collect_data_interval, {?DEFAULT_COLLECT, integer}),
    wm_utils:wake_up_after(N, collect),
    {reply, ok, MState};
handle_call(Msg, From, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown call from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast(transfer, #mstate{} = MState) ->
    ?LOG_DEBUG("Transfer start for data size ~p", [length(MState#mstate.data)]),
    MState2 = do_transfer(MState),
    {noreply, MState2};
handle_cast({data_sending, Module, Binary, Meta}, #mstate{} = MState) ->
    ?LOG_DEBUG("Receiving ~p bytes for ~p (~p)", [byte_size(Binary), Module, Meta]),
    case wm_utils:is_module_loaded(Module) of
        true ->
            Module:import_data(Meta, Binary);
        _ ->
            ok
    end,
    {noreply, MState};
handle_cast(Msg, #mstate{} = MState) ->
    ?LOG_DEBUG("Received unknown cast: ~p", [Msg]),
    {noreply, MState}.

handle_info(collect, #mstate{} = MState) ->
    MState2 = do_collect(MState),
    gen_server:cast(?MODULE, transfer), % TODO: use scheduler for the transferring
    N = wm_conf:g(collect_data_interval, {?DEFAULT_COLLECT, integer}),
    wm_utils:wake_up_after(N, collect),
    {noreply, MState2};
handle_info(Msg, #mstate{} = MState) ->
    ?LOG_DEBUG("Received info message: ~p", [Msg]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_, #mstate{} = MState, _) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, MState).

-spec register_sources(#mstate{}) -> #mstate{}.
register_sources(#mstate{} = MState) ->
    MState#mstate{sources = [wm_mon]}.

-spec do_collect(#mstate{}) -> #mstate{}.
do_collect(#mstate{} = MState) ->
    F = fun(Module) ->
           case wm_utils:is_module_loaded(Module) of
               true ->
                   try
                       Module:export_data()
                   catch
                       E1:E2 ->
                           ?LOG_ERROR("Error when exporting data from ~p: ~w:~w", [Module, E1, E2]),
                           []
                   end;
               _ ->
                   []
           end
        end,
    DataList = lists:map(F, MState#mstate.sources),
    MState#mstate{data = lists:flatten(DataList)}.

-spec do_transfer(#mstate{}) -> #mstate{}.
do_transfer(#mstate{} = MState) ->
    F = fun(DataInfo) -> send_data(DataInfo) end,
    lists:map(F, MState#mstate.data),
    MState#mstate{data = []}.

-spec send_data({not_found | node_address(), atom(), binary(), term()}) -> ok.
send_data({not_found, _, _, _}) ->
    ?LOG_DEBUG("Destination address is unknown");
send_data({Addr, Module, Binary, Meta}) ->
    wm_api:cast_self({data_sending, Module, Binary, Meta}, [Addr]).
