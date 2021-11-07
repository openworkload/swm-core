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
handle_request(<<"GET">>, #{path := <<"/user/flavors">>} = Req) ->
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

-spec get_nodes_info(map()) -> {[string()], pos_integer()}.
get_nodes_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 100}], Req),
    ?LOG_DEBUG("Handle nodes info HTTP request"),
    Xs = gen_server:call(wm_user, {list, [node], Limit}),
    F = fun(Node, FullJson) ->
           SubDiv = wm_entity:get_attr(subdivision, Node),
           SubDivId = wm_entity:get_attr(subdivision_id, Node),
           Parent = wm_entity:get_attr(parent, Node),
           Name = atom_to_list(wm_utils:node_to_fullname(Node)),
           NodeJson =
               "{\"name\":\""
               ++ Name
               ++ "\","
               ++ " \"subname\":\""
               ++ atom_to_list(SubDiv)
               ++ "\","
               ++ " \"subid\":\""
               ++ io_lib:format("~p", [SubDivId])
               ++ "\","
               ++ " \"parent\":\""
               ++ Parent
               ++ "\""
               ++ "}",
           [NodeJson | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["{\"nodes\": ["] ++ string:join(Ms, ", ") ++ ["]}"], ?HTTP_CODE_OK}.

-spec get_resources_json(#node{}) -> [string()].
get_resources_json(Node) ->
    GetResourceJson =
        fun(Resource, Accum) ->
           ["{\"name\":\"" ++ wm_entity:get_attr(name, Resource) ++ "\",",
            "\"count\"" ++ integer_to_list(wm_entity:get_attr(count, Resource)) ++ "\"}"
            | Accum]
        end,
    Resources = wm_entity:get_attr(resources, Node),
    lists:foldl(GetResourceJson, [], Resources).

-spec get_flavors_info(map()) -> {[string()], pos_integer()}.
get_flavors_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 100}], Req),
    ?LOG_DEBUG("Handle flavors info HTTP request (limit=~p)", [Limit]),
    FlavorNodes = gen_server:call(wm_user, {list, [flavor], Limit}),
    F = fun(FlavorNode, FullJson) ->
           FlavorJson =
               "{\"name\":\""
               ++ wm_entity:get_attr(name, FlavorNode)
               ++ "\","
               ++ " \"remote\":\""
               ++ wm_entity:get_attr(remote_id, FlavorNode)
               ++ "\""
               ++ " \"resources\":\""
               ++ get_resources_json(FlavorNode)
               ++ "\""
               ++ "}",
           [FlavorJson | FullJson]
        end,
    Ms = lists:foldl(F, [], FlavorNodes),
    {["{\"flavors\": ["] ++ string:join(Ms, ", ") ++ ["]}"], ?HTTP_CODE_OK}.

-spec get_jobs_info(map()) -> {[string()], pos_integer()}.
get_jobs_info(_Req) ->
    ?LOG_DEBUG("Handle job info HTTP request"),
    Xs = gen_server:call(wm_user, {list, [job]}),
    F = fun(Job, FullJson) ->
           JobJson =
               "{\"ID\":\""
               ++ wm_entity:get_attr(id, Job)
               ++ "\","
               ++ " \"name\":\""
               ++ wm_entity:get_attr(name, Job)
               ++ "\","
               ++ " \"state\":\""
               ++ wm_entity:get_attr(state, Job)
               ++ "\","
               ++ " \"submit_time\":\""
               ++ wm_entity:get_attr(submit_time, Job)
               ++ "\","
               ++ " \"start_time\":\""
               ++ wm_entity:get_attr(start_time, Job)
               ++ "\","
               ++ " \"end_time\":\""
               ++ wm_entity:get_attr(end_time, Job)
               ++ "\","
               ++ " \"comment\":\""
               ++ wm_entity:get_attr(comment, Job)
               ++ "\""
               ++ "}",
           [JobJson | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["[{\"jobs\": ["] ++ string:join(Ms, ", ") ++ ["]}]"], ?HTTP_CODE_OK}.

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
