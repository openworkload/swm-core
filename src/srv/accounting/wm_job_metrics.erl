-module(wm_job_metrics).

%% Prometheus export for Porter job metrics (Sky Port scrape target).

-export([setup/0, declare/0, observe/3, scrape_reply/0, start_listener/0, stop_listener/0]).

-include("../../lib/wm_log.hrl").

-define(DEFAULT_METRICS_PORT, 9568).
-define(LISTENER, job_metrics_http).
-define(GAUGES,
        [{swm_job_cpu_percent, "Job CPU usage percent (Porter window average)"},
         {swm_job_cpu_percent_max, "Job CPU usage percent (Porter window max)"},
         {swm_job_mem_bytes, "Job memory bytes (Porter window average)"},
         {swm_job_mem_bytes_max, "Job memory bytes (Porter window max)"},
         {swm_job_gpu_util_percent, "Job GPU utilization percent (Porter window average)"},
         {swm_job_gpu_util_percent_max, "Job GPU utilization percent (Porter window max)"},
         {swm_job_gpu_mem_bytes, "Job GPU memory bytes (Porter window average)"},
         {swm_job_gpu_mem_bytes_max, "Job GPU memory bytes (Porter window max)"}]).
-define(FIELD_TO_GAUGE,
        [{cpu_percent, swm_job_cpu_percent},
         {cpu_percent_max, swm_job_cpu_percent_max},
         {mem_bytes, swm_job_mem_bytes},
         {mem_bytes_max, swm_job_mem_bytes_max},
         {gpu_util_percent, swm_job_gpu_util_percent},
         {gpu_util_percent_max, swm_job_gpu_util_percent_max},
         {gpu_mem_bytes, swm_job_gpu_mem_bytes},
         {gpu_mem_bytes_max, swm_job_gpu_mem_bytes_max}]).

%% ============================================================================
%% API
%% ============================================================================

%% @doc Start prometheus (if needed), declare gauges, open cleartext /metrics listener.
-spec setup() -> ok.
setup() ->
    _ = application:ensure_all_started(prometheus),
    declare(),
    _ = start_listener(),
    ok.

-spec declare() -> ok.
declare() ->
    lists:foreach(fun({Name, Help}) -> prometheus_gauge:declare([{name, Name}, {help, Help}, {labels, [job_id, node]}])
                  end,
                  ?GAUGES),
    ok.

-spec observe(term(), term(), map()) -> ok.
observe(JobId, Node, Map) when is_map(Map) ->
    try
        Labels = [label_value(JobId), label_value(Node)],
        lists:foreach(fun({Field, Gauge}) ->
                         case map_get_number(Map, Field) of
                             undefined ->
                                 ok;
                             Value ->
                                 prometheus_gauge:set(Gauge, Labels, Value)
                         end
                      end,
                      ?FIELD_TO_GAUGE)
    catch
        _:_ ->
            ok
    end,
    ok;
observe(_, _, _) ->
    ok.

-spec scrape_reply() -> binary().
scrape_reply() ->
    prometheus_text_format:format().

-spec start_listener() -> ok | {error, term()}.
start_listener() ->
    Port = wm_conf:g(job_metrics_port, {?DEFAULT_METRICS_PORT, integer}),
    case Port of
        0 ->
            log_info("Job metrics Prometheus scrape listener disabled (job_metrics_port=0)", []),
            ok;
        _ when is_integer(Port), Port > 0 ->
            Dispatch = cowboy_router:compile([{'_', [{"/metrics", wm_job_metrics_handler, []}]}]),
            case cowboy:start_clear(?LISTENER, [{port, Port}], #{env => #{dispatch => Dispatch}}) of
                {ok, _} ->
                    log_info("Job metrics Prometheus scrape on cleartext port ~p (/metrics)", [Port]),
                    ok;
                {error, {already_started, _}} ->
                    ok;
                {error, Reason} ->
                    log_error("Failed to start job metrics scrape listener on ~p: ~p", [Port, Reason]),
                    {error, Reason}
            end;
        _ ->
            log_error("Invalid job_metrics_port=~p", [Port]),
            {error, bad_port}
    end.

-spec stop_listener() -> ok.
stop_listener() ->
    _ = cowboy:stop_listener(?LISTENER),
    ok.

%% ============================================================================
%% Internal
%% ============================================================================

-spec label_value(term()) -> binary().
label_value(V) when is_binary(V) ->
    V;
label_value(V) when is_atom(V) ->
    atom_to_binary(V, utf8);
label_value(V) when is_list(V) ->
    unicode:characters_to_binary(V);
label_value(V) ->
    iolist_to_binary(io_lib:format("~p", [V])).

-spec map_get_number(map(), atom()) -> number() | undefined.
map_get_number(Map, Field) ->
    Bin = atom_to_binary(Field, utf8),
    case maps:get(Field, Map, maps:get(Bin, Map, undefined)) of
        V when is_integer(V); is_float(V) ->
            V;
        _ ->
            undefined
    end.

%% wm_log may not be running yet during early boot / ad-hoc validation.
-spec log_info(string(), list()) -> ok.
log_info(Fmt, Args) ->
    try
        ?LOG_INFO(Fmt, Args)
    catch
        _:_ ->
            ok
    end.

-spec log_error(string(), list()) -> ok.
log_error(Fmt, Args) ->
    try
        ?LOG_ERROR(Fmt, Args)
    catch
        _:_ ->
            ok
    end.
