-module(wm_sup).

-behaviour(supervisor).

-export([start_link/1, init/1, get_child_pid/1]).

-include("wm_log.hrl").

-define(DEFAULT_MAXR, 1).
-define(DEFAULT_MAXT, 60).
-define(DEFAULT_EXIT_TIMEOUT, 20).
-define(STRATEGY, one_for_all).

%% ============================================================================
%% API functions
%% ============================================================================

start_link(Services) when is_list(Services) ->
    supervisor:start_link(?MODULE, Services);
start_link({Services, Args}) when is_list(Services), is_list(Args) ->
    supervisor:start_link(?MODULE, {Services, Args}).

init({Services, Args}) ->
    MaxR = wm_conf:g(srv_max_restarts_count, {?DEFAULT_MAXR, integer}),
    MaxT = wm_conf:g(srv_max_restarts_period, {?DEFAULT_MAXT, integer}),
    {ok, {{?STRATEGY, MaxR, MaxT}, addChilds(Services, Args, [])}};
init(Services) ->
    MaxR = wm_conf:g(srv_max_restarts_count, {?DEFAULT_MAXR, integer}),
    MaxT = wm_conf:g(srv_max_restarts_period, {?DEFAULT_MAXT, integer}),
    {ok, {{?STRATEGY, MaxR, MaxT}, addChilds(Services, [])}}.

get_child_pid(SupRef) ->
    do_get_children_pid(SupRef).

%% ============================================================================
%% Implementation functions
%% ============================================================================

addChilds([], Result) ->
    Result;
addChilds([Module | T], Result) ->
    ET = wm_conf:g(srv_exit_timeout, {?DEFAULT_EXIT_TIMEOUT, integer}),
    StartFun = {Module, start_link, [[]]},
    ChildSpec = {Module, StartFun, permanent, ET, worker, [Module]},
    addChilds(T, [ChildSpec | Result]).

addChilds([], _, Result) ->
    Result;
addChilds([Module | T], Args, Result) ->
    StartFun = {Module, start_link, [Args]},
    ET = wm_conf:g(srv_exit_timeout, {?DEFAULT_EXIT_TIMEOUT, integer}),
    ChildSpec = {Module, StartFun, permanent, ET, worker, [Module]},
    addChilds(T, Args, [ChildSpec | Result]).

do_get_children_pid(SupRef) ->
    % assume wm_sup serves one and only one child
    [{_, Pid, _, _}] = supervisor:which_children(SupRef),
    Pid.
