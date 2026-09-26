-module(wm_virtres_handler).

-export([get_remote/1, request_partition/2, request_partition_existence/2, is_job_partition_ready/1, update_job/3,
         update_job/2, upload_swm_worker/2, start_job_data_uploading/3, start_job_data_downloading/3,
         delete_partition/4, spawn_partition/2, wait_for_partition_fetch/0, wait_for_wm_resources_readiness/0,
         wait_for_wm_resources_readiness/1, wait_for_ssh_connection/1, wait_for_ssh_connection/2,
         remove_relocation_entities/1, ensure_entities_created/3, try_upload_worker_later/0]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").
-include("../../../include/wm_general.hrl").

%% Defaults used when globals are unset. Prefer shorter polls for SSH/readiness
%% so we notice Azure/cloud-init completion sooner; partition fetch stays a bit
%% longer because ARM create is already a long operation.
-define(DEFAULT_CLOUD_NODE_API_PORT, 10001).
-define(DEFAULT_READINESS_CHECK_PERIOD, 5000).
-define(DEFAULT_SSH_CHECK_PERIOD, 5000).
-define(DEFAULT_PARTITION_FETCH_PERIOD, 10000).
-define(DEFAULT_SWM_DIR_CHECK_PERIOD, 5000).

%% ============================================================================
%% Module API
%% ============================================================================

-spec get_remote(string()) -> {ok, #remote{}}.
get_remote(JobId) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    AccountID = wm_entity:get(account_id, Job),
    ?LOG_INFO("Validate partition (job: ~p, account: ~p)", [JobId, AccountID]),
    wm_conf:select(remote, {account_id, AccountID}).

-spec remove_relocation_entities(job_id()) -> atom().
remove_relocation_entities(JobId) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    ok = wm_relocator:remove_relocation_entities(Job).

-spec try_upload_worker_later() -> reference().
try_upload_worker_later() ->
    wm_utils:wake_up_after(swm_dir_check_period(), try_worker_upload).

-spec wait_for_partition_fetch() -> reference().
wait_for_partition_fetch() ->
    wm_utils:wake_up_after(partition_fetch_period(), part_fetch).

%% @doc Schedule readiness check after the configured period (retries).
-spec wait_for_wm_resources_readiness() -> reference().
wait_for_wm_resources_readiness() ->
    wait_for_wm_resources_readiness(delayed).

%% @doc Schedule readiness check immediately (first attempt) or after period (retry).
-spec wait_for_wm_resources_readiness(immediate | delayed) -> reference().
wait_for_wm_resources_readiness(immediate) ->
    wm_utils:wake_up_after(0, part_check);
wait_for_wm_resources_readiness(delayed) ->
    wm_utils:wake_up_after(readiness_check_period(), part_check).

%% @doc Schedule SSH check after the configured period (retries).
-spec wait_for_ssh_connection(atom()) -> reference().
wait_for_ssh_connection(SshPortType) ->
    wait_for_ssh_connection(SshPortType, delayed).

%% @doc Schedule SSH check immediately (first attempt) or after period (retry).
-spec wait_for_ssh_connection(atom(), immediate | delayed) -> reference().
wait_for_ssh_connection(SshPortType, immediate) ->
    wm_utils:wake_up_after(0, SshPortType);
wait_for_ssh_connection(SshPortType, delayed) ->
    wm_utils:wake_up_after(ssh_check_period(), SshPortType).

-spec partition_fetch_period() -> pos_integer().
partition_fetch_period() ->
    wm_conf:g(virtres_partition_fetch_ms, {?DEFAULT_PARTITION_FETCH_PERIOD, integer}).

-spec readiness_check_period() -> pos_integer().
readiness_check_period() ->
    wm_conf:g(virtres_readiness_check_ms, {?DEFAULT_READINESS_CHECK_PERIOD, integer}).

-spec ssh_check_period() -> pos_integer().
ssh_check_period() ->
    wm_conf:g(virtres_ssh_check_ms, {?DEFAULT_SSH_CHECK_PERIOD, integer}).

-spec swm_dir_check_period() -> pos_integer().
swm_dir_check_period() ->
    wm_conf:g(virtres_swm_dir_check_ms, {?DEFAULT_SWM_DIR_CHECK_PERIOD, integer}).

-spec request_partition(job_id(), #remote{}) -> {atom(), string()}.
request_partition(JobId, Remote) ->
    ?LOG_INFO("Fetch and wait for remote partition (job: ~p)", [JobId]),
    PartName = get_partition_name(JobId),
    wm_gate:get_partition(self(), Remote, PartName).

-spec request_partition_existence(job_id(), #remote{}) -> {atom(), string()}.
request_partition_existence(JobId, Remote) ->
    ?LOG_INFO("Request partition existence (job: ~p)", [JobId]),
    PartName = get_partition_name(JobId),
    wm_gate:partition_exists(self(), Remote, PartName).

-spec is_job_partition_ready(job_id()) -> true | false.
is_job_partition_ready(JobId) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    NodeIds = wm_entity:get(nodes, Job),
    NotReady =
        fun(NodeID) ->
           {ok, Node} = wm_conf:select(node, {id, NodeID}),
           idle =/= wm_entity:get(state_alloc, Node)
        end,
    not lists:any(NotReady, NodeIds).

-spec update_job(list(), job_id()) -> 1.
update_job(Params, JobId) ->
    update_job(Params, JobId, []).

-spec update_job(list(), job_id(), string()) -> 1.
update_job(Params, JobId, []) ->
    {ok, Job1} = wm_conf:select(job, {id, JobId}),
    Job2 = wm_entity:set(Params, Job1),
    ?LOG_DEBUG("Update job ~p with new parameters: ~10000p", [JobId, Params]),
    1 = wm_conf:update(Job2);
update_job(Params, JobId, ErrMsg) ->
    NewParams =
        lists:map(fun ({state_details, Str}) when is_list(Str) ->
                          {state_details, Str ++ ". " ++ ErrMsg};
                      (Other) ->
                          Other
                  end,
                  Params),
    update_job(NewParams, JobId).

-spec upload_swm_worker(node_id(), string()) -> ok | {error, term()}.
upload_swm_worker(RemoteNodeId, SshUserDir) ->
    RemoteFile = "/opt/swm/swm-worker.tar.gz",
    DefaultWorkerPath = "/opt/swm/swm-worker.tar.gz",
    LocalWorkerPath = os:getenv("SWM_WORKER_LOCAL_PATH", DefaultWorkerPath),
    case filelib:is_regular(LocalWorkerPath) of
        false ->
            ?LOG_ERROR("SWM worker package not found: ~p", [LocalWorkerPath]),
            {error, {worker_not_found, LocalWorkerPath}};
        true ->
            {ok, ToNode} = wm_conf:select(node, {id, RemoteNodeId}),
            {ok, MyNode} = wm_self:get_node(),
            {ToAddr, _} = wm_conf:get_relative_address(ToNode, MyNode),
            Port = wm_conf:g(ssh_prov_listen_port, {?DEFAULT_SSH_PROVISION_PORT, integer}),
            wm_file_transfer:upload_file_sftp_sync(ToAddr, Port, LocalWorkerPath, RemoteFile, SshUserDir)
    end.

-spec start_job_data_uploading(node_id(), job_id(), string()) -> {ok, string()}.
start_job_data_uploading(PartMgrNodeID, JobId, SshUserDir) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    Priority = wm_entity:get(priority, Job),
    WorkDir = wm_entity:get(workdir, Job),
    StdInFile = wm_entity:get(job_stdin, Job),
    InputFiles = wm_entity:get(input_files, Job),
    Files = lists:filter(fun(X) -> X =/= [] end, [StdInFile | InputFiles]),
    {ok, ToNode} = wm_conf:select(node, {id, PartMgrNodeID}),
    {ok, MyNode} = wm_self:get_node(),
    {ToAddr, _} = wm_conf:get_relative_address(ToNode, MyNode),
    % TODO upload files to their own dirs, not in workdir, unless the full path is unset
    wm_file_transfer:upload(self(), ToAddr, Priority, Files, WorkDir, #{via => ssh, user_dir => SshUserDir}).

-spec start_job_data_downloading(node_id(), job_id(), string()) -> {ok, reference(), [string()]} | {error, string()}.
start_job_data_downloading(PartMgrNodeID, JobId, SshUserDir) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    Priority = wm_entity:get(priority, Job),
    WorkDir = wm_entity:get(workdir, Job),
    OutputFiles = [WorkDir ++ "/" ++ Filename || Filename <- wm_entity:get(output_files, Job)],
    StdErrFile = wm_entity:get(job_stderr, Job),
    StdOutFile = wm_entity:get(job_stdout, Job),
    StdErrPath = filename:join([WorkDir, StdErrFile]),
    StdOutPath = filename:join([WorkDir, StdOutFile]),
    Files = lists:filter(fun(X) -> X =/= [] end, [StdErrPath, StdOutPath | OutputFiles]),
    case wm_conf:select(node, {id, PartMgrNodeID}) of
        {ok, FromNode} ->
            {ok, MyNode} = wm_self:get_node(),
            {FromAddr, _} = wm_conf:get_relative_address(FromNode, MyNode),
            {ok, Ref} =
                wm_file_transfer:download(self(),
                                          FromAddr,
                                          Priority,
                                          Files,
                                          WorkDir,
                                          #{via => ssh, user_dir => SshUserDir}),
            {ok, Ref, Files};
        {error, Error} ->
            {error, Error}
    end.

-spec delete_partition(partition_id() | undefined, string() | undefined, job_id(), #remote{}) ->
                          {ok, string()} | {error, atom()}.
delete_partition(_PartId, PartExtId, _JobId, Remote) when is_list(PartExtId), PartExtId =/= "" ->
    %% Prefer the gate/Azure id cached by virtres: relocator may already have
    %% deleted the local partition row on cancel.
    wm_gate:delete_partition(self(), Remote, PartExtId);
delete_partition(PartId, _PartExtId, JobId, Remote) when is_list(PartId), PartId =/= "" ->
    case wm_conf:select(partition, {id, PartId}) of
        {ok, Partition} ->
            case wm_entity:get(external_id, Partition) of
                ExtId when is_list(ExtId), ExtId =/= "" ->
                    wm_gate:delete_partition(self(), Remote, ExtId);
                _ ->
                    ?LOG_INFO("Partition ~p has no external_id => delete by name for job ~p", [PartId, JobId]),
                    wm_gate:delete_partition(self(), Remote, get_partition_name(JobId))
            end;
        {error, _} ->
            ?LOG_INFO("Unknown partition id=~p => delete by name for job ~p", [PartId, JobId]),
            wm_gate:delete_partition(self(), Remote, get_partition_name(JobId))
    end;
delete_partition(_PartId, _PartExtId, JobId, Remote) ->
    ?LOG_INFO("No partition id/ext_id => delete by name for job ~p", [JobId]),
    wm_gate:delete_partition(self(), Remote, get_partition_name(JobId)).

-spec spawn_partition(#job{}, #remote{}) -> {ok, string()} | {error, any()}.
spawn_partition(Job, Remote) ->
    JobId = wm_entity:get(id, Job),
    PartName = get_partition_name(JobId),
    {ok, SelfNode} = wm_self:get_node(),
    JobIngresPorts =
        wm_resource_utils:get_ingres_ports_str(
            wm_entity:get(request, Job)),
    ApiPort = integer_to_list(wm_entity:get(api_port, SelfNode)),
    SshPort = wm_conf:g(ssh_daemon_listen_port, {?DEFAULT_SSH_DAEMON_PORT, integer}),
    DataTransferPort = integer_to_list(wm_file_transfer:get_port()),
    SystemPorts = [ApiPort, integer_to_list(SshPort), DataTransferPort],
    Ports =
        string:join(case JobIngresPorts of
                        "" ->
                            SystemPorts;
                        _ ->
                            [JobIngresPorts | SystemPorts]
                    end,
                    ","),
    {ok, ContImage} = wm_utils:find_property_in_resource("container-image", value, wm_entity:get(request, Job)),
    CloudImage = get_resource_value_property(image, "cloud-image", Job, Remote, fun get_default_image_name/1),
    FlavorName = get_resource_value_property(node, "flavor", Job, Remote, fun get_default_flavor_name/1),
    UserId = wm_entity:get(user_id, Job),
    {ok, User} = wm_conf:select(user, {id, UserId}),
    Options =
        #{part_name => PartName,
          image_name => CloudImage,
          container_image => ContImage,
          flavor_name => FlavorName,
          job_id => JobId,
          ports => Ports,
          user_name => wm_entity:get(name, User),
          node_count => wm_utils:get_requested_nodes_number(Job)},
    wm_gate:create_partition(self(), Remote, Options).

-spec ensure_entities_created(job_id(), #partition{}, #node{}) -> {atom(), string()}.
ensure_entities_created(JobId, Partition, TplNode) ->
    remove_relocation_entities(JobId),
    create_relocation_entities(JobId, Partition, TplNode).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec get_resource_value_property(atom(), string(), #job{}, #remote{}, fun((#remote{}) -> string())) -> string().
get_resource_value_property(Tab, Name, Job, Remote, FunGetDefault) ->
    case lists:keyfind(Name, 2, wm_entity:get(request, Job)) of
        false ->
            FunGetDefault(Remote);
        Resource ->
            Properties = wm_entity:get(properties, Resource),
            case proplists:get_value(value, Properties) of
                undefined ->
                    FunGetDefault(Remote);
                EntityName ->
                    case wm_conf:select(Tab, {name, EntityName}) of
                        {ok, _} ->
                            EntityName;
                        {error, not_found} ->
                            JobId = wm_entity:get(id, Job),
                            Default = FunGetDefault(Remote),
                            case Default of
                                "" ->
                                    %% Keep the explicitly requested name so Azure/OpenStack
                                    %% can validate it; do not send an empty osVersion/flavor.
                                    ?LOG_WARN("Entity ~p ~p (job ~p) is unknown and no default is set; using requested name",
                                              [Tab, EntityName, JobId]),
                                    EntityName;
                                _ ->
                                    ?LOG_ERROR("Entity ~p ~p (job ~p) is unknown; using default ~p",
                                               [Tab, EntityName, JobId, Default]),
                                    Default
                            end
                    end
            end
    end.

-spec get_default_image_name(#remote{}) -> string().
get_default_image_name(Remote) ->
    RemoteName = wm_entity:get(name, Remote),
    case wm_entity:get(default_image_id, Remote) of
        DefaultImageId when DefaultImageId =:= undefined; DefaultImageId =:= "" ->
            ?LOG_ERROR("No default image id is set for the remote ~p", [RemoteName]),
            "";
        DefaultImageId ->
            case wm_conf:select(image, {id, DefaultImageId}) of
                {error, not_found} ->
                    ?LOG_ERROR("Default image for remote ~p is not found: ~p", [RemoteName, DefaultImageId]),
                    "";
                {ok, Image} ->
                    wm_entity:get(name, Image)
            end
    end.

-spec get_default_flavor_name(#remote{}) -> string().
get_default_flavor_name(Remote) ->
    RemoteName = wm_entity:get(name, Remote),
    case wm_entity:get(default_flavor_id, Remote) of
        DefaultFlavorId when DefaultFlavorId =:= undefined; DefaultFlavorId =:= "" ->
            ?LOG_ERROR("No default flavor node id is set for the remote ~p", [RemoteName]),
            "";
        DefaultFlavorId ->
            case wm_conf:select(node, {id, DefaultFlavorId}) of
                {error, not_found} ->
                    ?LOG_ERROR("Default flavor for remote ~p is not found: ~p", [RemoteName, DefaultFlavorId]),
                    "";
                {ok, Node} ->
                    wm_entity:get(name, Node)
            end
    end.

-spec create_relocation_entities(job_id(), #partition{}, #node{}) -> {ok, node_id()} | {error, string()}.
create_relocation_entities(JobId, Partition, TplNode) ->
    ?LOG_INFO("Create relocation entities for remote partition [job ~p]: ~10000p", [JobId, Partition]),
    Addresses = wm_entity:get(addresses, Partition),
    NodeIps = maps:get(compute_instances_ips, Addresses, []),
    PubPartMgrIp = maps:get(master_public_ip, Addresses, ""),
    PriPartMgrIp = maps:get(master_private_ip, Addresses, ""),
    PartID = wm_entity:get(id, Partition),
    PartMgrName = wm_utils:get_partition_manager_name(JobId),

    ExtraNodes = clone_extra_nodes(PartID, PartMgrName, NodeIps, JobId, TplNode),
    ExtraNodeIds = [wm_entity:get(id, X) || X <- ExtraNodes],
    PartMgrNode = create_partition_manager_node(PartID, JobId, PubPartMgrIp, PriPartMgrIp, TplNode),
    ok = update_division_entities(JobId, Partition, PartMgrNode, ExtraNodeIds),
    NewNodes = [PartMgrNode | ExtraNodes],
    wm_conf:update(NewNodes),
    ?LOG_INFO("New nodes for job ~p: ~10000p", [JobId, NewNodes]),
    PartMgrNodeId = wm_entity:get(id, PartMgrNode),
    JobRss = get_allocated_resources(PartID, [PartMgrNodeId | ExtraNodeIds]),
    ?LOG_DEBUG("New job resources [job ~p]: ~10000p", [JobId, JobRss]),
    wm_virtres_handler:update_job([{nodes, [PartMgrNodeId | ExtraNodeIds]}, {resources, JobRss}], JobId),
    wm_topology:reload(),
    {ok, PartMgrNodeId}.

-spec update_division_entities(job_id(), #partition{}, #node{}, [string()]) -> ok | {error, not_found}.
update_division_entities(JobId, NewPartition, PartMgrNode, ComputeNodeIds) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    case wm_relocator:get_base_partition(Job) of
        {ok, BasePartition} ->
            PartId = wm_entity:get(id, NewPartition),
            SubPartitionIds = wm_entity:get(partitions, BasePartition),
            BasePartitionUpdated = wm_entity:set({partitions, [PartId | SubPartitionIds]}, BasePartition),
            PartMgrNodeId = wm_entity:get(id, PartMgrNode),
            NameStr = wm_entity:get(name, PartMgrNode),
            HostStr = wm_entity:get(host, PartMgrNode),
            NewPartitionUpdated =
                wm_entity:set([{subdivision, partition},
                               {subdivision_id, wm_entity:get(id, BasePartition)},
                               {manager, NameStr ++ "@" ++ HostStr},
                               {nodes, [PartMgrNodeId | ComputeNodeIds]}],
                              NewPartition),
            1 = wm_conf:update(NewPartitionUpdated),
            1 = wm_conf:update(BasePartitionUpdated),
            ok;
        {error, not_found} ->
            ?LOG_ERROR("Partition for job ~p not found", [JobId]),
            {error, not_found}
    end.

-spec get_partition_name(job_id()) -> string().
get_partition_name(JobId) ->
    "swm-" ++ string:slice(JobId, 0, 8).

-spec get_allocated_resources(partition_id(), [node_id()]) -> [#resource{}].
get_allocated_resources(PartID, NodeIds) ->
    GetNodeRes =
        fun(NodeID) ->
           wm_entity:set([{name, "node"}, {count, 1}, {properties, [{id, NodeID}]}], wm_entity:new(resource))
        end,
    NodeRss = [GetNodeRes(X) || X <- NodeIds],
    PartRes =
        wm_entity:set([{name, "partition"}, {count, 1}, {properties, [{id, PartID}]}, {resources, NodeRss}],
                      wm_entity:new(resource)),
    [PartRes].

-spec get_job_pin_resource(job_id()) -> #resource{}.
get_job_pin_resource(JobId) ->
    wm_entity:set([{name, "job"}, {count, 1}, {properties, [{id, JobId}]}], wm_entity:new(resource)).

-spec create_partition_manager_node(partition_id(), job_id(), string(), string(), #node{}) -> #node{}.
create_partition_manager_node(PartID, JobId, PubPartMgrIp, PriPartMgrIp, TplNode) when TplNode =/= undefined ->
    RemoteID = wm_entity:get(remote_id, TplNode),
    NodeName = wm_utils:get_partition_manager_name(JobId),
    ApiPort = get_cloud_node_api_port(),
    NodeID = wm_utils:uuid(v4),
    Resources = [get_job_pin_resource(JobId) | wm_entity:get(resources, TplNode)],
    wm_entity:set([{id, NodeID},
                   {name, NodeName},
                   {host, PriPartMgrIp},
                   {gateway, PubPartMgrIp},
                   {api_port, ApiPort},
                   {roles, [get_role_id("partition"), get_role_id("compute")]},
                   {remote_id, RemoteID},
                   {resources, Resources},
                   {subdivision, partition},
                   {subdivision_id, PartID},
                   {parent, wm_utils:get_short_name(node())},
                   {comment, "Main cloud node for job " ++ JobId}],
                  wm_entity:new(node)).

-spec clone_extra_nodes(partition_id(), string(), [string()], job_id(), #node{}) -> list().
clone_extra_nodes(_, _, [], _, _) ->
    ?LOG_DEBUG("No extra nodes to clone (no IPs retrieved)"),
    [];
clone_extra_nodes(PartID, ParentName, NodeIps, JobId, TplNode) when TplNode =/= undefined ->
    RemoteID = wm_entity:get(remote_id, TplNode),
    ApiPort = get_cloud_node_api_port(),
    Resources = [get_job_pin_resource(JobId) | wm_entity:get(resources, TplNode)],
    NewNode =
        fun({SeqNum, IP}) ->
           wm_entity:set([{id, wm_utils:uuid(v4)},
                          {name, wm_utils:get_cloud_node_name(JobId, SeqNum)},
                          {host, IP},
                          {api_port, ApiPort},
                          {roles, [get_role_id("compute")]},
                          {subdivision, partition},
                          {subdivision_id, PartID},
                          {remote_id, RemoteID},
                          {resources, Resources},
                          {parent, ParentName},
                          {comment, "Cloud extra compute node for job " ++ JobId}],
                         wm_entity:new(node))
        end,
    ListOfPairs =
        lists:zip(
            lists:seq(1, length(NodeIps)), NodeIps),
    [NewNode(P) || P <- ListOfPairs].

get_cloud_node_api_port() ->
    ?DEFAULT_CLOUD_NODE_API_PORT.

get_role_id(RoleName) ->
    {ok, Role} = wm_conf:select(role, {name, RoleName}),
    wm_entity:get(id, Role).
