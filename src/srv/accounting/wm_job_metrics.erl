-module(wm_job_metrics).

%% Prometheus export (scrape) and PromQL query helpers for Porter job metrics.

-export([setup/0, declare/0, observe/3, scrape_reply/0, start_listener/0, stop_listener/0]).
-export([query_job_stats/1, promql_query/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(DEFAULT_METRICS_PORT, 9568).
-define(DEFAULT_PROMETHEUS_URL, "http://prometheus:9090").
-define(DEFAULT_QUERY_RANGE, "7d").
-define(PROM_AWAIT_MS, 5000).
-define(PROM_BODY_MS, 10000).
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
%% REST metric groups: {JsonKey, AvgGauge, MaxGauge}
-define(STAT_GROUPS,
        [{<<"cpu_percent">>, swm_job_cpu_percent, swm_job_cpu_percent_max},
         {<<"mem_bytes">>, swm_job_mem_bytes, swm_job_mem_bytes_max},
         {<<"gpu_util_percent">>, swm_job_gpu_util_percent, swm_job_gpu_util_percent_max},
         {<<"gpu_mem_bytes">>, swm_job_gpu_mem_bytes, swm_job_gpu_mem_bytes_max}]).

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

%% @doc Look up job and return avg/max metrics map for JSON encoding.
%% Missing Prometheus series become JSON null. Unknown job -> {error, not_found}.
-spec query_job_stats(job_id() | #job{}) -> {ok, map()} | {error, not_found}.
query_job_stats(#job{} = Job) ->
    JobId = wm_entity:get(id, Job),
    Range = range_for_job(Job),
    {ok, build_stats_map(JobId, Range)};
query_job_stats(JobId0) ->
    JobId = ensure_list(JobId0),
    case wm_conf:select(job, {id, JobId}) of
        {ok, Job} ->
            query_job_stats(Job);
        {error, not_found} ->
            {error, not_found};
        _ ->
            {error, not_found}
    end.

%% @doc Instant PromQL query against configured prometheus_url.
%% Returns {ok, Number | null} or {error, Reason}. Exported for tests.
-spec promql_query(string()) -> {ok, number() | null} | {error, term()}.
promql_query(Query) when is_list(Query) ->
    Url = wm_conf:g(prometheus_url, {?DEFAULT_PROMETHEUS_URL, string}),
    case parse_http_url(Url) of
        {ok, Host, Port} ->
            promql_query_http(Host, Port, Query);
        {error, Reason} ->
            {error, Reason}
    end.

%% ============================================================================
%% Internal
%% ============================================================================

-spec build_stats_map(string(), string()) -> map().
build_stats_map(JobId, Range) ->
    Escaped = escape_prom_label(JobId),
    Groups =
        lists:foldl(fun({JsonKey, AvgGauge, MaxGauge}, Acc) ->
                       AvgQ =
                           lists:flatten(
                               io_lib:format("avg(avg_over_time(~s{job_id=\"~s\"}[~s]))", [AvgGauge, Escaped, Range])),
                       MaxQ =
                           lists:flatten(
                               io_lib:format("max(max_over_time(~s{job_id=\"~s\"}[~s]))", [MaxGauge, Escaped, Range])),
                       Acc#{JsonKey =>
                                #{<<"avg">> => query_number_or_null(AvgQ), <<"max">> => query_number_or_null(MaxQ)}}
                    end,
                    #{},
                    ?STAT_GROUPS),
    Groups#{<<"job_id">> => list_to_binary(JobId)}.

-spec query_number_or_null(string()) -> number() | null.
query_number_or_null(Query) ->
    case promql_query(Query) of
        {ok, null} ->
            null;
        {ok, N} when is_number(N) ->
            N;
        {error, Reason} ->
            log_error("Prometheus query failed (~s): ~p", [Query, Reason]),
            null
    end.

-spec promql_query_http(string(), inet:port_number(), string()) -> {ok, number() | null} | {error, term()}.
promql_query_http(Host, Port, Query) ->
    case gun:open(Host, Port, #{protocols => [http], retry => 0}) of
        {ok, ConnPid} ->
            try
                case gun:await_up(ConnPid, ?PROM_AWAIT_MS) of
                    {ok, _} ->
                        Path =
                            "/api/v1/query?"
                            ++ uri_string:compose_query([{<<"query">>, unicode:characters_to_binary(Query)}]),
                        StreamRef = gun:get(ConnPid, Path),
                        case gun:await(ConnPid, StreamRef, ?PROM_BODY_MS) of
                            {response, nofin, 200, _} ->
                                case gun:await_body(ConnPid, StreamRef, ?PROM_BODY_MS) of
                                    {ok, Body} ->
                                        parse_promql_response(Body);
                                    BodyErr ->
                                        {error, BodyErr}
                                end;
                            {response, _, Code, _} ->
                                {error, {http_status, Code}};
                            AwaitErr ->
                                {error, AwaitErr}
                        end;
                    {error, UpErr} ->
                        {error, UpErr}
                end
            after
                gun:close(ConnPid)
            end;
        {error, OpenErr} ->
            {error, OpenErr}
    end.

-spec parse_promql_response(binary()) -> {ok, number() | null} | {error, term()}.
parse_promql_response(Body) ->
    case wm_json:decode(Body) of
        #{<<"status">> := <<"success">>, <<"data">> := #{<<"result">> := []}} ->
            {ok, null};
        #{<<"status">> := <<"success">>, <<"data">> := #{<<"result">> := [#{<<"value">> := [_, Val]} | _]}} ->
            {ok, prom_value_to_number(Val)};
        #{<<"status">> := <<"success">>} ->
            {ok, null};
        #{<<"status">> := <<"error">>, <<"error">> := Err} ->
            {error, Err};
        {error, Reason} ->
            {error, Reason};
        Other ->
            {error, {unexpected_prom_response, Other}}
    end.

-spec prom_value_to_number(binary() | number()) -> number() | null.
prom_value_to_number(N) when is_integer(N); is_float(N) ->
    N;
prom_value_to_number(<<"NaN">>) ->
    null;
prom_value_to_number(<<"+Inf">>) ->
    null;
prom_value_to_number(<<"-Inf">>) ->
    null;
prom_value_to_number(Bin) when is_binary(Bin) ->
    try
        binary_to_float(Bin)
    catch
        _:_ ->
            try
                binary_to_integer(Bin)
            catch
                _:_ ->
                    null
            end
    end;
prom_value_to_number(_) ->
    null.

-spec parse_http_url(string() | binary()) -> {ok, string(), inet:port_number()} | {error, term()}.
parse_http_url(Url0) ->
    Url = ensure_list(Url0),
    case uri_string:parse(Url) of
        #{scheme := Scheme, host := HostBin} = Parts when Scheme =:= <<"http">>; Scheme =:= "http"; Scheme =:= http ->
            Host = ensure_list(HostBin),
            Port =
                case maps:get(port, Parts, undefined) of
                    undefined ->
                        80;
                    P when is_integer(P) ->
                        P
                end,
            {ok, Host, Port};
        #{scheme := Scheme} ->
            {error, {unsupported_scheme, Scheme}};
        Other ->
            {error, {bad_url, Other}}
    end.

-spec range_for_job(#job{}) -> string().
range_for_job(Job) ->
    Start = wm_entity:get(start_time, Job),
    End = wm_entity:get(end_time, Job),
    case {parse_iso_local_secs(Start), parse_iso_local_secs(End)} of
        {{ok, S}, {ok, E}} when is_integer(E), E > S ->
            integer_to_list(max(E - S, 60) + 60) ++ "s";
        {{ok, S}, _} ->
            %% Job times are local wall-clock ISO strings; compare with local now.
            Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
            Now = calendar:datetime_to_gregorian_seconds(
                      calendar:local_time())
                  - Epoch,
            integer_to_list(max(Now - S, 60) + 60) ++ "s";
        _ ->
            case wm_entity:get(duration, Job) of
                D when is_integer(D), D > 0 ->
                    integer_to_list(D + 60) ++ "s";
                _ ->
                    ?DEFAULT_QUERY_RANGE
            end
    end.

-spec parse_iso_local_secs(term()) -> {ok, integer()} | error.
parse_iso_local_secs(Str) when is_list(Str), Str =/= "" ->
    case io_lib:fread("~d-~d-~dT~d:~d:~d", Str) of
        {ok, [Y, Mo, D, H, M, S], _} ->
            Greg = calendar:datetime_to_gregorian_seconds({{Y, Mo, D}, {H, M, S}}),
            Epoch = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
            {ok, Greg - Epoch};
        _ ->
            error
    end;
parse_iso_local_secs(Bin) when is_binary(Bin) ->
    parse_iso_local_secs(binary_to_list(Bin));
parse_iso_local_secs(_) ->
    error.

-spec escape_prom_label(string()) -> string().
escape_prom_label(S) ->
    lists:flatmap(fun ($\\) ->
                          "\\\\";
                      ($") ->
                          "\\\"";
                      (C) ->
                          [C]
                  end,
                  S).

-spec ensure_list(term()) -> string().
ensure_list(V) when is_list(V) ->
    V;
ensure_list(V) when is_binary(V) ->
    binary_to_list(V);
ensure_list(V) when is_atom(V) ->
    atom_to_list(V);
ensure_list(V) ->
    lists:flatten(
        io_lib:format("~p", [V])).

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
%% Under TEST + DISABLE_LOGGING_IN_TESTS, ?LOG_* expands to ok (args unused);
%% format first so the compiler always sees Fmt/Args used.
-spec log_info(string(), list()) -> ok.
log_info(Fmt, Args) ->
    _ = wm_utils:format(Fmt, Args),
    try
        ?LOG_INFO(Fmt, Args)
    catch
        _:_ ->
            ok
    end.

-spec log_error(string(), list()) -> ok.
log_error(Fmt, Args) ->
    _ = wm_utils:format(Fmt, Args),
    try
        ?LOG_ERROR(Fmt, Args)
    catch
        _:_ ->
            ok
    end.
