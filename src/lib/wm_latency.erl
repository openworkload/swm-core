-module(wm_latency).

-behaviour(gen_server).

-export([start_link/1]).
-export([ping/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("wm_log.hrl").

-record(mstate, {}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec ping(node(), integer()) -> integer().
%% @doc Measure send-receive time, where N is a number of measurements
ping(Node, Trials) ->
    gen_server:call(?MODULE, {ping, Node, Trials}).

%% ============================================================================
%% Server callbacks
%% ============================================================================

handle_call({ping, Node, Trials}, _From, MState) ->
    {reply, do_ping_avg(Node, Trials), MState};
handle_call(measure, _From, MState) ->
    {reply, pong, MState};
handle_call(_Msg, _From, MState) ->
    {reply, {error, not_handled}, MState}.

handle_cast(_Msg, MState) ->
    {noreply, MState}.

handle_info(_Info, MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @hidden
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_INFO("Network latency measurement module has "
              "been started"),
    {ok, MState}.

parse_args([], MState) ->
    MState;
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

do_ping_avg(Node, Trials) ->
    Me = node(),
    case Node of
        Me ->
            1;
        _ ->
            L = do_pings(Node, Trials, []),
            ?LOG_DEBUG("Measurements for ~p: ~p", [Node, L]),
            Length = length(L),
            round(lists:foldl(fun(X, Sum) -> X + Sum end, 0, L) / Length)
    end.

do_pings(_, 0, L) ->
    L;
do_pings(Node, Trials, L) ->
    Args = [{wm_latency, Node}, measure],
    case timer:tc(wm_utils, protected_call, Args) of
        {T, pong} ->
            do_pings(Node, Trials - 1, [T | L]);
        _ ->
            [0]
    end.
