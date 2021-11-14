%% @doc User facing service HTTP handler.
-module(wm_user_rest).

-export([init/2]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(API_VERSION, "1").
-define(HTTP_CODE_OK, 200).
-define(HTTP_CODE_BAD_REQUEST, 400).
-define(HTTP_CODE_NOT_FOUND, 404).
-define(HTTP_CODE_INTERNAL_ERROR, 500).

-record(mstate, {}).

%% ============================================================================
%% Callbacks
%% ============================================================================

-spec init(map(), term()) -> {atom(), map(), map()}.
init(Req, _Opts) ->
    ?LOG_INFO("Load user manager HTTP handler"),
    {ok, json_handler(Req), #mstate{}}.

%% ============================================================================
%% API handlers
%% ============================================================================

-spec json_handler(map()) -> cowboy_req:req().
json_handler(Req) ->
    ?LOG_DEBUG("JSON handler for method ~p", [cowboy_req:method(Req)]),
    Method = cowboy_req:method(Req),
    {Body, StatusCode} = handle_request(Method, Req),
    cowboy_req:reply(StatusCode, #{<<"content-type">> => <<"application/json; charset=utf-8">>}, Body, Req).

-spec handle_request(binary(), map()) -> {[string()], pos_integer()}.
handle_request(<<"GET">>, #{path := <<"/user">>} = _) ->
    get_api_version();
handle_request(<<"GET">>, #{path := <<"/user/node">>} = Req) ->
    get_nodes_info(Req);
handle_request(<<"GET">>, #{path := <<"/user/flavor">>} = Req) ->
    get_flavors_info(Req);
handle_request(<<"GET">>, #{path := <<"/user/job">>} = Req) ->
    get_jobs_info(Req);
handle_request(<<"POST">>, #{path := <<"/user/job">>} = Req) ->
    submit_job(Req);
handle_request(<<"DELETE">>, #{path := <<"/user/job">>} = Req) ->
    delete_job(Req);
handle_request(Method, Req) ->
    ?LOG_ERROR("Unknown request: ~p ~p", [Method, Req]),
    unknown_request_reply().

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec get_api_version() -> {[string()], pos_integer()}.
get_api_version() ->
    {["{\"api_version\": "] ++ ?API_VERSION ++ ["}"], ?HTTP_CODE_OK}.

-spec get_resources_json(#node{}) -> list().
get_resources_json(Node) ->
    lists:foldl(fun(Resource, Acc) ->
                   PropertiesMap =
                       #{name => list_to_binary(wm_entity:get_attr(name, Resource)),
                         count => wm_entity:get_attr(count, Resource)},
                   [PropertiesMap | Acc]
                end,
                [],
                wm_entity:get_attr(resources, Node)).

-spec get_roles_json(#node{}) -> list().
get_roles_json(Node) ->
    lists:foldl(fun(RoleId, Acc) ->
                   case wm_conf:select(role, {id, RoleId}) of
                       {ok, Role} ->
                           PropertiesMap =
                               #{id => wm_entity:get_attr(id, Role),
                                 name => list_to_binary(wm_entity:get_attr(name, Role)),
                                 comment => list_to_binary(wm_entity:get_attr(comment, Role))},
                           [PropertiesMap | Acc];
                       _ ->
                           Acc
                   end
                end,
                [],
                wm_entity:get_attr(roles, Node)).

-spec get_nodes_info(map()) -> {[string()], pos_integer()}.
get_nodes_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 100}], Req),
    ?LOG_DEBUG("Handle nodes info HTTP request"),
    Xs = gen_server:call(wm_user, {list, [node], Limit}),
    F = fun(Node, FullJson) ->
           NodeJson =
               jsx:encode(#{id => list_to_binary(wm_entity:get_attr(id, Node)),
                            name => list_to_binary(wm_entity:get_attr(name, Node)),
                            host => list_to_binary(wm_entity:get_attr(host, Node)),
                            api_port => wm_entity:get_attr(api_port, Node),
                            state_power => wm_entity:get_attr(state_power, Node),
                            state_alloc => wm_entity:get_attr(state_alloc, Node),
                            resources => get_resources_json(Node),
                            roles => get_roles_json(Node)}),
           [binary_to_list(NodeJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec find_resource_count(string(), [#resource{}]) -> pos_integer().
find_resource_count(Name, Resources) ->
    case lists:keyfind(Name, 2, Resources) of
        false ->
            0;
        Resource ->
            wm_entity:get_attr(count, Resource)
    end.

-spec find_flavor_and_remote_ids(#job{}) -> {node_id(), remote_id()}.
find_flavor_and_remote_ids(Job) ->
    RrequestedResources = wm_entity:get_attr(request, Job),
    NodeFlavorName =
        case lists:keyfind("flavor", 2, RrequestedResources) of
            false ->
                "";
            Resource ->
                Properties = wm_entity:get_attr(properties, Resource),
                case lists:keyfind(value, 1, Properties) of
                    false ->
                        "";
                    Property ->
                        element(2, Property)
                end
        end,
    case wm_conf:select(node, {name, NodeFlavorName}) of
        {ok, Node} ->
            {wm_entity:get_attr(id, Node), wm_entity:get_attr(remote_id, Node)};
        _ ->
            {"", ""}
    end.

-spec get_flavors_info(map()) -> {[string()], pos_integer()}.
get_flavors_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 100}], Req),
    ?LOG_DEBUG("Handle flavors info HTTP request (limit=~p)", [Limit]),
    FlavorNodes = gen_server:call(wm_user, {list, [flavor], Limit}),
    F = fun(FlavorNode, FullJson) ->
           RemoteId = wm_entity:get_attr(remote_id, FlavorNode),
           case wm_conf:select(remote, {id, RemoteId}) of
               {ok, Remote} ->
                   AccountId = wm_entity:get_attr(account_id, Remote),
                   Resources = wm_entity:get_attr(resources, FlavorNode),
                   FlavorJson =
                       jsx:encode(#{id => list_to_binary(wm_entity:get_attr(id, FlavorNode)),
                                    name => list_to_binary(wm_entity:get_attr(name, FlavorNode)),
                                    remote_id => list_to_binary(RemoteId),
                                    cpus => find_resource_count("cpus", Resources),
                                    mem => find_resource_count("mem", Resources),
                                    storage => find_resource_count("storage", Resources),
                                    price => maps:get(AccountId, wm_entity:get_attr(prices, FlavorNode), 0)}),
                   [binary_to_list(FlavorJson) | FullJson];
               {error, not_found} ->
                   ?LOG_WARN("Remote not found when generate JSON: ~p", [RemoteId]),
                   FullJson
           end
        end,
    Ms = lists:foldl(F, [], FlavorNodes),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec get_jobs_info(map()) -> {[string()], pos_integer()}.
get_jobs_info(_Req) ->
    ?LOG_DEBUG("Handle job info HTTP request"),
    Xs = gen_server:call(wm_user, {list, [job]}),
    F = fun(Job, FullJson) ->
           JobNodes = wm_conf:select_many(node, id, wm_entity:get_attr(nodes, Job)),
           JobNodeNames = [list_to_binary(wm_entity:get_attr(name, X)) || X <- JobNodes],
           {FlavorId, RemoteId} = find_flavor_and_remote_ids(Job),
           JobJson =
               jsx:encode(#{id => list_to_binary(wm_entity:get_attr(id, Job)),
                            name => list_to_binary(wm_entity:get_attr(name, Job)),
                            state => list_to_binary(wm_entity:get_attr(state, Job)),
                            submit_time => list_to_binary(wm_entity:get_attr(submit_time, Job)),
                            start_time => list_to_binary(wm_entity:get_attr(start_time, Job)),
                            end_time => list_to_binary(wm_entity:get_attr(end_time, Job)),
                            duration => wm_entity:get_attr(duration, Job),
                            exitcode => wm_entity:get_attr(exitcode, Job),
                            signal => wm_entity:get_attr(signal, Job),
                            node_names => JobNodeNames,
                            remote_id => list_to_binary(RemoteId),
                            flavor_id => list_to_binary(FlavorId),
                            comment => list_to_binary(wm_entity:get_attr(comment, Job))}),
           [binary_to_list(JobJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec submit_job(map()) -> {string(), pos_integer()} | {error, pos_integer()}.
submit_job(Req) ->
    ?LOG_DEBUG("Handle job submission HTTP request"),
    case cowboy_req:match_qs([{path, [], undefined}], Req) of
        #{path := Path} ->
            CertBin = maps:get(cert, Req, undefined),
            case get_username_from_cert(CertBin) of
                {error, Error} ->
                    {Error, ?HTTP_CODE_BAD_REQUEST};
                {ok, Username} ->
                    do_submit(Username, binary_to_list(Path))
            end
    end.

-spec do_submit(string(), string()) -> {string(), pos_integer()} | {error, pos_integer()}.
do_submit(Username, Path) ->
    case wm_utils:read_file(Path, [binary]) of
        {ok, JobScriptContent} ->
            JobScriptAbsPath = filename:absname(Path),
            Args = {submit, JobScriptContent, JobScriptAbsPath, Username},
            {string, Result} = gen_server:call(wm_user, Args),
            {Result, ?HTTP_CODE_OK};
        {error, noent} ->
            ?LOG_ERROR("No such jobscript file: ~p", [Path]),
            {error, ?HTTP_CODE_NOT_FOUND}
    end.

-spec get_username_from_cert(binary()) -> {ok, string()} | {error, string()}.
get_username_from_cert(CertBin) ->
    Cert = public_key:pkix_decode_cert(CertBin, otp),
    UserID = wm_cert:get_uid(Cert),
    case wm_conf:select(user, {id, UserID}) of
        {error, not_found} ->
            {error, io_lib:format("User with ID=~p is not registred in the workload manager", [UserID])};
        {ok, User} ->
            {ok, wm_entity:get_attr(name, User)}
    end.

-spec delete_job(map()) -> {string(), pos_integer()}.
delete_job(Req) ->
    ?LOG_DEBUG("Handle job deletion HTTP request: ~p", [Req]),
    unknown_request_reply().

-spec unknown_request_reply() -> {string(), pos_integer()}.
unknown_request_reply() ->
    {"NOT IMPLEMENTED", ?HTTP_CODE_INTERNAL_ERROR}.
