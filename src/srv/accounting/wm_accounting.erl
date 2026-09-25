-module(wm_accounting).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([job_cost/1, node_prices/1]).
-export([update_node_prices/0]).
-export([norming/1, node_weight/3]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_general.hrl").

-record(mstate, {}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec job_cost(#job{}) -> {ok, {#node{}, number()}} | {error, not_found}.
job_cost(Job) ->
    %TODO allow to estimate job cast via API
    Nodes = wm_relocator:get_suited_template_nodes(Job),
    %FIXME estimate costs per template nodes separatly (if we need this function at all)
    job_cost(Job, Nodes).

-spec node_prices(#node{}) -> #{}.
node_prices(Node) ->
    Resources = wm_entity:get(resources, Node),
    lists:foldl(fun(Resource, Acc) ->
                   Count = wm_entity:get(count, Resource),
                   Prices = wm_entity:get(prices, Resource),
                   maps:fold(fun(AccountId, Price, Acc2) ->
                                Acc2#{AccountId => maps:get(AccountId, Acc2, 0) + Count * Price}
                             end,
                             Acc,
                             Prices)
                end,
                #{},
                Resources).

-spec update_node_prices() -> ok.
update_node_prices() ->
    wm_utils:protected_call(?MODULE, update_node_prices).

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
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    wm_works:call_asap(?MODULE, update_node_prices),
    ?LOG_INFO("Jobs accounting service has been started"),
    {ok, MState}.

handle_call(update_node_prices, _From, MState) ->
    Pred = fun(X) -> wm_entity:get(is_template, X) =:= false end,
    OldNodes =
        case wm_conf:select(node, Pred) of
            {ok, Xs} ->
                Xs;
            {error, not_found} ->
                []
        end,
    Accounts = wm_conf:select(account, all),
    NewNodes = apply_price_map_to_nodes(OldNodes, Accounts),
    true = wm_conf:update(NewNodes) == length(NewNodes),
    {reply, ok, MState};
handle_call(Msg, From, MState) ->
    ?LOG_INFO("Got not handled call message ~p from ~p", [Msg, From]),
    {reply, {error, not_handled}, MState}.

handle_cast(Msg, MState) ->
    ?LOG_INFO("Got not handled cast message ~p", [Msg]),
    {noreply, MState}.

handle_info(Info, MState) ->
    ?LOG_INFO("Got not handled message ~p", [Info]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], MState) ->
    MState;
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec job_cost(#job{}, [#node{}]) -> {ok, {#node{}, number()}} | {error, not_found}.
job_cost(_, []) ->
    {error, not_found};
job_cost(Job, Nodes) ->
    AccountId = wm_entity:get(account_id, Job),
    Duration = wm_entity:get(duration, Job),
    [X | Xs] =
        lists:map(fun(Node) ->
                     Prices = node_prices(Node),
                     Price = maps:get(AccountId, Prices, 0),
                     Hour = 3600,
                     {Node, Price * (Duration / Hour)}
                  end,
                  Nodes),
    Result =
        lists:foldl(fun ({_CurrNode, CurrPrice} = Current, {_Node, Price}) when CurrPrice < Price ->
                            Current;
                        (_Current, Acc) ->
                            Acc
                    end,
                    X,
                    Xs),
    {ok, Result}.

apply_price_map_to_nodes(OldNodes, Accounts) ->
    F = fun(Account, Nodes) ->
           PriceList = wm_entity:get(price_list, Account),
           PriceMap = convert_price_list_to_map(PriceList, maps:new()),
           Apply =
               fun(Node) ->
                  case wm_entity:get(subdivision, Node) of
                      partition ->
                          PartId = wm_entity:get(subdivision_id, Node),
                          Part = wm_conf:select(partition, [PartId]),
                          apply_price_map(Node, Part, Account, PriceMap);
                      _ ->
                          NodeName = wm_entity:get(name, Node),
                          ?LOG_DEBUG("Node ~p is not in a partition!", [NodeName]),
                          Node
                  end
               end,
           [Apply(Node) || Node <- Nodes]
        end,
    lists:foldl(F, OldNodes, Accounts).

scan_price_line(Line) ->
    {ok, Scanned, _} = erl_scan:string(Line),
    case Scanned of
        %% example: "resource=mem price=0.4 when partition=*"
        [{_, _, resource},
         {'=', _},
         {_, _, Res},
         {_, _, price},
         {'=', _},
         {_, _, Price},
         {'when', _},
         {_, _, Cond},
         {'=', _},
         ScannedCondVal] ->
            CondVal =
                case ScannedCondVal of
                    {_, _, X} ->
                        X;
                    {X, 1} ->
                        X
                end,
            {atom_to_list(Res), Price, atom_to_list(Cond), atom_to_list(CondVal)};
        %% example: "resource=mem price=0.4"
        [{_, _, resource}, {'=', _}, {_, _, Res}, {_, _, price}, {'=', _}, {_, _, Price}] ->
            {atom_to_list(Res), Price, "", ""};
        _ ->
            {not_valid, Line}
    end.

convert_price_list_to_map([], Map) ->
    Reverse = fun(_, List) -> lists:reverse(List) end,
    maps:map(Reverse, Map);
convert_price_list_to_map([Line | T], Map) ->
    {Name, Price, CondObj, CondVal} = scan_price_line(Line),
    F = fun(List) -> [{Price, CondObj, CondVal} | List] end,
    Map2 =
        case maps:is_key(Name, Map) of
            true ->
                Map;
            _ ->
                maps:put(Name, [], Map)
        end,
    Map3 = maps:update_with(Name, F, Map2),
    convert_price_list_to_map(T, Map3).

%% @doc Go through each resource price filter and return price from passed ones
filter_node_price(_, _, [], FoundPrice) ->
    FoundPrice;
filter_node_price(Node, Partition, [{NewPrice, [], _} | T], _) ->
    filter_node_price(Node, Partition, T, NewPrice);
filter_node_price(Node, Partition, [{NewPrice, _, "*"} | T], _) ->
    filter_node_price(Node, Partition, T, NewPrice);
filter_node_price(Node, Partition, [{NewPrice, "partition", Name} | T], OldPrice) ->
    case wm_entity:get(name, Partition) of
        Name ->
            filter_node_price(Node, Partition, T, NewPrice);
        _ ->
            filter_node_price(Node, Partition, T, OldPrice)
    end;
filter_node_price(Node, Partition, [{NewPrice, "node", Name} | T], OldPrice) ->
    case wm_entity:get(name, Node) of
        Name ->
            filter_node_price(Node, Partition, T, NewPrice);
        _ ->
            filter_node_price(Node, Partition, T, OldPrice)
    end.

apply_price_map(Node, Partition, Account, PriceMap) ->
    AccId = wm_entity:get(id, Account),
    F = fun(Res) ->
           ResName = wm_entity:get(name, Res),
           PriceList = maps:get(ResName, PriceMap, []),
           ResPrice = filter_node_price(Node, Partition, PriceList, 0),
           OldPriceMap = wm_entity:get(prices, Res),
           NewPriceMap = maps:put(AccId, ResPrice, OldPriceMap),
           wm_entity:set({prices, NewPriceMap}, Res)
        end,
    UpdatedRss = [F(R) || R <- wm_entity:get(resources, Node)],
    wm_entity:set({resources, UpdatedRss}, Node).

-spec norming([number()]) -> [number()].
norming(Xs) ->
    case lists:max(Xs) of
        0 ->
            Xs;
        Max ->
            lists:map(fun(X) -> X / Max end, Xs)
    end.

-spec koef(number()) -> number().
koef(X) ->
    Y = math:log10(X + 1) / 3.0103,
    0.5 - 1 / math:pi() * math:atan(Y - 2).

-spec node_weight(number(), number(), pos_integer()) -> number().
node_weight(Price, NetworkLatency, Data) ->
    K = koef(Data),
    1 / (K * Price + (1 - K) * NetworkLatency).
