%% @doc User facing service HTTP handler.
-module(wm_user_rest).

-export([init/2]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(HTTP_CODE_OK, 200).
-define(HTTP_CODE_BAD_REQUEST, 400).
-define(HTTP_CODE_NOT_FOUND, 404).
-define(HTTP_CODE_INTERNAL_ERROR, 500).
-define(JOB_SUBMISSION_SCRIPT_SIZE_MAX, 16000000).
-define(JOB_SUBMISSION_SCRIPT_WAIT_TIME, 15000).
-define(JOB_ID_SIZE, 36).

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
handle_request(<<"GET">>, #{path := <<"/user/remote">>} = Req) ->
    get_remotes_info(Req);
handle_request(<<"GET">>, #{path := <<"/user/job", _/binary>>} = Req) ->
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
    {wm_user_json:get_api_version_json(), ?HTTP_CODE_OK}.

-spec get_remotes_info(map()) -> {[string()], pos_integer()}.
get_remotes_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 100}], Req),
    ?LOG_DEBUG("Handle remote sites info HTTP request (limit=~p)", [Limit]),
    Remotes = gen_server:call(wm_user, {list, [remote], Limit}),
    F = fun(Remote, FullJson) ->
           RemoteJson =
               jsx:encode(#{id => list_to_binary(wm_entity:get_attr(id, Remote)),
                            name => list_to_binary(wm_entity:get_attr(name, Remote)),
                            account_id => list_to_binary(wm_entity:get_attr(account_id, Remote)),
                            server => list_to_binary(wm_entity:get_attr(server, Remote)),
                            port => wm_entity:get_attr(port, Remote),
                            kind => wm_entity:get_attr(kind, Remote),
                            default_image_id => list_to_binary(wm_entity:get_attr(default_image_id, Remote)),
                            default_flavor_id => list_to_binary(wm_entity:get_attr(default_flavor_id, Remote))}),
           [binary_to_list(RemoteJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Remotes),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

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
                            resources =>
                                wm_user_json:get_resources_json(
                                    wm_entity:get_attr(resources, Node)),
                            roles => wm_user_json:get_roles_json(Node)}),
           [binary_to_list(NodeJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

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
                                    cpus => wm_user_json:find_resource_count("cpus", Resources),
                                    mem => wm_user_json:find_resource_count("mem", Resources),
                                    storage => wm_user_json:find_resource_count("storage", Resources),
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
get_jobs_info(Req) ->
    ?LOG_DEBUG("Handle job info HTTP request"),
    case Req of
        #{path := <<"/user/job/", JobId:?JOB_ID_SIZE/binary, "/stdout">>} ->
            get_job_stdout(JobId);
        #{path := <<"/user/job/", JobId:?JOB_ID_SIZE/binary, "/stderr">>} ->
            get_job_stderr(JobId);
        #{path := <<"/user/job">>} ->
            get_job_list()
    end.

-spec get_job_stdout(job_id()) -> {[string()], pos_integer()}.
get_job_stdout(JobId) ->
    case gen_server:call(wm_user, {stdout, JobId}) of
        {ok, Data} ->
            {Data, ?HTTP_CODE_OK};
        _ ->
            ?LOG_ERROR("Job stdout not found for job ~p", [JobId]),
            {error, ?HTTP_CODE_NOT_FOUND}
    end.

-spec get_job_stderr(job_id()) -> {[string()], pos_integer()}.
get_job_stderr(JobId) ->
    case gen_server:call(wm_user, {stderr, JobId}) of
        {ok, Data} ->
            {Data, ?HTTP_CODE_OK};
        {error, Error} ->
            ?LOG_ERROR("Job stderr not found for job ~p: ~p", [JobId, Error]),
            {error, ?HTTP_CODE_NOT_FOUND}
    end.

-spec get_job_list() -> {[string()], pos_integer()}.
get_job_list() ->
    Xs = gen_server:call(wm_user, {list, [job]}),
    F = fun(Job, FullJson) ->
           JobNodes = wm_conf:select_many(node, id, wm_entity:get_attr(nodes, Job)),
           JobNodeNames = [list_to_binary(wm_entity:get_attr(name, X)) || X <- JobNodes],
           {FlavorId, RemoteId} = wm_user_json:find_flavor_and_remote_ids(Job),
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
                            request =>
                                wm_user_json:get_resources_json(
                                    wm_entity:get_attr(request, Job)),
                            resources =>
                                wm_user_json:get_resources_json(
                                    wm_entity:get_attr(resources, Job)),
                            comment => list_to_binary(wm_entity:get_attr(comment, Job))}),
           [binary_to_list(JobJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec submit_job(map()) -> {string(), pos_integer()} | {error, pos_integer()}.
submit_job(Req) ->
    ?LOG_DEBUG("Handle job submission HTTP request"),
    CertBin = maps:get(cert, Req, undefined),
    case cowboy_req:match_qs([{path, [], undefined}], Req) of
        #{path := undefined} ->
            case cowboy_req:has_body(Req) of
                true ->
                    {ok, Data, _} =
                        cowboy_req:read_body(Req,
                                             #{length => ?JOB_SUBMISSION_SCRIPT_SIZE_MAX,
                                               period => ?JOB_SUBMISSION_SCRIPT_WAIT_TIME}),
                    do_submit_jobscript("", Data, CertBin);
                false ->
                    ?LOG_DEBUG("No job script passed to the job submission HTTP request"),
                    {error, ?HTTP_CODE_BAD_REQUEST}
            end;
        #{path := Path} ->
            do_submit_jobscript_path(binary_to_list(Path), CertBin)
    end.

-spec do_submit_jobscript(string(), binary(), binary()) -> {string(), pos_integer()} | {error, pos_integer()}.
do_submit_jobscript(JobScriptPath, JobScriptContent, CertBin) ->
    case get_username_from_cert(CertBin) of
        {error, Error} ->
            {Error, ?HTTP_CODE_BAD_REQUEST};
        {ok, Username} ->
            Args = {submit, JobScriptContent, JobScriptPath, Username},
            {string, Result} = gen_server:call(wm_user, Args),
            {Result, ?HTTP_CODE_OK}
    end.

-spec do_submit_jobscript_path(string(), binary()) -> {string(), pos_integer()} | {error, pos_integer()}.
do_submit_jobscript_path(Path, CertBin) ->
    case wm_utils:read_file(Path, [binary]) of
        {ok, JobScriptContent} ->
            do_submit_jobscript(filename:absname(Path), JobScriptContent, CertBin);
        {error, noent} ->
            ?LOG_ERROR("No such jobscript local file: ~p", [Path]),
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
