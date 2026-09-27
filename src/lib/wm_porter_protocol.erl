-module(wm_porter_protocol).

%% Shared Porter stdin framing and job enrichment for Porter.

-export([prepare_run_input/2, prepare_ctrl_reply/2, enrich_job_for_porter/1]).

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
    Job1 = wm_entity:set([{nodes, NodeNames}, {account_id, AccountName}], Job),
    case PmixEnv of
        [] ->
            Job1;
        _ ->
            Env0 = wm_entity:get(env, Job1),
            wm_entity:set({env, Env0 ++ PmixEnv}, Job1)
    end.

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
