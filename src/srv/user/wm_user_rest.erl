%% @doc User facing service HTTP handler.
-module(wm_user_rest).

-export([init/2, submit_script_source/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(HTTP_CODE_OK, 200).
-define(HTTP_CODE_BAD_REQUEST, 400).
-define(HTTP_CODE_UNAUTHORIZED, 401).
-define(HTTP_CODE_FORBIDDEN, 403).
-define(HTTP_CODE_NOT_FOUND, 404).
-define(HTTP_CODE_INTERNAL_ERROR, 500).
-define(JSON_ERR_UNAUTHORIZED, <<"{\"error\":\"unauthorized\"}">>).
-define(JSON_ERR_FORBIDDEN, <<"{\"error\":\"forbidden\"}">>).
-define(JSON_ERR_NOT_FOUND, <<"{\"error\":\"job not found\"}">>).
-define(JSON_ERR_PATH_NOT_ALLOWED, <<"{\"error\":\"path query parameter is not allowed\"}">>).
-define(JOB_SUBMISSION_SCRIPT_SIZE_MAX, 16000000).
-define(JOB_SUBMISSION_SCRIPT_WAIT_TIME, 15000).
-define(JOB_ID_SIZE, 36).
-define(SUBMISSION_HEADER, "\r\nContent-Disposition: form-data; name=\"script_content\"\r\n\r\n").
%% Default gen_server:call is 5s; submit/cancel can wait on topology/DB longer.
-define(USER_CALL_TIMEOUT, 60000).

-record(mstate, {}).

%% ============================================================================
%% Callbacks
%% ============================================================================

-spec init(map(), term()) -> {atom(), map(), map()}.
init(Req, _Opts) ->
    {ok, json_handler(Req), #mstate{}}.

%% ============================================================================
%% API handlers
%% ============================================================================

-spec json_handler(map()) -> cowboy_req:req().
json_handler(Req) ->
    ?LOG_ACCESS("JSON handler for method ~p", [cowboy_req:method(Req)]),
    Method = cowboy_req:method(Req),
    {Body, StatusCode} = handle_request(Method, Req),
    cowboy_req:reply(StatusCode, #{<<"content-type">> => <<"application/json; charset=utf-8">>}, Body, Req).

-spec handle_request(binary(), map()) -> {[string()], pos_integer()}.
handle_request(<<"GET">>, #{path := <<"/user">>} = _) ->
    get_api_version();
handle_request(<<"GET">>, #{path := <<"/user/image">>} = Req) ->
    get_images_info(Req);
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
handle_request(<<"DELETE">>, #{path := <<"/user/job", _/binary>>} = Req) ->
    delete_job(Req);
handle_request(<<"PATCH">>, #{path := <<"/user/job", _/binary>>} = Req) ->
    update_job(Req);
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
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 10}], Req),
    ?LOG_ACCESS("Handle remote sites info HTTP request (limit=~p)", [Limit]),
    Remotes = gen_server:call(wm_user, {list, [remote], Limit}),
    F = fun(Remote, FullJson) ->
           RemoteJson =
               wm_json:encode(#{id => list_to_binary(wm_entity:get(id, Remote)),
                                name => list_to_binary(wm_entity:get(name, Remote)),
                                account_id => list_to_binary(wm_entity:get(account_id, Remote)),
                                server => list_to_binary(wm_entity:get(server, Remote)),
                                port => wm_entity:get(port, Remote),
                                kind => wm_entity:get(kind, Remote),
                                default_image_id => list_to_binary(wm_entity:get(default_image_id, Remote)),
                                default_flavor_id => list_to_binary(wm_entity:get(default_flavor_id, Remote))}),
           [binary_to_list(RemoteJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Remotes),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec get_images_info(map()) -> {[string()], pos_integer()}.
get_images_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 1000}], Req),
    ?LOG_ACCESS("Handle images info HTTP request"),
    Xs = gen_server:call(wm_user, {list, [image], Limit}),
    F = fun(Image, FullJson) ->
           ImageJson =
               wm_json:encode(#{id => list_to_binary(wm_entity:get(id, Image)),
                                name => list_to_binary(wm_entity:get(name, Image)),
                                remote_id => list_to_binary(wm_entity:get(remote_id, Image)),
                                kind => atom_to_binary(wm_entity:get(kind, Image)),
                                comment => list_to_binary(wm_entity:get(comment, Image))}),
           [binary_to_list(ImageJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec get_nodes_info(map()) -> {[string()], pos_integer()}.
get_nodes_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 3000}], Req),
    ?LOG_ACCESS("Handle nodes info HTTP request"),
    Xs = gen_server:call(wm_user, {list, [node], Limit}),
    F = fun(Node, FullJson) ->
           NodeJson =
               wm_json:encode(#{id => list_to_binary(wm_entity:get(id, Node)),
                                name => list_to_binary(wm_entity:get(name, Node)),
                                host => list_to_binary(wm_entity:get(host, Node)),
                                api_port => wm_entity:get(api_port, Node),
                                state_power => wm_entity:get(state_power, Node),
                                state_alloc => wm_entity:get(state_alloc, Node),
                                resources =>
                                    wm_user_json:get_resources_json(
                                        wm_entity:get(resources, Node)),
                                roles => wm_user_json:get_roles_json(Node)}),
           [binary_to_list(NodeJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec get_flavors_info(map()) -> {[string()], pos_integer()}.
get_flavors_info(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, int, 1000}], Req),
    ?LOG_ACCESS("Handle flavors info HTTP request (limit=~p)", [Limit]),
    FlavorNodes = gen_server:call(wm_user, {list, [flavor], Limit}),
    F = fun(FlavorNode, FullJson) ->
           RemoteId = wm_entity:get(remote_id, FlavorNode),
           AccountId =
               case wm_conf:select(remote, {id, RemoteId}) of
                   {ok, Remote} ->
                       wm_entity:get(account_id, Remote);
                   {error, not_found} ->
                       ""
               end,
           FlavorJson =
               wm_json:encode(#{id => list_to_binary(wm_entity:get(id, FlavorNode)),
                                name => list_to_binary(wm_entity:get(name, FlavorNode)),
                                remote_id => list_to_binary(RemoteId),
                                resources =>
                                    wm_user_json:get_resources_json(
                                        wm_entity:get(resources, FlavorNode)),
                                price => maps:get(AccountId, wm_entity:get(prices, FlavorNode), 0)}),
           [binary_to_list(FlavorJson) | FullJson]
        end,
    Ms = lists:foldl(F, [], FlavorNodes),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec get_jobs_info(map()) -> {[string()] | binary() | iodata(), pos_integer()}.
get_jobs_info(Req) ->
    ?LOG_ACCESS("Handle job info HTTP request"),
    case require_user_id(Req) of
        {error, Body, Code} ->
            {Body, Code};
        {ok, UserId} ->
            case Req of
                #{path := <<"/user/job/", JobId:(?JOB_ID_SIZE)/binary, "/stdout">>} ->
                    get_job_stdout(binary_to_list(JobId), UserId);
                #{path := <<"/user/job/", JobId:(?JOB_ID_SIZE)/binary, "/stderr">>} ->
                    get_job_stderr(binary_to_list(JobId), UserId);
                #{path := <<"/user/job/", JobId:(?JOB_ID_SIZE)/binary, "/metrics">>} ->
                    get_job_metrics(binary_to_list(JobId), UserId);
                #{path := <<"/user/job/", JobId:(?JOB_ID_SIZE)/binary>>} ->
                    get_one_job(binary_to_list(JobId), UserId);
                #{path := <<"/user/job">>} ->
                    get_job_list(UserId);
                #{path := Path} ->
                    Msg = io_lib:format("Can't parse the path: ~p", [binary_to_list(Path)]),
                    {Msg, ?HTTP_CODE_NOT_FOUND};
                _ ->
                    {"Can't parse the request", ?HTTP_CODE_NOT_FOUND}
            end
    end.

-spec get_one_job(job_id(), user_id()) -> {[string()] | binary(), pos_integer()}.
get_one_job(JobId, UserId) ->
    case gen_server:call(wm_user, {show, [JobId], UserId}) of
        [Job] ->
            {job_to_json(Job, <<>>, true), ?HTTP_CODE_OK};
        {error, forbidden} ->
            {?JSON_ERR_FORBIDDEN, ?HTTP_CODE_FORBIDDEN};
        {error, not_found} ->
            ?LOG_ERROR("Job not found by ID=~p", [JobId]),
            {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND};
        _ ->
            ?LOG_ERROR("Job not found by ID=~p", [JobId]),
            {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND}
    end.

-spec get_job_stdout(job_id(), user_id()) -> {iodata() | binary(), pos_integer()}.
get_job_stdout(JobId, UserId) ->
    case gen_server:call(wm_user, {stdout, JobId, UserId}) of
        {ok, Data} ->
            {Data, ?HTTP_CODE_OK};
        {error, forbidden} ->
            {?JSON_ERR_FORBIDDEN, ?HTTP_CODE_FORBIDDEN};
        {error, not_found} ->
            ?LOG_ERROR("Job stdout not found for job ~p", [JobId]),
            {io_lib:format("Error: stdout for job ~s is not found", [JobId]), ?HTTP_CODE_NOT_FOUND};
        _ ->
            ?LOG_ERROR("Job stdout not found for job ~p", [JobId]),
            {io_lib:format("Error: stdout for job ~s is not found", [JobId]), ?HTTP_CODE_NOT_FOUND}
    end.

-spec get_job_stderr(job_id(), user_id()) -> {iodata() | binary(), pos_integer()}.
get_job_stderr(JobId, UserId) ->
    case gen_server:call(wm_user, {stderr, JobId, UserId}) of
        {ok, Data} ->
            {Data, ?HTTP_CODE_OK};
        {error, forbidden} ->
            {?JSON_ERR_FORBIDDEN, ?HTTP_CODE_FORBIDDEN};
        {error, not_found} ->
            ?LOG_ERROR("Job stderr not found for job ~p", [JobId]),
            {io_lib:format("Error: stderr for job ~s is not found", [JobId]), ?HTTP_CODE_NOT_FOUND};
        {error, Error} ->
            ?LOG_ERROR("Job stderr not found for job ~p: ~p", [JobId, Error]),
            {io_lib:format("Error: stderr for job ~s is not found", [JobId]), ?HTTP_CODE_NOT_FOUND}
    end.

-spec get_job_metrics(job_id(), user_id()) -> {binary() | string(), pos_integer()}.
get_job_metrics(JobId, UserId) ->
    case gen_server:call(wm_user, {show, [JobId], UserId}) of
        [_Job] ->
            case wm_job_metrics:query_job_stats(JobId) of
                {ok, Stats} ->
                    {wm_json:encode(Stats), ?HTTP_CODE_OK};
                {error, not_found} ->
                    ?LOG_ERROR("Job metrics requested for unknown job ~p", [JobId]),
                    {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND}
            end;
        {error, forbidden} ->
            {?JSON_ERR_FORBIDDEN, ?HTTP_CODE_FORBIDDEN};
        {error, not_found} ->
            ?LOG_ERROR("Job metrics requested for unknown job ~p", [JobId]),
            {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND};
        _ ->
            ?LOG_ERROR("Job metrics requested for unknown job ~p", [JobId]),
            {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND}
    end.

-spec job_to_json(#job{}, binary()) -> binary().
job_to_json(Job, FullJson) ->
    job_to_json(Job, FullJson, false).

-spec job_to_json(#job{}, binary(), boolean()) -> binary().
job_to_json(Job, FullJson, IncludeScript) ->
    JobNodes =
        case wm_entity:get(nodes, Job) of
            [] ->
                [];
            NodeIds ->
                %% Preserve job.nodes order: partition manager (main) is first.
                %% select_many/qlc does not keep that order.
                select_nodes_in_order(NodeIds)
        end,
    JobHosts = [wm_entity:get(host, X) || X <- JobNodes],
    JobNodeHostnames = [list_to_binary(X) || X <- JobHosts, is_list(X)],
    JobNodeIps = nodes_to_ips(JobNodes),
    MainIp = main_node_public_ip(JobNodes),
    {FlavorId, RemoteId} = wm_user_json:find_flavor_and_remote_ids(Job),
    Base =
        #{id => list_to_binary(wm_entity:get(id, Job)),
          name => list_to_binary(wm_entity:get(name, Job)),
          state => list_to_binary(wm_entity:get(state, Job)),
          state_details => list_to_binary(wm_entity:get(state_details, Job)),
          submit_time => list_to_binary(wm_entity:get(submit_time, Job)),
          start_time => list_to_binary(wm_entity:get(start_time, Job)),
          end_time => list_to_binary(wm_entity:get(end_time, Job)),
          duration => wm_entity:get(duration, Job),
          exitcode => wm_entity:get(exitcode, Job),
          signal => wm_entity:get(signal, Job),
          node_names => JobNodeHostnames,
          node_ips => JobNodeIps,
          main_ip => MainIp,
          remote_id => list_to_binary(RemoteId),
          flavor_id => list_to_binary(FlavorId),
          request =>
              wm_user_json:get_resources_json(
                  wm_entity:get(request, Job)),
          resources =>
              wm_user_json:get_resources_json(
                  wm_entity:get(resources, Job)),
          comment => list_to_binary(wm_entity:get(comment, Job)),
          checkpoint => list_to_binary(wm_entity:get(checkpoint, Job)),
          checkpoint_dir => list_to_binary(wm_entity:get(checkpoint_dir, Job)),
          checkpoint_interval => wm_entity:get(checkpoint_interval, Job),
          last_checkpoint_time => list_to_binary(wm_entity:get(last_checkpoint_time, Job)),
          checkpoint_display => list_to_binary(wm_checkpoint:display_last(Job))},
    JobMap =
        case IncludeScript of
            true ->
                Base#{script_content => list_to_binary(wm_entity:get(script_content, Job))};
            false ->
                Base
        end,
    JobJson = wm_json:encode(JobMap),
    [binary_to_list(JobJson) | FullJson].

%% @doc Select nodes by id, keeping the caller's order (main / partmgr first).
-spec select_nodes_in_order([node_id()]) -> [#node{}].
select_nodes_in_order(NodeIds) ->
    lists:filtermap(fun(Id) ->
                       case wm_conf:select(node, {id, Id}) of
                           {ok, Node} ->
                               {true, Node};
                           _ ->
                               false
                       end
                    end,
                    NodeIds).

%% @doc Public IP of the job main (partition manager) node.
%% Prefers a node with gateway set (cloud public IP). Do not assume job.nodes[0]
%% is main: the scheduler timetable rewrite reverses node order at start time.
-spec main_node_public_ip([#node{}]) -> binary().
main_node_public_ip([]) ->
    <<>>;
main_node_public_ip(Nodes) ->
    Main =
        case lists:filter(fun(#node{gateway = Gw}) -> Gw =/= [] end, Nodes) of
            [WithGw | _] ->
                WithGw;
            [] ->
                hd(Nodes)
        end,
    case nodes_to_ips([Main]) of
        [Ip | _] ->
            Ip;
        [] ->
            <<>>
    end.

-spec nodes_to_ips([#node{}]) -> [binary()].
nodes_to_ips([]) ->
    [];
nodes_to_ips(Nodes) ->
    {ok, SelfHostname} = inet:gethostname(),
    Hostnames =
        lists:map(fun (#node{gateway = [], host = Hostname}) ->
                          Hostname;
                      (#node{gateway = Gateway}) ->
                          %% Prefer gateway: public address of cloud main node
                          Gateway
                  end,
                  Nodes),
    lists:map(fun ([]) ->
                      <<>>;
                  (Hostname) ->
                      HostnameToResolve =
                          case hd(string:split(Hostname, ".")) of
                              SelfHostname ->
                                  "host";
                              _ ->
                                  Hostname
                          end,
                      case inet:getaddr(HostnameToResolve, inet) of
                          {ok, IP} ->
                              list_to_binary(inet:ntoa(IP));
                          _ ->
                              ?LOG_WARN("Can't resolve job hostname ~p => use localhost", [Hostname]),
                              <<"127.0.0.1">>
                      end
              end,
              Hostnames).

-spec get_job_list(user_id()) -> {[string()], pos_integer()}.
get_job_list(UserId) ->
    Xs = gen_server:call(wm_user, {list_jobs, UserId}),
    Ms = lists:foldl(fun job_to_json/2, [], Xs),
    {["["] ++ string:join(Ms, ", ") ++ ["]"], ?HTTP_CODE_OK}.

-spec delete_job(map()) -> {string() | binary(), pos_integer()}.
delete_job(Req) ->
    ?LOG_ACCESS("Handle job deletion HTTP request with url=~p", [maps:get(path, Req, undefined)]),
    case Req of
        #{path := <<"/user/job">>} ->
            purge_jobs(Req);
        #{path := <<"/user/job/", JobId:(?JOB_ID_SIZE)/binary>>} ->
            case require_user_id(Req) of
                {error, Body, Code} ->
                    {Body, Code};
                {ok, UserId} ->
                    case gen_server:call(wm_user, {cancel, [binary_to_list(JobId)], UserId}, user_call_timeout()) of
                        {string, Msg} ->
                            {Msg, ?HTTP_CODE_OK};
                        {error, forbidden} ->
                            {?JSON_ERR_FORBIDDEN, ?HTTP_CODE_FORBIDDEN};
                        {error, not_found} ->
                            {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND}
                    end
            end;
        _ ->
            {"Can't parse the request", ?HTTP_CODE_NOT_FOUND}
    end.

-spec purge_jobs(map()) -> {string(), pos_integer()}.
purge_jobs(Req) ->
    CertBin = maps:get(cert, Req, undefined),
    case get_username_from_cert(CertBin) of
        {error, Error} ->
            {Error, ?HTTP_CODE_BAD_REQUEST};
        {ok, Username} ->
            %% Purge can touch many jobs; allow longer than the default 5s call.
            {string, Msg} = gen_server:call(wm_user, {purge, Username}, 120000),
            {Msg, ?HTTP_CODE_OK}
    end.

-spec update_job(map()) -> {string() | binary(), pos_integer()}.
update_job(Req) ->
    ?LOG_ACCESS("Handle job updating HTTP request: ~p", [Req]),
    case Req of
        #{path := <<"/user/job/", JobId:(?JOB_ID_SIZE)/binary>>} ->
            case cowboy_req:header(<<"modification">>, Req) of
                <<"requeue">> ->
                    case require_user_id(Req) of
                        {error, Body, Code} ->
                            {Body, Code};
                        {ok, UserId} ->
                            case gen_server:call(wm_user, {requeue, [binary_to_list(JobId)], UserId}) of
                                {string, Msg} ->
                                    {Msg, ?HTTP_CODE_OK};
                                {error, forbidden} ->
                                    {?JSON_ERR_FORBIDDEN, ?HTTP_CODE_FORBIDDEN};
                                {error, not_found} ->
                                    {?JSON_ERR_NOT_FOUND, ?HTTP_CODE_NOT_FOUND}
                            end
                    end;
                undefined ->
                    Msg = io_lib:format("Modification is not specified in the headers: ~p", [cowboy_req:headers(Req)]),
                    {Msg, ?HTTP_CODE_BAD_REQUEST}
            end;
        _ ->
            {"Can't parse the request", ?HTTP_CODE_NOT_FOUND}
    end.

-spec submit_job(map()) -> {iodata() | binary() | string(), pos_integer()} | {error, pos_integer()}.
submit_job(Req) ->
    ?LOG_ACCESS("Handle job submission HTTP request"),
    CertBin = maps:get(cert, Req, undefined),
    {Ip, _} = cowboy_req:peer(Req),
    IpStr = inet:ntoa(Ip),
    #{path := PathQs} = cowboy_req:match_qs([{path, [], undefined}], Req),
    case submit_script_source(PathQs) of
        {error, bad_request} ->
            ?LOG_WARN("Rejecting job submit with path query parameter: ~p", [PathQs]),
            {?JSON_ERR_PATH_NOT_ALLOWED, ?HTTP_CODE_BAD_REQUEST};
        body ->
            case cowboy_req:has_body(Req) of
                true ->
                    {ok, Data, _} =
                        cowboy_req:read_body(Req,
                                             #{length => ?JOB_SUBMISSION_SCRIPT_SIZE_MAX,
                                               period => ?JOB_SUBMISSION_SCRIPT_WAIT_TIME}),
                    do_submit_jobscript("", Data, CertBin, IpStr);
                false ->
                    ?LOG_DEBUG("No job script passed to the job submission HTTP request"),
                    {error, ?HTTP_CODE_BAD_REQUEST}
            end
    end.

%% @doc Job script must come from the request body. The path query parameter
%% used to read arbitrary server files and is rejected.
-spec submit_script_source(undefined | binary()) -> body | {error, bad_request}.
submit_script_source(undefined) ->
    body;
submit_script_source(_Path) ->
    {error, bad_request}.

-spec do_submit_jobscript(string(), binary(), binary(), string()) -> {string(), pos_integer()} | {error, pos_integer()}.
do_submit_jobscript(JobScriptPath, <<"--", Boundary:32/binary, ?SUBMISSION_HEADER, Tail/bitstring>>, CertBin, IpStr) ->
    % Parse multipart request body, see https://swagger.io/docs/specification/describing-request-body/file-upload
    TailStr = binary_to_list(Tail),
    BoundaryStr = binary_to_list(Boundary),
    case string:rstr(TailStr, "\r\n--" ++ BoundaryStr) of
        0 ->
            ?LOG_WARN("Wrong HTTP body format: ~p", [TailStr]),
            {error, ?HTTP_CODE_BAD_REQUEST};
        JobScriptContentEndPosition ->
            NewJobScriptContent = string:substr(TailStr, 1, JobScriptContentEndPosition - 1),
            do_submit_jobscript(JobScriptPath, NewJobScriptContent, CertBin, IpStr)
    end;
do_submit_jobscript(JobScriptPath, JobScriptContent, CertBin, IpStr) ->
    case get_username_from_cert(CertBin) of
        {error, Error} ->
            {Error, ?HTTP_CODE_BAD_REQUEST};
        {ok, Username} ->
            Args = {submit, JobScriptContent, JobScriptPath, Username, IpStr},
            {string, Result} = gen_server:call(wm_user, Args, user_call_timeout()),
            {Result, ?HTTP_CODE_OK}
    end.

-spec user_call_timeout() -> pos_integer().
user_call_timeout() ->
    wm_conf:g(srv_local_call_timeout, {?USER_CALL_TIMEOUT, integer}).

%% @doc Resolve peer cert to #user{}; used by submit/purge (name) and job access (id).
-spec get_user_from_cert(binary() | undefined) -> {ok, #user{}} | {error, string()}.
get_user_from_cert(undefined) ->
    {error, "Client certificate is required"};
get_user_from_cert(CertBin) ->
    Cert = public_key:pkix_decode_cert(CertBin, otp),
    UserID = wm_cert:get_uid(Cert),
    case wm_conf:select(user, {id, UserID}) of
        {error, not_found} ->
            {error, io_lib:format("User with ID=~p is not registred in the workload manager", [UserID])};
        {ok, User} ->
            {ok, User}
    end.

-spec get_username_from_cert(binary() | undefined) -> {ok, string()} | {error, string()}.
get_username_from_cert(CertBin) ->
    case get_user_from_cert(CertBin) of
        {ok, User} ->
            {ok, wm_entity:get(name, User)};
        {error, _} = Error ->
            Error
    end.

%% @doc Require a registered peer-cert user; 401 when missing/unknown (job access paths).
-spec require_user_id(map()) -> {ok, user_id()} | {error, binary(), pos_integer()}.
require_user_id(Req) ->
    case get_user_from_cert(maps:get(cert, Req, undefined)) of
        {ok, User} ->
            {ok, wm_entity:get(id, User)};
        {error, _} ->
            {error, ?JSON_ERR_UNAUTHORIZED, ?HTTP_CODE_UNAUTHORIZED}
    end.

-spec unknown_request_reply() -> {string(), pos_integer()}.
unknown_request_reply() ->
    {"NOT IMPLEMENTED", ?HTTP_CODE_INTERNAL_ERROR}.
