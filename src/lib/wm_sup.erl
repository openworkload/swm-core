-module(wm_sup).

-behaviour(supervisor).

-export([start_link/1, init/1, get_child_pid/1]).

-include("wm_log.hrl").

-define(DEFAULT_MAXR, 1).
-define(DEFAULT_MAXT, 60).
-define(DEFAULT_EXIT_TIMEOUT, 20).
-define(STRATEGY, one_for_one).

%% ============================================================================
%% API functions
%% ============================================================================

-spec start_link(list()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Services) when is_list(Services) ->
    supervisor:start_link(?MODULE, Services);
start_link({Services, Args}) when is_list(Services), is_list(Args) ->
    supervisor:start_link(?MODULE, {Services, Args}).

-spec init({list(), list()}) -> {atom(), term()}.
init({Services, Args}) ->
    MaxR = wm_conf:g(srv_max_restarts_count, {?DEFAULT_MAXR, integer}),
    MaxT = wm_conf:g(srv_max_restarts_period, {?DEFAULT_MAXT, integer}),
    SupFlags =
        #{strategy => ?STRATEGY,
          intensity => MaxR,
          period => MaxT,
          auto_shutdown => any_significant},
    {ok, {SupFlags, get_children_spec(Services, Args, [])}};
init(Services) ->
    MaxR = wm_conf:g(srv_max_restarts_count, {?DEFAULT_MAXR, integer}),
    MaxT = wm_conf:g(srv_max_restarts_period, {?DEFAULT_MAXT, integer}),
    SupFlags =
        #{strategy => ?STRATEGY,
          intensity => MaxR,
          period => MaxT,
          auto_shutdown => any_significant},
    {ok, {SupFlags, get_children_spec(Services, [])}}.

-spec get_child_pid(atom() | {atom(), node()} | {global, atom()} | {via, module(), any()} | pid()) -> pid().
get_child_pid(SupRef) ->
    do_get_children_pid(SupRef).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec get_children_spec([module()], list()) -> list().
get_children_spec([], Result) ->
    Result;
get_children_spec([Module | T], Result) ->
    ET = wm_conf:g(srv_exit_timeout, {?DEFAULT_EXIT_TIMEOUT, integer}),
    StartFun = {Module, start_link, [[]]},
    ChildSpec = {Module, StartFun, transient, ET, worker, [Module]},
    get_children_spec(T, [ChildSpec | Result]).

-spec get_children_spec([module()], list(), list()) -> list().
get_children_spec([], _, Result) ->
    Result;
get_children_spec([Module | T], Args, Result) ->
    StartFun = {Module, start_link, [Args]},
    ET = wm_conf:g(srv_exit_timeout, {?DEFAULT_EXIT_TIMEOUT, integer}),
    ChildSpec = {Module, StartFun, transient, ET, worker, [Module]},
    get_children_spec(T, Args, [ChildSpec | Result]).

-spec do_get_children_pid(atom() | {atom(), node()} | {global, atom()} | {via, module(), any()} | pid()) -> pid().
do_get_children_pid(SupRef) ->
    % assume wm_sup serves one and only one child
    [{_, Pid, _, _}] = supervisor:which_children(SupRef),
    Pid.
