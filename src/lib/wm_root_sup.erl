-module(wm_root_sup).

-behaviour(supervisor).

-export([start_link/1, start_slave/1, init/1, start_child/3, stop_child/1]).
-export([restarter_process/0]).

-include("wm_log.hrl").

% We cannot put these values in db, because wm_db is started later on:
-define(MAXR, 1).
-define(MAXT, 120).
-define(EXIT_TIMEOUT, 30).
-define(STRATEGY, one_for_one).

%% ============================================================================
%% API functions
%% ============================================================================

start_link(Args) ->
    case supervisor:start_link({local, ?MODULE}, ?MODULE, [Args]) of
        {error, {shutdown, {failed_to_start_child, Module, Error}}} ->
            error_logger:error_msg("Failed to start ~p: ~p\n", [Module, Error]),
            exit(self(), kill);
        Result ->
            Result
    end.

start_slave(Args) ->
    application:ensure_all_started(folsom),
    case start_link(Args) of
        {ok, Pid} ->
            unlink(Pid);
        _ ->
            ok
    end.

init(Args) ->
    Pid = spawn(?MODULE, restarter_process, []),
    register(wm_restarter, Pid),
    {ok,
     {{?STRATEGY, ?MAXR, ?MAXT},
      [get_worker_spec(wm_log, Args),
       get_worker_spec(wm_works, Args),
       get_worker_spec(wm_state, Args),
       get_worker_spec(wm_pinger, Args),
       get_worker_spec(wm_db, Args),
       get_worker_spec(wm_event, Args),
       get_worker_spec(wm_conf, Args),
       get_worker_spec(wm_self, Args),
       get_worker_spec(wm_data, Args),
       get_worker_spec(wm_tcpserver, Args),
       get_worker_spec(wm_file_transfer, Args),
       get_worker_spec(wm_session, Args),
       get_worker_spec(wm_api, Args),
       get_worker_spec(wm_factory_mst, Args),
       get_worker_spec(wm_factory_commit, Args),
       get_worker_spec(wm_factory_proc, Args),
       get_worker_spec(wm_factory_virtres, Args),
       get_worker_spec(wm_latency, Args),
       get_worker_spec(wm_topology, Args),
       get_worker_spec(wm_core, Args)]}}.

start_child(Mod, Args, worker) ->
    ChildSpec = get_worker_spec(Mod, Args),
    supervisor:start_child(?MODULE, ChildSpec).

stop_child(Mod) ->
    supervisor:terminate_child(?MODULE, Mod),
    supervisor:delete_child(?MODULE, Mod).

%% ============================================================================
%% Implementation functions
%% ============================================================================

add_arg(Name, Value, Args) ->
    List = [[{Name, Value} | hd(Args)]],
    List.

get_worker_spec(wm_factory_mst, Args) ->
    Args1 = add_arg(regname, wm_factory_mst, Args),
    Args2 = add_arg(module, wm_mst, Args1),
    Args3 = add_arg(activate_passive, true, Args2),
    get_worker_spec({wm_factory_mst, wm_factory}, Args3);
get_worker_spec(wm_factory_commit, Args) ->
    Args1 = add_arg(regname, wm_factory_commit, Args),
    Args2 = add_arg(module, wm_commit, Args1),
    Args3 = add_arg(activate_passive, false, Args2),
    get_worker_spec({wm_factory_commit, wm_factory}, Args3);
get_worker_spec(wm_factory_proc, Args) ->
    Args1 = add_arg(regname, wm_factory_proc, Args),
    Args2 = add_arg(module, wm_proc, Args1),
    Args3 = add_arg(activate_passive, false, Args2),
    get_worker_spec({wm_factory_proc, wm_factory}, Args3);
get_worker_spec(wm_factory_virtres, Args) ->
    Args1 = add_arg(regname, wm_factory_virtres, Args),
    Args2 = add_arg(module, wm_virtres, Args1),
    Args3 = add_arg(activate_passive, false, Args2),
    get_worker_spec({wm_factory_virtres, wm_factory}, Args3);
get_worker_spec({RegName, Mod}, Args) ->
    {RegName, {Mod, start_link, Args}, permanent, ?EXIT_TIMEOUT, worker, [Mod]};
get_worker_spec(Mod, Args) ->
    {Mod, {Mod, start_link, Args}, permanent, ?EXIT_TIMEOUT, worker, [Mod]}.

restarter_process() ->
    receive
        {restart_all, ReqPid} ->
            ?LOG_INFO("All modules will be restarted now (request "
                      "by ~p)",
                      [ReqPid]),
            restart_children(),
            restarter_process()
    end.

restart_children() ->
    Exceptions = [wm_log, wm_conf, wm_db],
    Children = [Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)],
    F2 = fun(Name) ->
            ?LOG_DEBUG("Restart ~p", [Name]),
            supervisor:terminate_child(?MODULE, Name),
            supervisor:restart_child(?MODULE, Name)
         end,
    lists:map(F2,
              lists:reverse(
                  lists:subtract(Children, Exceptions))).
