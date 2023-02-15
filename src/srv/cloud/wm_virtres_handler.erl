-module(wm_virtres_handler).

-export([get_remote/1, request_partition/2, request_partition_existence/2, is_job_partition_ready/1, update_job/2,
         start_uploading/2, start_downloading/2, delete_partition/2, spawn_partition/2, wait_for_partition_fetch/0,
         wait_for_wm_resources_readiness/0, wait_for_ssh_connection/0, remove_relocation_entities/1,
         ensure_entities_created/3]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(DEFAULT_CLOUD_NODE_API_PORT, 10001).
-define(REDINESS_CHECK_PERIOD, 10000).
-define(SSH_CHECK_PERIOD, 10000).
-define(PARTITION_FETCH_PERIOD, 10000).

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

-spec wait_for_partition_fetch() -> reference().
wait_for_partition_fetch() ->
    wm_utils:wake_up_after(?PARTITION_FETCH_PERIOD, part_fetch).

-spec wait_for_wm_resources_readiness() -> reference().
wait_for_wm_resources_readiness() ->
    wm_utils:wake_up_after(?REDINESS_CHECK_PERIOD, part_check).

-spec wait_for_ssh_connection() -> reference().
wait_for_ssh_connection() ->
    wm_utils:wake_up_after(?SSH_CHECK_PERIOD, ssh_check).

-spec request_partition(job_id(), #remote{}) -> {atom(), string()}.
request_partition(JobId, Remote) ->
    ?LOG_INFO("Fetch and wait for remote partition (job: ~p)", [JobId]),
    PartName = get_partition_name(JobId),
    {ok, Creds} = get_credentials(Remote),
    wm_gate:get_partition(self(), Remote, Creds, PartName).

-spec request_partition_existence(job_id(), #remote{}) -> {atom(), string()}.
request_partition_existence(JobId, Remote) ->
    ?LOG_INFO("Request partition existence (job: ~p)", [JobId]),
    PartName = get_partition_name(JobId),
    {ok, Creds} = get_credentials(Remote),
    wm_gate:partition_exists(self(), Remote, Creds, PartName).

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
update_job(NewParams, JobId) ->
    {ok, Job1} = wm_conf:select(job, {id, JobId}),
    Job2 = wm_entity:set(NewParams, Job1),
    1 = wm_conf:update(Job2).

-spec start_uploading(node_id(), job_id()) -> {ok, string()}.
start_uploading(PartMgrNodeID, JobId) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    Priority = wm_entity:get(priority, Job),
    WorkDir = wm_entity:get(workdir, Job),
    StdInFile = wm_entity:get(job_stdin, Job),
    InputFiles = wm_entity:get(input_files, Job),
    JobScript = wm_entity:get(script, Job),
    %TODO: transfer also container image
    Files = lists:filter(fun(X) -> X =/= [] end, [JobScript, StdInFile | InputFiles]),
    {ok, ToNode} = wm_conf:select(node, {id, PartMgrNodeID}),
    {ok, MyNode} = wm_self:get_node(),
    {ToAddr, _} = wm_conf:get_relative_address(ToNode, MyNode),
    % TODO copy files to their own dirs, not in workdir, unless the full path is not set
    wm_file_transfer:upload(self(), ToAddr, Priority, Files, WorkDir, #{via => ssh}).

-spec start_downloading(node_id(), job_id()) -> {ok, reference(), [string()]}.
start_downloading(PartMgrNodeID, JobId) ->
    {ok, Job} = wm_conf:select(job, {id, JobId}),
    Priority = wm_entity:get(priority, Job),
    WorkDir = wm_entity:get(workdir, Job),
    OutputFiles = wm_entity:get(output_files, Job),
    StdErrFile = wm_entity:get(job_stderr, Job),
    StdOutFile = wm_entity:get(job_stdout, Job),
    StdErrPath = filename:join([WorkDir, StdErrFile]),
    StdOutPath = filename:join([WorkDir, StdOutFile]),
    Files = lists:filter(fun(X) -> X =/= [] end, [StdErrPath, StdOutPath | OutputFiles]),
    {ok, FromNode} = wm_conf:select(node, {id, PartMgrNodeID}),
    {ok, MyNode} = wm_self:get_node(),
    {FromAddr, _} = wm_conf:get_relative_address(FromNode, MyNode),
    % TODO allow to copy files which paths are defined in a file that will be generated in cloud
    {ok, Ref} = wm_file_transfer:download(self(), FromAddr, Priority, Files, WorkDir, #{via => ssh}),
    {ok, Ref, Files}.

-spec delete_partition(partition_id(), #remote{}) -> {ok, string()} | {error, atom()}.
delete_partition(PartId, Remote) ->
    case wm_conf:select(partition, {id, PartId}) of
        {ok, Partition} ->
            PartName = wm_entity:get(name, Partition),
            {ok, Creds} = get_credentials(Remote),
            wm_gate:delete_partition(self(), Remote, Creds, PartName);
        {error, Error} ->
            {error, Error}
    end.

-spec spawn_partition(#job{}, #remote{}) -> {ok, string()} | {error, any()}.
spawn_partition(Job, Remote) ->
    JobId = wm_entity:get(id, Job),
    PartName = get_partition_name(JobId),
    {ok, Creds} = get_credentials(Remote),
    Options =
        #{name => PartName,
          image_name => get_resource_value_property(image, "image", Job, Remote, fun get_default_image_name/1),
          flavor_name => get_resource_value_property(node, "flavor", Job, Remote, fun get_default_flavor_name/1),
          tenant_name => wm_entity:get(tenant_name, Creds),
          partition_name => PartName,
          node_count => wm_utils:get_requested_nodes_number(Job)},
    ?LOG_DEBUG("Start partition options: ~w", [Options]),
    wm_gate:create_partition(self(), Remote, Creds, Options).

-spec ensure_entities_created(job_id(), #partition{}, #node{}) -> {atom(), string()}.
ensure_entities_created(JobId, Partition, TplNode) ->
    remove_relocation_entities(JobId),
    create_relocation_entities(JobId, Partition, TplNode).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec get_resource_value_property(atom(), string(), #job{}, #remote{}, fun((#remote{}) -> string())) -> string().
get_resource_value_property(Tab, Name, Job, Remote, FunGetDefault) ->
    %case lists:search(fun (#resource{name = X}) when X == Name ->
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
                            throw(io_lib:format("Entity ~p ~p (job ~p) is unknown", [Tab, EntityName, JobId]))
                    end
            end
    end.

-spec get_default_image_name(#remote{}) -> string().
get_default_image_name(Remote) ->
    RemoteName = wm_entity:get(name, Remote),
    case wm_entity:get(default_image_id, Remote) of
        undefined ->
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
        undefined ->
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

-spec create_relocation_entities(job_id(), #partition{}, #node{}) -> {atom(), string()}.
create_relocation_entities(JobId, Partition, TplNode) ->
    ?LOG_INFO("Remote partition [job ~p]: ~p", [JobId, Partition]),
    Addresses = wm_entity:get(addresses, Partition),
    NodeIps = maps:get(compute_instances_ips, Addresses, []),
    PubPartMgrIp = maps:get(master_public_ip, Addresses, ""),
    PriPartMgrIp = maps:get(master_private_ip, Addresses, ""),
    PartID = wm_entity:get(id, Partition),
    PartMgrName = get_partition_manager_name(JobId),

    case ensure_nodes_cloned(PartID, PartMgrName, NodeIps, JobId, TplNode) of
        [] ->
            {error, "Could not clone nodes for job " ++ JobId};
        ComputeNodes ->
            ComputeNodeIds = [wm_entity:get(id, X) || X <- ComputeNodes],
            PartMgrNode = create_partition_manager_node(PartID, JobId, PubPartMgrIp, PriPartMgrIp, TplNode),
            ok = update_division_entities(JobId, Partition, PartMgrNode, ComputeNodeIds),
            NewNodes = [PartMgrNode | ComputeNodes],
            wm_conf:update(NewNodes),
            ?LOG_INFO("Remote nodes [job ~p]: ~p", [JobId, NewNodes]),
            PartMgrNodeId = wm_entity:get(id, PartMgrNode),
            JobRss = get_allocated_resources(PartID, [PartMgrNodeId | ComputeNodeIds]),
            ?LOG_DEBUG("New job resources [job ~p]: ~p", [JobId, JobRss]),
            wm_virtres_handler:update_job([{nodes, ComputeNodeIds}, {resources, JobRss}], JobId),
            wm_topology:reload(),
            {ok, PartMgrNodeId}
    end.

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
            1 = wm_conf:update(BasePartitionUpdated);
        {error, not_found} ->
            ?LOG_ERROR("Partition for job ~p not found", [JobId]),
            {error, not_found}
    end.

-spec get_partition_name(job_id()) -> string().
get_partition_name(JobId) ->
    "swm-" ++ string:slice(JobId, 0, 8).

-spec get_credentials(#remote{}) -> #credential{}.
get_credentials(Remote) ->
    RemoteID = wm_entity:get(id, Remote),
    wm_conf:select(credential, {remote_id, RemoteID}).

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

-spec create_partition_manager_node(partition_id(), job_id(), string(), string(), #node{}) -> #node{}.
create_partition_manager_node(PartID, JobId, PubPartMgrIp, PriPartMgrIp, TplNode) when TplNode =/= undefined ->
    RemoteID = wm_entity:get(remote_id, TplNode),
    NodeName = get_partition_manager_name(JobId),
    ApiPort = get_cloud_node_api_port(),
    NodeID = wm_utils:uuid(v4),
    wm_entity:set([{id, NodeID},
                   {name, NodeName},
                   {host, PriPartMgrIp},
                   {gateway, PubPartMgrIp},
                   {api_port, ApiPort},
                   {roles, [get_role_id("partition")]},
                   {remote_id, RemoteID},
                   {resources, []},
                   {subdivision, partition},
                   {subdivision_id, PartID},
                   {parent, wm_utils:get_short_name(node())},
                   {comment, "Cloud partition manager node for job " ++ JobId}],
                  wm_entity:new(node)).

-spec get_partition_manager_name(job_id()) -> string().
get_partition_manager_name(JobId) ->
    "swm-" ++ string:slice(JobId, 0, 8) ++ "-phead".

-spec ensure_nodes_cloned(partition_id(), string(), [string()], job_id(), #node{}) -> list().
ensure_nodes_cloned(_, _, [], _, _) ->
    ?LOG_ERROR("Could not clone nodes, because there are no IPs"),
    [];
ensure_nodes_cloned(PartID, ParentName, NodeIps, JobId, TplNode) when TplNode =/= undefined ->
    RemoteID = wm_entity:get(remote_id, TplNode),
    ApiPort = get_cloud_node_api_port(),
    JobRes =
        wm_entity:set([{name, "job"}, % special resource to pin node to job
                       {count, 1},
                       {properties, [{id, JobId}]}],
                      wm_entity:new(resource)),
    Rss = [JobRes | wm_entity:get(resources, TplNode)],
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
                          {resources, Rss},
                          {parent, ParentName},
                          {comment, "Cloud compute node for job " ++ JobId}],
                         wm_entity:new(node))
        end,
    ListOfPairs =
        lists:zip(
            lists:seq(0, length(NodeIps) - 1), NodeIps),
    [NewNode(P) || P <- ListOfPairs].

get_cloud_node_api_port() ->
    ?DEFAULT_CLOUD_NODE_API_PORT.

get_role_id(RoleName) ->
    {ok, Role} = wm_conf:select(role, {name, RoleName}),
    wm_entity:get(id, Role).
