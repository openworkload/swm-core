%%% @doc Native Podman (libpod) job-container backend.
%%% Implements wm_container_runtime using unix-socket REST + crun.
-module(wm_podman).

-behaviour(wm_container_runtime).

-export([run_steps/0, communicate_steps/1, get_unregistered_images/0, get_unregistered_image/1, ensure_create_ready/1,
         create/5, start/2, attach/3, attach_ws/3, delete/2, send/3, create_exec/2, start_exec/4, stop_client/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(GPU_CDI_MISSING_MSG, "GPU job requires NVIDIA CDI on the compute node, but CDI was not available").

%% ============================================================================
%% wm_container_runtime
%% ============================================================================

-spec run_steps() -> [atom() | {atom(), term()}].
run_steps() ->
    %% Attach is deferred to communicate_steps/1 (after start) so Podman does not
    %% close stdin. Finalize exec runs after Porter has been fed (return_sent).
    [create, start, return_started].

-spec communicate_steps(binary()) -> [atom() | {atom(), term()}].
communicate_steps(Bin) when is_binary(Bin) ->
    [attach_ws, {send, Bin}, return_sent, create_exec, start_exec].

-spec get_unregistered_images() -> list().
get_unregistered_images() ->
    Http = start_client(self(), [], "list images"),
    Path = api("/images/json"),
    BodyBin = wm_podman_client:get(Path, [], Http),
    wm_podman_client:stop(Http),
    case catch wm_json:decode(BodyBin) of
        ImageStructs when is_list(ImageStructs) ->
            get_images_from_json(ImageStructs, []);
        _ ->
            []
    end.

-spec get_unregistered_image(string()) -> term().
get_unregistered_image(ImageId) ->
    Http = start_client(self(), ImageId, "get image"),
    Path = api("/images/" ++ ImageId ++ "/json"),
    case wm_podman_client:get_status(Path, [], Http) of
        {404, _} ->
            not_found;
        {error, _} ->
            catch wm_podman_client:stop(Http),
            not_found;
        {_Status, BodyBin} ->
            wm_podman_client:stop(Http),
            case catch wm_json:decode(BodyBin) of
                {struct, _} = Struct ->
                    case get_images_from_json([Struct], []) of
                        [Image] ->
                            Image;
                        _ ->
                            not_found
                    end;
                Map when is_map(Map) ->
                    case get_images_from_json([{struct, maps:to_list(Map)}], []) of
                        [Image] ->
                            Image;
                        _ ->
                            not_found
                    end;
                _ ->
                    not_found
            end
    end.

-spec ensure_create_ready(#job{}) -> ok | {error, string()}.
ensure_create_ready(#job{request = Request} = Job) ->
    JobId = wm_entity:get(id, Job),
    case binary_to_list(get_container_image(Request)) of
        "" ->
            {error, "Container image not specified"};
        Image ->
            case ensure_runtime_ok() of
                {error, _} = E ->
                    E;
                ok ->
                    case ensure_gpu_cdi(Request) of
                        {error, _} = E2 ->
                            E2;
                        ok ->
                            case image_exists(Image) of
                                true ->
                                    ok;
                                false ->
                                    Msg = "Podman image not found: " ++ Image,
                                    ?LOG_ERROR("~s (job ~p)", [Msg, JobId]),
                                    {error, Msg}
                            end
                    end
            end
    end.

-spec create(#job{}, string(), map(), pid(), list()) -> {string(), pid()}.
create(Job, Porter, _Envs, Owner, Steps) ->
    ContID = "swmjob-" ++ wm_entity:get(id, Job),
    ?LOG_DEBUG("Podman create container ~p", [ContID]),
    Http = start_client(Owner, ContID, "create " ++ ContID),
    Body = generate_create_json(Job, Porter, ContID),
    Path = api("/containers/create"),
    Hdrs = [{<<"content-type">>, <<"application/json">>}],
    wm_podman_client:post(Path, Body, Hdrs, Http, Steps),
    {ContID, Http}.

-spec start(#job{}, list()) -> ok.
start(Job, Steps) ->
    ContID = wm_entity:get(container, Job),
    Http = start_client(self(), ContID, "start " ++ ContID),
    Path = api("/containers/" ++ ContID ++ "/start"),
    wm_podman_client:post(Path, <<>>, [], Http, Steps),
    ok.

-spec attach(#job{}, pid(), list()) -> {string(), pid()}.
attach(Job, Owner, Steps) ->
    ContID = wm_entity:get(container, Job),
    Http = start_client(Owner, ContID, "attach " ++ ContID),
    %% stdout/stderr only; Porter stdin is attached later via attach_ws after start.
    %% Container create sets stdin=>true so PID 1 blocks instead of seeing EOF.
    Params = "?logs=true&stream=true&stderr=true&stdout=true&stdin=false",
    Path = api("/containers/" ++ ContID ++ "/attach" ++ Params),
    Hdrs =
        [{<<"Content-Type">>, <<"application/vnd.docker.raw-stream">>},
         {<<"Upgrade">>, <<"tcp">>},
         {<<"Connection">>, <<"Upgrade">>}],
    wm_podman_client:post(Path, <<>>, Hdrs, Http, Steps),
    {ContID, Http}.

%% @doc Attach for Porter stdin (+ stdout/stderr for process status and logs).
-spec attach_ws(#job{}, pid(), list()) -> {string(), pid()}.
attach_ws(Job, Owner, Steps) ->
    ContID = wm_entity:get(container, Job),
    Http = start_client(Owner, ContID, "attach-stdin " ++ ContID),
    Params = "?logs=true&stream=true&stderr=true&stdout=true&stdin=true",
    Path = api("/containers/" ++ ContID ++ "/attach" ++ Params),
    Hdrs =
        [{<<"Content-Type">>, <<"application/vnd.docker.raw-stream">>},
         {<<"Upgrade">>, <<"tcp">>},
         {<<"Connection">>, <<"Upgrade">>}],
    wm_podman_client:attach_stdin(Path, Hdrs, Http, Steps),
    {ContID, Http}.

-spec send(pid(), binary(), list()) -> ok.
send(HttpProcPid, Data, Steps) when is_binary(Data) ->
    wm_podman_client:send(Data, HttpProcPid, Steps).

-spec create_exec(#job{}, list()) -> pid().
create_exec(Job, Steps) ->
    ContID = wm_entity:get(container, Job),
    Http = start_client(self(), ContID, "exec-create " ++ ContID),
    Path = api("/containers/" ++ ContID ++ "/exec"),
    Hdrs = [{<<"content-type">>, <<"application/json">>}],
    Body = generate_exec_create_json(Job),
    wm_podman_client:post(Path, Body, Hdrs, Http, Steps),
    Http.

-spec start_exec(#job{}, string(), pid(), list()) -> ok.
start_exec(_Job, ExecId, HttpProcPid, Steps) ->
    Path = api("/exec/" ++ ExecId ++ "/start"),
    Hdrs = [{<<"content-type">>, <<"application/json">>}],
    Body = jsx:encode(#{<<"Detach">> => false, <<"Tty">> => false}),
    wm_podman_client:post(Path, Body, Hdrs, HttpProcPid, Steps),
    ok.

-spec delete(#job{}, pid()) -> ok.
delete(Job, Owner) ->
    ContID = wm_entity:get(container, Job),
    Http = start_client(Owner, ContID, "delete " ++ ContID),
    Path = api("/containers/" ++ ContID ++ "?force=true&v=true"),
    %% Best-effort delete; do not block cleanup on API errors.
    catch wm_podman_client:delete(Path, [], Http, []),
    catch wm_podman_client:stop(Http),
    ok.

-spec stop_client(pid() | undefined) -> ok.
stop_client(undefined) ->
    ok;
stop_client(Pid) when is_pid(Pid) ->
    try
        wm_podman_client:stop(Pid)
    catch
        _:_ ->
            ok
    end.

%% ============================================================================
%% Internals
%% ============================================================================

api(Path) ->
    wm_container_cfg:podman_api_prefix() ++ Path.

start_client(Owner, ReqID, Reason) ->
    Sock = wm_container_cfg:podman_sock(),
    {ok, Pid} = wm_podman_client:start_link(Sock, Owner, ReqID, Reason),
    Pid.

-spec ensure_runtime_ok() -> ok | {error, string()}.
ensure_runtime_ok() ->
    case wm_container_cfg:require_crun() of
        false ->
            ok;
        true ->
            case query_oci_runtime() of
                {ok, "crun"} ->
                    ok;
                {ok, Other} ->
                    {error,
                     lists:flatten(
                         io_lib:format("Podman OCI runtime is ~s; crun required (SWM_CONTAINER_REQUIRE_CRUN=1)",
                                       [Other]))};
                {error, Reason} ->
                    Sock = wm_container_cfg:podman_sock(),
                    {error,
                     lists:flatten(
                         io_lib:format("Podman API unreachable (~s): ~p (install/enable podman.socket + crun)",
                                       [Sock, Reason]))}
            end
    end.

-spec query_oci_runtime() -> {ok, string()} | {error, term()}.
query_oci_runtime() ->
    Http = start_client(self(), [], "podman info"),
    case wm_podman_client:get_status(api("/info"), [], Http) of
        {error, Reason} ->
            catch wm_podman_client:stop(Http),
            {error, Reason};
        {404, _} ->
            catch wm_podman_client:stop(Http),
            {error, not_found};
        {_St, Body} ->
            catch wm_podman_client:stop(Http),
            case extract_runtime_name(Body) of
                "" ->
                    {error, unknown_runtime};
                Name ->
                    {ok, string:lowercase(Name)}
            end
    end.

extract_runtime_name(Body) when is_binary(Body) ->
    case catch jsx:decode(Body, [return_maps]) of
        #{<<"host">> := #{<<"ociRuntime">> := #{<<"name">> := N}}} when is_binary(N) ->
            binary_to_list(N);
        #{<<"host">> := #{<<"ociRuntime">> := #{<<"Name">> := N}}} when is_binary(N) ->
            binary_to_list(N);
        _ ->
            %% Fallback: substring search
            case binary:match(Body, <<"\"name\":\"crun\"">>) of
                nomatch ->
                    case binary:match(Body, <<"crun">>) of
                        nomatch ->
                            "";
                        _ ->
                            "crun"
                    end;
                _ ->
                    "crun"
            end
    end.

-spec ensure_gpu_cdi([#resource{}]) -> ok | {error, string()}.
ensure_gpu_cdi(Request) ->
    case get_gpus(Request) of
        <<"0">> ->
            ok;
        _ ->
            case wm_container_cfg:cdi_available() of
                true ->
                    ok;
                false ->
                    ?LOG_ERROR("~s", [?GPU_CDI_MISSING_MSG]),
                    {error, ?GPU_CDI_MISSING_MSG}
            end
    end.

image_exists(Image) ->
    Http = start_client(self(), Image, "image exists"),
    Path = api("/images/" ++ Image ++ "/exists"),
    case wm_podman_client:get_status(Path, [], Http) of
        {404, _} ->
            false;
        {error, _} ->
            catch wm_podman_client:stop(Http),
            %% Fallback inspect
            image_inspect_ok(Image);
        {Status, _} when Status >= 200, Status < 300 ->
            catch wm_podman_client:stop(Http),
            true;
        {204, _} ->
            true;
        _ ->
            catch wm_podman_client:stop(Http),
            image_inspect_ok(Image)
    end.

image_inspect_ok(Image) ->
    Http = start_client(self(), Image, "image inspect"),
    Path = api("/images/" ++ Image ++ "/json"),
    case wm_podman_client:get_status(Path, [], Http) of
        {404, _} ->
            false;
        {error, _} ->
            catch wm_podman_client:stop(Http),
            false;
        {Status, Data} when is_binary(Data), Data =/= <<>>, Status >= 200, Status < 300 ->
            catch wm_podman_client:stop(Http),
            true;
        _ ->
            catch wm_podman_client:stop(Http),
            false
    end.

generate_create_json(#job{request = Request} = Job, Porter, ContID) ->
    Image = get_container_image(Request),
    Cmd = [list_to_binary(wm_utils:unroll_symlink(Porter)), <<"-d">>],
    Mounts = default_mounts(),
    Term =
        #{<<"name">> => list_to_binary(ContID),
          <<"image">> => Image,
          <<"command">> => Cmd,
          <<"entrypoint">> => entrypoint_or_empty(),
          %% Keep stdin open until Porter input is written (attach alone is not enough).
          <<"stdin">> => true,
          %% Host net: PMIx / multi-node wireup invariant (HOWTO/CONTAINERS.md).
          <<"netns">> => #{<<"nsmode">> => <<"host">>},
          <<"mounts">> => Mounts,
          <<"work_dir">> => <<"/tmp">>,
          <<"env">> => #{<<"SWM_CONTAINER_RUNTIME">> => <<"podman">>},
          <<"remove">> => true},
    Term2 =
        case get_gpus(Request) of
            <<"0">> ->
                Term;
            _ ->
                Term#{<<"cdi_devices">> => [#{<<"Name">> => <<"nvidia.com/gpu=all">>}]}
        end,
    jsx:encode(Term2).

entrypoint_or_empty() ->
    case wm_container_cfg:entrypoint() of
        undefined ->
            [];
        Parts ->
            Parts
    end.

default_mounts() ->
    Root = wm_utils:get_env("SWM_ROOT"),
    RootBin = list_to_binary(Root),
    Base =
        [#{<<"destination">> => <<"/home">>,
           <<"type">> => <<"bind">>,
           <<"source">> => <<"/home">>,
           <<"options">> => [<<"rbind">>, <<"rw">>]},
         #{<<"destination">> => <<"/tmp">>,
           <<"type">> => <<"bind">>,
           <<"source">> => <<"/tmp">>,
           <<"options">> => [<<"rbind">>, <<"rw">>]},
         #{<<"destination">> => RootBin,
           <<"type">> => <<"bind">>,
           <<"source">> => RootBin,
           <<"options">> => [<<"rbind">>, <<"rw">>]}],
    Base ++ wm_container_cfg:extra_binds().

generate_exec_create_json(Job) ->
    Cmd = get_finalize_cmd(Job),
    jsx:encode(#{<<"Cmd">> => Cmd,
                 <<"AttachStdout">> => true,
                 <<"AttachStderr">> => true,
                 <<"Privileged">> => false,
                 <<"User">> => <<"root">>}).

get_finalize_cmd(#job{workdir = WorkDir} = Job) ->
    case wm_utils:get_job_user(Job) of
        {error, not_found} ->
            [<<"/bin/sh">>, <<"-c">>, <<"echo no-user; exit 1">>];
        {ok, User} ->
            Username = wm_entity:get(name, User),
            FinScript = wm_container_cfg:finalize_script(),
            HostIP =
                case inet:gethostname() of
                    {ok, H} ->
                        H;
                    _ ->
                        "127.0.0.1"
                end,
            {UID, GID} =
                case wm_posix_utils:get_system_uid_gid(Username) of
                    {ok, FoundUID, FoundGID} ->
                        {FoundUID, FoundGID};
                    {error, not_found} ->
                        {"1000", "1000"}
                end,
            Command = FinScript ++ " " ++ Username ++ " " ++ UID ++ " " ++ GID ++ " " ++ HostIP ++ " " ++ WorkDir,
            [<<"/bin/sh">>, <<"-c">>, list_to_binary(Command)]
    end.

get_gpus([]) ->
    <<"0">>;
get_gpus([#resource{name = "gpus", count = Count} | _]) ->
    integer_to_binary(Count);
get_gpus([_ | T]) ->
    get_gpus(T).

get_container_image([]) ->
    <<"">>;
get_container_image([#resource{name = "container-image", properties = Properties} | T]) ->
    case proplists:get_value(value, Properties) of
        Value when is_list(Value) ->
            list_to_binary(Value);
        _ ->
            get_container_image(T)
    end;
get_container_image([_ | T]) ->
    get_container_image(T).

get_images_from_json([], Images) ->
    Images;
get_images_from_json([{struct, ImageParams} | T], Images) ->
    EmptyImage = wm_entity:set([kind, container], wm_entity:new(<<"image">>)),
    case fill_image_from_params(ImageParams, EmptyImage) of
        ignore ->
            get_images_from_json(T, Images);
        NewImage ->
            get_images_from_json(T, [NewImage | Images])
    end;
get_images_from_json([Map | T], Images) when is_map(Map) ->
    get_images_from_json([{struct, maps:to_list(Map)} | T], Images);
get_images_from_json([_ | T], Images) ->
    get_images_from_json(T, Images).

fill_image_from_params([], Image) ->
    Image;
fill_image_from_params([{B, _} | T], Image) when not is_binary(B) ->
    fill_image_from_params(T, Image);
fill_image_from_params([{<<"Id">>, Value} | T], Image) ->
    List1 = binary_to_list(Value),
    List2 = lists:subtract(List1, "sha256:"),
    fill_image_from_params(T, wm_entity:set({id, List2}, Image));
fill_image_from_params([{<<"Size">>, Value} | T], Image) ->
    fill_image_from_params(T, wm_entity:set({size, Value}, Image));
fill_image_from_params([{<<"RepoTags">>, Value} | T], Image) when is_list(Value) ->
    fill_image_tags([binary_to_list(B) || B <- Value], Image, T);
fill_image_from_params([{<<"Names">>, Value} | T], Image) when is_list(Value) ->
    fill_image_tags([binary_to_list(B) || B <- Value], Image, T);
fill_image_from_params([_ | T], Image) ->
    fill_image_from_params(T, Image).

fill_image_tags(Tags, Image, T) ->
    Image2 = wm_entity:set({tags, Tags}, Image),
    case Tags of
        [] ->
            ignore;
        ["<none>:<none>" | _] ->
            ignore;
        [Name | _] ->
            fill_image_from_params(T, wm_entity:set({name, Name}, Image2))
    end.
