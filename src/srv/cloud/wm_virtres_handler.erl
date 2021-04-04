-module(wm_virtres_handler).

-export([validate_partition/2, request_partition_existence/2, is_job_partition_ready/1, update_job/2, start_uploading/2,
         start_downloading/2, delete_partition/2]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-spec validate_partition(string(), #remote{}) -> {atom(), string()}.
validate_partition(JobID, Remote) ->
    ?LOG_INFO("Validate remote partition (job: ~p)", [JobID]),
    PartName = get_partition_name(JobID),
    {ok, Creds} = get_credentials(Remote),
    {ok, Ref} = wm_gate:partition_exists(self(), Remote, Creds, PartName),
    {validating, Ref}.

-spec request_partition_existence(string(), #remote{}) -> {atom(), string()}.
request_partition_existence(JobID, Remote) ->
    ?LOG_INFO("Request partition existence (job: ~p)", [JobID]),
    PartName = get_partition_name(JobID),
    {ok, Creds} = get_credentials(Remote),
    {ok, Ref} = wm_gate:partition_exists(self(), Remote, Creds, PartName),
    {creating, Ref}.

-spec get_partition_name(string()) -> string().
get_partition_name(JobID) ->
    "swm-" ++ string:slice(JobID, 0, 8).

-spec get_credentials(#remote{}) -> #credential{}.
get_credentials(Remote) ->
    RemoteID = wm_entity:get_attr(id, Remote),
    wm_conf:select(credential, {remote_id, RemoteID}).

-spec is_job_partition_ready(string()) -> true | false.
is_job_partition_ready(JobID) ->
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    NodeIds = wm_entity:get_attr(nodes, Job),
    NotReady =
        fun(NodeID) ->
           {ok, Node} = wm_conf:select(node, {id, NodeID}),
           idle =/= wm_entity:get_attr(state_alloc, Node)
        end,
    lists:any(NotReady, NodeIds).

-spec update_job(list(), string()) -> 1.
update_job(NewParams, JobID) ->
    {ok, Job1} = wm_conf:select(job, {id, JobID}),
    Job2 = wm_entity:set_attr(NewParams, Job1),
    1 = wm_conf:update(Job2).

-spec start_uploading(string(), string()) -> {ok, string()}.
start_uploading(PartMgrNodeID, JobID) ->
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    Priority = wm_entity:get_attr(priority, Job),
    WorkDir = wm_entity:get_attr(workdir, Job),
    StdInFile = wm_entity:get_attr(job_stdin, Job),
    InputFiles = wm_entity:get_attr(input_files, Job),
    JobScript = wm_entity:get_attr(script, Job),
    %TODO: transfer also container image
    Files = lists:filter(fun(X) -> X =/= [] end, [JobScript, StdInFile | InputFiles]),
    {ok, ToNode} = wm_conf:select(node, {id, PartMgrNodeID}),
    {ok, MyNode} = wm_self:get_node(),
    {ToAddr, _} = wm_conf:get_relative_address(ToNode, MyNode),
    % TODO copy files to their own dirs, not in workdir, unless the full path is not set
    wm_file_transfer:upload(self(), ToAddr, Priority, Files, WorkDir, #{via => ssh}).

-spec start_downloading(string(), string()) -> {ok, string()}.
start_downloading(PartMgrNodeID, JobID) ->
    {ok, Job} = wm_conf:select(job, {id, JobID}),
    Priority = wm_entity:get_attr(priority, Job),
    WorkDir = wm_entity:get_attr(workdir, Job),
    OutputFiles = wm_entity:get_attr(output_files, Job),
    StdErrFile = wm_entity:get_attr(job_stderr, Job),
    StdOutFile = wm_entity:get_attr(job_stdout, Job),
    StdErrPath = filename:join([WorkDir, StdErrFile]),
    StdOutPath = filename:join([WorkDir, StdOutFile]),
    Files = lists:filter(fun(X) -> X =/= [] end, [StdErrPath, StdOutPath | OutputFiles]),
    {ok, FromNode} = wm_conf:select(node, {id, PartMgrNodeID}),
    {ok, MyNode} = wm_self:get_node(),
    {FromAddr, _} = wm_conf:get_relative_address(FromNode, MyNode),
    % TODO allow to copy files which paths are defined in a file that will be generated in cloud
    {ok, Ref} = wm_file_transfer:download(self(), FromAddr, Priority, Files, WorkDir, #{via => ssh}),
    {ok, Ref, Files}.

-spec delete_partition(string(), #remote{}) -> {ok, string()} | {error, atom()}.
delete_partition(PartId, Remote) ->
    case wm_conf:select(partition, {id, PartId}) of
        {ok, Partition} ->
            PartName = wm_entity:get_atter(name, Partition),
            {ok, Creds} = get_credentials(Remote),
            wm_gate:delete_partition(self(), Remote, Creds, PartName);
        {error, Error} ->
            {error, Error}
    end.
