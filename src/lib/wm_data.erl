-module(wm_data).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_log.hrl").

-define(DEFAULT_COLLECT, 30000).

-record(mstate, {sources = [], data = []}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% ============================================================================
%% Callbacks
%% ============================================================================

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

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, MState).

register_sources(#mstate{} = MState) ->
    MState#mstate{sources = [wm_mon]}.

do_collect(#mstate{} = MState) ->
    F = fun(Module) ->
           case wm_utils:is_module_loaded(Module) of
               true ->
                   try
                       Module:export_data()
                   catch
                       E1:E2 ->
                           ?LOG_ERROR("Error when exporting data from ~p: ~p:~p", [Module, E1, E2]),
                           []
                   end;
               _ ->
                   []
           end
        end,
    DataList = lists:map(F, MState#mstate.sources),
    MState#mstate{data = lists:flatten(DataList)}.

do_transfer(#mstate{} = MState) ->
    F = fun(DataInfo) -> send_data(DataInfo) end,
    lists:map(F, MState#mstate.data),
    MState#mstate{data = []}.

send_data({Addr, Module, Binary, Meta}) ->
    wm_api:cast_self({data_sending, Module, Binary, Meta}, [Addr]).
