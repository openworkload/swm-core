-module(wm_docker).

-export([get_unregistered_images/0, get_unregistered_image/1, create/5, start/2, attach/3, attach_ws/3, delete/2,
         send/3, create_exec/2, start_exec/4]).

-include_lib("kernel/include/file.hrl").

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(CONTAINER_ADDR, "localhost").
-define(CONTAINER_PORT, 6000).
-define(SWM_FINALIZE_IN_CONTAINER, "/opt/swm/current/scripts/swm-docker-finalize.sh").

%% ============================================================================
%% API
%% ============================================================================

%% @doc Get all container images that have not been registered in ther WM yet
-spec get_unregistered_images() -> list().
get_unregistered_images() ->
    do_get_unregistered_images().

%% @doc Get unregistered container image by ID
-spec get_unregistered_image(string()) -> tuple().
get_unregistered_image(ID) ->
    do_get_unregistered_image(ID).

%% @doc Create container for specified job
-spec create(tuple(), string(), map(), pid(), list()) -> {string(), pid()}.
create(Job, Porter, Envs, Owner, Steps) ->
    do_create_container(Job, Porter, Envs, Owner, Steps).

%% @doc Start container for specified job
-spec start(tuple(), list()) -> ok.
start(Job, Steps) ->
    do_start_container(Job, Steps).

%% @doc Attach to container for specified job
-spec attach(tuple(), pid(), list()) -> {string(), pid()}.
attach(Job, Owner, Steps) ->
    do_attach_container(Job, Owner, Steps).

%% @doc Attach to container for specified job using web sockets
-spec attach_ws(tuple(), pid(), list()) -> pid().
attach_ws(Job, Owner, Steps) ->
    do_attach_ws_container(Job, Owner, Steps).

%% @doc Send data into already attached container
-spec send(pid(), binary(), list()) -> pid().
send(HttpProcPid, Data, Steps) ->
    do_send(HttpProcPid, Data, Steps).

%% @doc Create exec in running container
-spec create_exec(tuple(), list()) -> pid().
create_exec(Job, Steps) ->
    do_create_exec(Job, Steps).

%% @doc Start exec in running container
-spec start_exec(tuple(), string(), pid(), list()) -> ok.
start_exec(Job, ExecId, HttpProcPid, Steps) ->
    do_start_exec(Job, ExecId, HttpProcPid, Steps).

%% @doc Delete container for specified job
-spec delete(#job{}, pid()) -> ok.
delete(Job, Owner) ->
    do_delete_container(Job, Owner).

%% ============================================================================
%% IMPLEMENTATION
%% ============================================================================

-spec start_http_client(pid(), term(), string()) -> pid().
start_http_client(Owner, ReqID, Reason) ->
    Host = get_connection_host(),
    Port = wm_conf:g(cont_port, {?CONTAINER_PORT, integer}),
    {ok, Pid} = wm_docker_client:start_link(Host, Port, Owner, ReqID, Reason),
    ?LOG_DEBUG("HTTP client Pid=~p", [Pid]),
    Pid.

-spec get_connection_host() -> string().
get_connection_host() ->
    case filelib:is_regular("/.dockerenv") of
        true -> % we are in docker
            "host";
        false ->
            wm_conf:g(cont_host, {?CONTAINER_ADDR, string})
    end.

do_get_unregistered_image(ImageId) ->
    HttpProcPid = start_http_client(self(), ImageId, "get unregistered image " ++ ImageId),
    Path = "/images/" ++ ImageId ++ "/json",
    BodyBin = wm_docker_client:get(Path, [], HttpProcPid),
    ?LOG_DEBUG("Get unregistered images: ~p", [BodyBin]),
    wm_docker_client:stop(HttpProcPid),
    ImageStruct = wm_json:decode(BodyBin),
    [Image] = get_images_from_json([ImageStruct], []),
    Image.

do_get_unregistered_images() ->
    HttpProcPid = start_http_client(self(), [], "get all unregistered images"),
    Path = "/images/json",
    BodyBin = wm_docker_client:get(Path, [], HttpProcPid),
    wm_docker_client:stop(HttpProcPid),
    ImageStructs = wm_json:decode(BodyBin),
    get_images_from_json(ImageStructs, []).

% Example of parsing image structure that comes from Docker:
% {struct,
%   [{<<"Id">>,
%    <<"sha256:73403b9c37ef3b52ec4895d4fc99f03544d41d4c19d8d05bc5">>},
%   {<<"ParentId">>,
%    <<"sha256:1c391dfeb6a3bd9a71a5a895cf66ec06910b13a1551c4c4367">>},
%   {<<"RepoTags">>,[<<"swm-build:20.1">>]},
%   {<<"RepoDigests">>,null},
%   {<<"Created">>,1476814253},
%   {<<"Size">>,1911787182},
%   {<<"VirtualSize">>,1911787182},
%   {<<"Labels">>,{struct,[]}}]
% }
get_images_from_json([], Images) ->
    Images;
get_images_from_json([{struct, ImageParams} | T], Images) ->
    EmptyImage = wm_entity:set_attr([kind, docker], wm_entity:new(<<"image">>)),
    case fill_image_from_params(ImageParams, EmptyImage) of
        ignore ->
            get_images_from_json(T, Images);
        NewImage ->
            get_images_from_json(T, [NewImage | Images])
    end.

fill_image_from_params([], Image) ->
    Image;
fill_image_from_params([{B, _} | T], Image) when not is_binary(B) ->
    fill_image_from_params(T, Image);
fill_image_from_params([{<<"Id">>, Value} | T], Image) ->
    List1 = binary_to_list(Value),
    List2 = lists:subtract(List1, "sha256:"),
    Image2 = wm_entity:set_attr({id, List2}, Image),
    fill_image_from_params(T, Image2);
fill_image_from_params([{<<"Size">>, Value} | T], Image) ->
    Image2 = wm_entity:set_attr({size, Value}, Image),
    fill_image_from_params(T, Image2);
fill_image_from_params([{<<"RepoTags">>, Value} | T], Image) ->
    Tags = [binary_to_list(B) || B <- Value],
    Image2 = wm_entity:set_attr({tags, Tags}, Image),
    case length(Tags) of
        0 ->
            ignore;
        _ ->
            case hd(Tags) of
                "<none>:<none>" ->
                    ignore;
                Name ->
                    Image3 = wm_entity:set_attr({name, Name}, Image2),
                    fill_image_from_params(T, Image3)
            end
    end;
fill_image_from_params([_ | T], Image) ->
    fill_image_from_params(T, Image).

get_config_map(volumes) ->
    #{<<"/home">> => #{},
      <<"/tmp">> => #{},
      list_to_binary(wm_utils:get_env("SWM_ROOT")) => #{}};
get_config_map(binds) ->
    RootBin = list_to_binary(wm_utils:get_env("SWM_ROOT")),
    #{<<"Binds">> => [<<"/home:/home">>, <<"/tmp:/tmp">>, <<RootBin/binary, <<":">>/binary, RootBin/binary>>]}.

-spec get_cmd(string()) -> [binary()].
get_cmd(Porter) ->
    [list_to_binary(wm_utils:unroll_symlink(Porter)), <<"-d">>].

-spec get_volumes_from() -> binary().
get_volumes_from() ->
    [list_to_binary(os:getenv("SWM_DOCKER_VOLUMES_FROM", "swm-core:ro"))].

-spec generate_container_json(#job{}, string()) -> list().
generate_container_json(#job{request = Request}, Porter) ->
    Term1 = jwalk:set({"Tty"}, #{}, false),
    Term2 = jwalk:set({"OpenStdin"}, Term1, true),
    Term3 = jwalk:set({"AttachStdin"}, Term2, true),
    Term4 = jwalk:set({"AttachStdout"}, Term3, true),
    Term5 = jwalk:set({"AttachStderr"}, Term4, true),
    Term6 = jwalk:set({"Image"}, Term5, get_container_image(Request)),
    Term7 = jwalk:set({"Cmd"}, Term6, get_cmd(Porter)),
    Term8 = jwalk:set({"Volumes"}, Term7, get_config_map(volumes)),
    Term9 = jwalk:set({"HostConfig"}, Term8, get_config_map(binds)),
    Term10 = jwalk:set({"StdinOnce"}, Term9, false),
    Term11 = jwalk:set({"VolumesFrom"}, Term10, get_volumes_from()),
    Term12 = jwalk:set({"ExposedPorts"}, Term11, get_container_ports(Request)),
    jsx:encode(Term12).

-spec get_container_ports([#resource{}]) -> map().
get_container_ports([]) ->
    #{};
get_container_ports([#resource{name = "ports", properties = Properties} | T]) ->
    case proplists:get_value(value, Properties) of
        Value when is_list(Value) ->
            Ports = string:split(Value, ",", all),
            lists:foldl(fun(Port, Map) -> maps:put(list_to_binary(Port), #{}, Map) end, #{}, Ports);
        _ ->
            get_container_ports(T)
    end;
get_container_ports([_ | T]) ->
    get_container_ports(T).

-spec get_container_image([#resource{}]) -> binary().
get_container_image([]) ->
    <<"">>;
get_container_image([#resource{name = "image", properties = Properties} | T]) ->
    case proplists:get_value(value, Properties) of
        Value when is_list(Value) ->
            list_to_binary(Value);
        _ ->
            get_container_image(T)
    end;
get_container_image([_ | T]) ->
    get_container_image(T).

-spec do_create_container(#job{}, string(), map(), pid(), list()) -> {string(), pid()}.
do_create_container(Job, Porter, _Envs, Owner, Steps) ->
    ContID = "swmjob-" ++ wm_entity:get_attr(id, Job),
    ?LOG_DEBUG("Create container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID, "create container " ++ ContID),
    Body = generate_container_json(Job, Porter),
    Path = "/containers/create?name=" ++ ContID,
    Hdrs = [{<<"content-type">>, "application/json"}],
    wm_docker_client:post(Path, Body, Hdrs, HttpProcPid, Steps),
    {ContID, HttpProcPid}.

-spec do_delete_container(#job{}, pid()) -> ok.
do_delete_container(Job, Owner) ->
    ContID = wm_entity:get_attr(container, Job),
    HttpProcPid = start_http_client(Owner, ContID, "delete container " ++ ContID),
    KillBeforeDeleteOption = "?force=1",
    Path = "/containers/" ++ ContID ++ KillBeforeDeleteOption,
    ?LOG_DEBUG("Delete docker container with path=~p [~p]", [Path, HttpProcPid]),
    ok = wm_docker_client:delete(Path, [], HttpProcPid, []),
    wm_docker_client:stop(HttpProcPid),
    ok.

do_start_container(Job, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Start container ~p", [ContID]),
    HttpProcPid = start_http_client(self(), ContID, "start container " ++ ContID),
    Path = "/containers/" ++ ContID ++ "/start",
    wm_docker_client:post(Path, [], [], HttpProcPid, Steps).

do_attach_container(Job, Owner, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Attach to container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID, "attach to container " ++ ContID),
    Params = "?logs=1&stream=1&stderr=1&stdout=1&stdin=0",
    Path = "/containers/" ++ ContID ++ "/attach" ++ Params,
    Hdrs =
        [{<<"Content-Type">>, <<"application/vnd.docker.raw-stream">>},
         {<<"Upgrade">>, <<"tcp">>},
         {<<"Connection">>, <<"Upgrade">>}],
    wm_docker_client:post(Path, [], Hdrs, HttpProcPid, Steps),
    {ContID, HttpProcPid}.

do_attach_ws_container(Job, Owner, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Attach (ws) container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID, "attach to webscket container " ++ ContID),
    % We attach using websockets here only for data sending.
    % Although we still set stream=1 otherwise the attachment
    % connection is closed by docker immidiatly after esteblished.
    Params = "?logs=0&stream=1&stderr=0&stdout=0&stdin=1",
    Path = "/containers/" ++ ContID ++ "/attach/ws" ++ Params,
    Hdrs =
        [{<<"Content-Type">>, <<"application/vnd.docker.raw-stream">>},
         {<<"Upgrade">>, <<"tcp">>},
         {<<"Connection">>, <<"Upgrade">>}],
    wm_docker_client:ws_upgrade(Path, Hdrs, HttpProcPid, Steps),
    {ContID, HttpProcPid}.

do_send(HttpProcPid, Data, Steps) when is_binary(Data) ->
    wm_docker_client:send({binary, Data}, HttpProcPid, Steps).

get_finalize_cmd(Job) ->
    case wm_utils:get_job_user(Job) of
        {error, not_found} ->
            not_found;
        {ok, User} ->
            Username = wm_entity:get_attr(name, User),
            UID = wm_posix_utils:get_system_uid(Username),
            GID = wm_posix_utils:get_system_gid(Username),
            BUID = list_to_binary(UID),
            BGID = list_to_binary(GID),
            ContID = wm_entity:get_attr(container, Job),
            FinScript = os:getenv("SWM_FINALIZE_IN_CONTAINER", ?SWM_FINALIZE_IN_CONTAINER),
            ?LOG_DEBUG("Finalize ~p: ~p ~p ~p", [ContID, FinScript, BUID, BGID]),
            W = FinScript ++ " " ++ Username ++ " " ++ UID ++ " " ++ GID,
            [<<"/bin/bash">>, <<"-c">>, list_to_binary(W)]
    end.

generate_finalize_json(Job, create) ->
    Term1 = jwalk:set({"Tty"}, #{}, false),
    Term2 = jwalk:set({"OpenStdin"}, Term1, false),
    Term3 = jwalk:set({"AttachStdin"}, Term2, false),
    Term4 = jwalk:set({"AttachStdout"}, Term3, false),
    Term5 = jwalk:set({"AttachStderr"}, Term4, false),
    Term6 = jwalk:set({"Cmd"}, Term5, get_finalize_cmd(Job)),
    Term7 = jwalk:set({"User"}, Term6, <<"root">>),
    jsx:encode(Term7);
generate_finalize_json(_, start) ->
    Term1 = jwalk:set({"Detach"}, #{}, false),
    Term2 = jwalk:set({"Tty"}, Term1, false),
    Term3 = jwalk:set({"User"}, Term2, <<"root">>),
    jsx:encode(Term3).

do_create_exec(Job, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    HttpProcPid = start_http_client(self(), ContID, "exec-finalize in container " ++ ContID),
    ?LOG_DEBUG("Finalize container (HttpProcPid=~p)", [HttpProcPid]),
    ContID = wm_entity:get_attr(container, Job),
    Path = "/containers/" ++ ContID ++ "/exec",
    Hdrs = [{<<"content-type">>, "application/json"}],
    Body = generate_finalize_json(Job, create),
    wm_docker_client:post(Path, Body, Hdrs, HttpProcPid, Steps),
    HttpProcPid.

do_start_exec(Job, ExecId, HttpProcPid, Steps) ->
    Path = "/exec/" ++ ExecId ++ "/start",
    Hdrs = [{<<"content-type">>, "application/json"}],
    Body = generate_finalize_json(Job, start),
    wm_docker_client:post(Path, Body, Hdrs, HttpProcPid, Steps).
