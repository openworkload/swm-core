-module(wm_docker).

-export([get_unregistered_images/0, get_unregistered_image/1, create/5, start/2, attach/3, attach_ws/3, delete/3,
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
-spec attach(tuple(), pid(), list()) -> pid().
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

%% @doc Delete container for specified job
-spec delete(tuple(), pid(), list()) -> ok.
delete(Job, Owner, Steps) ->
    do_delete_container(Job, Owner, Steps).

%% @doc Create exec in running container
-spec create_exec(tuple(), list()) -> pid().
create_exec(Job, Steps) ->
    do_create_exec(Job, Steps).

%% @doc Start exec in running container
-spec start_exec(tuple(), string(), pid(), list()) -> ok.
start_exec(Job, ExecId, HttpProcPid, Steps) ->
    do_start_exec(Job, ExecId, HttpProcPid, Steps).

%% ============================================================================
%% IMPLEMENTATION
%% ============================================================================

start_http_client(Owner, ReqID) ->
    Host = get_connection_host(),
    Port = wm_conf:g(cont_port, {?CONTAINER_PORT, integer}),
    {ok, Pid} = wm_docker_client:start_link(Host, Port, Owner, ReqID),
    ?LOG_DEBUG("HTTP client Pid=~p", [Pid]),
    Pid.

get_connection_host() ->
    case filelib:is_regular("/.dockerenv") of
        true -> % we are in docker
            "host";
        false ->
            wm_conf:g(cont_host, {?CONTAINER_ADDR, string})
    end.

do_get_unregistered_image(ImageId) ->
    HttpProcPid = start_http_client(self(), ImageId),
    Path = "/images/" ++ ImageId ++ "/json",
    BodyBin = wm_docker_client:get(Path, [], HttpProcPid),
    ?LOG_DEBUG("Get unregistered images: ~p", [BodyBin]),
    wm_docker_client:stop(HttpProcPid),
    ImageStruct = wm_json:decode(BodyBin),
    [Image] = get_images_from_json([ImageStruct], []),
    Image.

do_get_unregistered_images() ->
    HttpProcPid = start_http_client(self(), []),
    Path = "/images/json",
    BodyBin = wm_docker_client:get(Path, [], HttpProcPid),
    wm_docker_client:stop(HttpProcPid),
    ImageStructs = wm_json:decode(BodyBin),
    get_images_from_json(ImageStructs, []).

% Example of parsing image structure that comes from Docker:
%{struct,

  %[{<<"Id">>,
  % <<"sha256:73403b9c37ef3b52ec4895d4fc99f03544d41d4c19d8d05bc5">>},
  %{<<"ParentId">>,
  % <<"sha256:1c391dfeb6a3bd9a71a5a895cf66ec06910b13a1551c4c4367">>},
  %{<<"RepoTags">>,[<<"swm-build:20.1">>]},
  %{<<"RepoDigests">>,null},
  %{<<"Created">>,1476814253},
  %{<<"Size">>,1911787182},
  %{<<"VirtualSize">>,1911787182},
  %{<<"Labels">>,{struct,[]}}]

%}
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

get_cmd(Porter) ->
    [list_to_binary(wm_utils:unroll_symlink(Porter)), <<"-d">>].

-spec get_volumes_from() -> binary().
get_volumes_from() ->
    [list_to_binary(os:getenv("SWM_DOCKER_VOLUMES_FROM", "swm-core:ro"))].

-spec generate_container_json(string()) -> list().
generate_container_json(Porter) ->
    Term1 = jwalk:set({"Tty"}, #{}, false),
    Term2 = jwalk:set({"OpenStdin"}, Term1, true),
    Term3 = jwalk:set({"AttachStdin"}, Term2, true),
    Term4 = jwalk:set({"AttachStdout"}, Term3, true),
    Term5 = jwalk:set({"AttachStderr"}, Term4, true),
    Term6 = jwalk:set({"Image"}, Term5, <<"ubuntu:18.04">>),
    Term7 = jwalk:set({"Cmd"}, Term6, get_cmd(Porter)),
    Term8 = jwalk:set({"Volumes"}, Term7, get_config_map(volumes)),
    Term9 = jwalk:set({"HostConfig"}, Term8, get_config_map(binds)),
    Term10 = jwalk:set({"StdinOnce"}, Term9, false),
    Term11 = jwalk:set({"VolumesFrom"}, Term10, get_volumes_from()),
    jsx:encode(Term11).

do_create_container(Job, Porter, Envs, Owner, Steps) ->
    ContID = "swmjob-" ++ wm_entity:get_attr(id, Job),
    ?LOG_DEBUG("Create container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID),
    Body = generate_container_json(Porter),
    Path = "/containers/create?name=" ++ ContID,
    Hdrs = [{<<"content-type">>, "application/json"}],
    wm_docker_client:post(Path, Body, Hdrs, HttpProcPid, Steps),
    {ContID, HttpProcPid}.

do_stop_container(Job, Owner, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Stop container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID),
    Timeout = "1",
    Path = "/containers/" ++ ContID ++ "/stop?t=" ++ Timeout,
    wm_docker_client:post(Path, [], [], HttpProcPid, Steps),
    wm_docker_client:stop(HttpProcPid).

do_delete_container(Job, Owner, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Delete container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID),
    Path = "/containers/" ++ ContID,
    wm_docker_client:delete(Path, [], HttpProcPid, Steps),
    wm_docker_client:stop(HttpProcPid).

do_start_container(Job, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Start container ~p", [ContID]),
    HttpProcPid = start_http_client(self(), ContID),
    Path = "/containers/" ++ ContID ++ "/start",
    wm_docker_client:post(Path, [], [], HttpProcPid, Steps).

do_attach_container(Job, Owner, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    ?LOG_DEBUG("Attach container ~p", [ContID]),
    HttpProcPid = start_http_client(Owner, ContID),
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
    HttpProcPid = start_http_client(Owner, ContID),
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
            BName = list_to_binary(Username),
            ContID = wm_entity:get_attr(container, Job),
            FinScript = os:getenv("SWM_FINALIZE_IN_CONTAINER", ?SWM_FINALIZE_IN_CONTAINER),
            ?LOG_DEBUG("Finalize ~p: ~p ~p ~p", [ContID, FinScript, BUID, BGID]),
            [list_to_binary(FinScript), BName, BUID, BGID]
    end.

generate_finalize_json(Job, create) ->
    Term1 = jwalk:set({"Tty"}, #{}, false),
    Term2 = jwalk:set({"OpenStdin"}, Term1, false),
    Term3 = jwalk:set({"AttachStdin"}, Term2, false),
    Term4 = jwalk:set({"AttachStdout"}, Term3, false),
    Term5 = jwalk:set({"AttachStderr"}, Term4, false),
    Term6 = jwalk:set({"Cmd"}, Term5, get_finalize_cmd(Job)),
    jsx:encode(Term6);
generate_finalize_json(_, start) ->
    Term1 = jwalk:set({"Detach"}, #{}, false),
    Term2 = jwalk:set({"Tty"}, Term1, false),
    jsx:encode(Term2).

do_create_exec(Job, Steps) ->
    ContID = wm_entity:get_attr(container, Job),
    HttpProcPid = start_http_client(self(), ContID),
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
