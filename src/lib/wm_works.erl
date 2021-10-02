-module(wm_works).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([call_asap/2, call_thread/2, enable/0, disable/0]).

-include("wm_entity.hrl").
-include("wm_log.hrl").

-define(PARALLEL_CALLS, 2).
-define(LOCAL_CALL_TIMEOUT, 60000).

-record(mstate, {enabled = false :: boolean(), tasks = [] :: [{module(), term()}]}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%%doc Ask to call some (heavy) function later. The function must be exported.
-spec call_asap(atom(), term()) -> ok.
call_asap(Module, Message) ->
    gen_server:cast(?MODULE, {call_asap, Module, Message}).

%%doc Enable tasks execution from queue.
-spec enable() -> ok.
enable() ->
    gen_server:cast(?MODULE, enable).

%%doc Disable tasks execution. Existing and new tasks will be queued.
-spec disable() -> ok.
disable() ->
    gen_server:cast(?MODULE, disable).

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
    ?LOG_DEBUG("Load heavy works module"),
    process_flag(trap_exit, true),
    MState = #mstate{},
    {ok, MState}.

handle_call(Msg, From, MState) ->
    ?LOG_ERROR("Received unknown call from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast(enable, MState) ->
    ?LOG_DEBUG("Enable heavy tasks execution"),
    {noreply, continue(MState)};
handle_cast(disable, MState) ->
    ?LOG_DEBUG("Disable heavy tasks execution"),
    {noreply, MState#mstate{enabled = false}};
handle_cast({call_asap, Module, Message}, MState) ->
    ?LOG_DEBUG("Received request to call ~p, message: ~p", [Module, Message]),
    P = wm_conf:g(srv_parallel_works, {?PARALLEL_CALLS, integer}),
    case MState#mstate.enabled of
        true ->
            MState2 = append_task(Module, Message, MState),
            {Tasks, T} =
                if length(MState2#mstate.tasks) =< P ->
                       {MState2#mstate.tasks, []};
                   true ->
                       lists:split(P, MState2#mstate.tasks)
                end,
            ?LOG_DEBUG("Tasks to execute now: ~p, remaining tasks: ~w", [Tasks, T]),
            %% TODO: Don't remove task from module state, until ?MODULE received
            %% {'EXIT', Pid, normal} message. In case {'EXIT', Pid, Reason} received re-enqueue task.
            F = fun({TaskModule, TaskMessage}) ->
                   Pid = spawn_link(?MODULE, call_thread, [TaskModule, TaskMessage]),
                   ?LOG_DEBUG("Process ~p has been spawned", [Pid])
                end,
            lists:map(F, Tasks),
            {noreply, continue(MState2#mstate{tasks = T})};
        false ->
            {noreply, append_task(Module, Message, MState)}
    end;
handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Received unknown cast message: ~p", [Msg]),
    {noreply, MState}.

handle_info({'EXIT', Pid, normal}, MState) ->
    ?LOG_DEBUG("Process ~p has finished normally", [Pid]),
    {noreply, MState};
handle_info(Info, MState) ->
    ?LOG_DEBUG("Received unknown info message: ~p", [Info]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec continue(#mstate{}) -> #mstate{}.
continue(MState) ->
    Tasks = MState#mstate.tasks,
    case Tasks of
        [] ->
            MState#mstate{enabled = true};
        List when is_list(List) ->
            {Head, [{Module, Message}]} = lists:split(length(List) - 1, List),
            gen_server:cast(?MODULE, {call_asap, Module, Message}),
            MState#mstate{enabled = true, tasks = Head}
    end.

-spec call_thread(module(), term()) -> any().
call_thread(Module, Message) ->
    T = wm_conf:g("srv_local_call_timeout", {?LOCAL_CALL_TIMEOUT, integer}),
    gen_server:call(Module, Message, T).

-spec append_task(module(), term(), #mstate{}) -> #mstate{}.
append_task(Module, Message, MState) ->
    Tasks = lists:append(MState#mstate.tasks, [{Module, Message}]),
    MState#mstate{tasks = Tasks}.
