-module(wm_porter_protocol).

%% Shared Porter stdin framing and job enrichment for Porter.

-export([prepare_run_input/2, prepare_ctrl_reply/2, enrich_job_for_porter/1, metrics_env/1]).

-include("../../include/wm_porter.hrl").
-include("wm_entity.hrl").
-include("wm_log.hrl").

-spec prepare_run_input(#job{}, #user{}) -> binary().
prepare_run_input(Job, User) ->
    JobForPorter = enrich_job_for_porter(Job),
    UserBin = erlang:term_to_binary(User),
    UserBinSize = byte_size(UserBin),
    JobBin = erlang:term_to_binary(JobForPorter),
    JobBinSize = byte_size(JobBin),
    <<?PORTER_COMMAND_RUN/integer,
      ?PORTER_DATA_TYPES_COUNT/integer,
      ?PORTER_DATA_TYPE_USERS/integer,
      UserBinSize:4/big-integer-unit:8,
      UserBin/binary,
      ?PORTER_DATA_TYPE_JOBS/integer,
      JobBinSize:4/big-integer-unit:8,
      JobBin/binary>>.

%% @doc Encode a control reply for Porter parent stdin (after RUN).
-spec prepare_ctrl_reply(binary(), term()) -> binary().
prepare_ctrl_reply(Ref, Msg) when is_binary(Ref) ->
    Term = {porter_rep, Ref, Msg},
    Bin = erlang:term_to_binary(Term),
    Size = byte_size(Bin),
    <<?PORTER_COMMAND_CTRL_REPLY/integer, Size:4/big-integer-unit:8, Bin/binary>>.

-spec enrich_job_for_porter(#job{}) -> #job{}.
enrich_job_for_porter(Job) ->
    NodeNames = node_ids_to_names(wm_entity:get(nodes, Job)),
    AccountName = account_id_to_name(wm_entity:get(account_id, Job)),
    PmixEnv = collect_pmix_env(Job),
    MetricsEnv = metrics_env(Job),
    Job1 = wm_entity:set([{nodes, NodeNames}, {account_id, AccountName}], Job),
    case MetricsEnv ++ PmixEnv of
        [] ->
            Job1;
        Extra ->
            Env0 = wm_entity:get(env, Job1),
            wm_entity:set({env, Env0 ++ Extra}, Job1)
    end.

%% @doc Sample/report intervals and GPU flag for Porter (see HOWTO/ACCOUNTING.md).
-spec metrics_env(#job{}) -> [{string(), string()}].
metrics_env(Job) ->
    Sample = integer_to_list(wm_conf:g(job_metrics_interval, {15000, integer})),
    Report = integer_to_list(wm_conf:g(job_metrics_report_interval, {120000, integer})),
    Gpu = case job_requests_gpus(Job) of
              true ->
                  "1";
              false ->
                  "0"
          end,
    [{"SWM_METRICS_INTERVAL_MS", Sample}, {"SWM_METRICS_REPORT_MS", Report}, {"SWM_METRICS_GPU", Gpu}].

-spec job_requests_gpus(#job{}) -> boolean().
job_requests_gpus(Job) ->
    job_gpus_count(wm_entity:get(request, Job)) > 0.

-spec job_gpus_count([#resource{}]) -> non_neg_integer().
job_gpus_count([]) ->
    0;
job_gpus_count([#resource{name = "gpus", count = Count} | _]) when is_integer(Count), Count > 0 ->
    Count;
job_gpus_count([_ | T]) ->
    job_gpus_count(T).

-spec collect_pmix_env(#job{}) -> [{string(), string()}].
collect_pmix_env(Job) ->
    Env = wm_entity:get(env, Job),
    [Pair || {K, _} = Pair <- Env, is_pmix_or_swm_pmix_key(K)].

-spec is_pmix_or_swm_pmix_key(string()) -> boolean().
is_pmix_or_swm_pmix_key("PMIX_" ++ _) ->
    true;
is_pmix_or_swm_pmix_key("SWM_PMIX_" ++ _) ->
    true;
is_pmix_or_swm_pmix_key(_) ->
    false.

-spec node_ids_to_names([node_id()]) -> [string()].
node_ids_to_names(NodeIds) ->
    OrderedIds = wm_utils:order_node_ids_main_first(NodeIds),
    lists:map(fun(NodeId) ->
                 case wm_conf:select(node, {id, NodeId}) of
                     {ok, Node} ->
                         wm_entity:get(name, Node);
                     _ ->
                         NodeId
                 end
              end,
              OrderedIds).

-spec account_id_to_name(account_id() | []) -> string().
account_id_to_name([]) ->
    "";
account_id_to_name(AccountId) ->
    case wm_conf:select(account, {id, AccountId}) of
        {ok, Account} ->
            case wm_entity:get(name, Account) of
                Name when is_atom(Name) ->
                    atom_to_list(Name);
                Name when is_list(Name) ->
                    Name;
                _ ->
                    ""
            end;
        _ ->
            ""
    end.
