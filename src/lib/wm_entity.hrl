%%
%% Main data structures
%%

-type grid_id()         :: string().
-type cluster_id()      :: string().
-type partition_id()    :: string().
-type node_id()         :: string().
-type credential_id()   :: string().
-type remote_id()       :: string().
-type account_id()      :: string().
-type user_id()         :: string().
-type hook_id()         :: string().
-type job_id()          :: string().
-type image_id()        :: string().
-type relocation_id()   :: integer().
-type node_address()    :: {string(), integer()}.

-record (executable, {
           name :: string(),
           path = "" :: string(),
           user = "" :: user_id(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (hook, {
           id :: hook_id(),
           name = "" :: string(),
           event :: atom(),
           state = enabled :: atom(),
           executable :: #executable{},
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (resource, {
           name :: string(),
           count = 1 :: pos_integer(),
           hooks = [] :: [hook_id()],
           properties = [] :: [{atom(), any()}],
           prices = #{} :: map(),
           usage_time = 1 :: pos_integer(),
           resources = [] :: [#resource{}]
    }).
-record (global, {
           name :: atom(),
           value :: string(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (malfunction, {
           id = 0 :: pos_integer(),
           name :: binary(),
           failures = [] :: [{atom(), any()}],
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (table, {
           name :: binary(),
           fields = [] :: [any()],
           revision = 0 :: pos_integer()
    }).
-record (grid, {
           id = "" :: grid_id(),
           name = "" :: string(),
           state = down :: atom(),
           manager = "" :: string(),
           clusters = [] :: [cluster_id()],
           hooks = [] :: [hook_id()],
           scheduler = 0 :: pos_integer(),
           resources = [] :: [#resource{}],
           properties = [] :: [{atom(), any()}],
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (cluster, {
           id :: cluster_id(),
           name = "" :: string(),
           state = down :: atom(),
           manager = "" :: string(),
           partitions = [] :: [partition_id()],
           hooks = [] :: [hook_id()],
           scheduler = 0 :: pos_integer(),
           resources = [] :: [#resource{}],
           properties = [] :: [{atom(), any()}],
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (partition, {
           id :: partition_id(),
           name = "" :: string(),
           state = down :: atom(),
           manager = "" :: string(),
           nodes = [] :: [node_id()],
           partitions = [] :: [partition_id()],
           hooks = [] :: [hook_id()],
           scheduler = 0 :: pos_integer(),
           jobs_per_node = 1 :: pos_integer(),
           resources = [] :: [#resource{}],
           properties = [] :: [{atom(), any()}],
           subdivision = grid :: atom(),
           subdivision_id = "" :: string(),
           created = "" :: string(),
           updated = "" :: string(),
           external_id = "" :: string(),
           addresses = #{} :: map(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (node, {
           id = 0 :: node_id(),
           name = "" :: string(),
           host = "" :: string(),
           api_port = 0 :: pos_integer(),
           parent = "" :: string(),
           state_power = down :: atom(),
           state_alloc = stopped :: atom(),
           roles = [] :: [pos_integer()],
           resources = [] :: [#resource{}],
           properties = [] :: [{atom(), any()}],
           subdivision = grid :: atom(),
           subdivision_id = "" :: string(),
           malfunctions = [] :: [pos_integer()],
           comment = "" :: string(),
           remote_id = "" :: remote_id(),
           is_template = false :: atom(),
           gateway = "" :: string(),
           prices = #{} :: map(),
           revision = 0 :: pos_integer()
    }).
-record (service, {
           id = 0 :: pos_integer(),
           name :: string(),
           modules = [] :: [string()],
           tables = [] :: [atom()],
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (role, {
           id = 0 :: pos_integer(),
           name :: string(),
           services = [] :: [pos_integer()],
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (job, {
           id :: string(),
           name = "" :: string(),
           cluster_id = "" :: cluster_id(),
           nodes = [] :: [node_id()],
           state = "Q" :: string(),
           job_class = [] :: [atom()],
           start_time = "" :: string(),
           submit_time = "" :: string(),
           end_time = "" :: string(),
           duration = 0 :: pos_integer(),
           job_stdin = "" :: string(),
           job_stdout = "" :: string(),
           job_stderr = "" :: string(),
           input_files = [] :: [string()],
           output_files = [] :: [string()],
           workdir = "" :: string(),
           user_id = "" :: user_id(),
           hooks = [] :: [hook_id()],
           env = [] :: [{string(), string()}],
           deps = [] :: [{atom(), string()}],
           steps = [] :: [string()],
           projects = [] :: [pos_integer()],
           account_id = "" :: account_id(),
           gang_id = "" :: string(),
           task_id = "" :: string(),
           execution_path = "" :: string(),
           script_content = "" :: string(),
           request = [] :: [#resource{}],
           resources = [] :: [#resource{}],
           container = "" :: string(),
           relocatable = true :: atom(),
           exitcode = 0 :: pos_integer(),
           signal = 0 :: pos_integer(),
           priority = 0 :: pos_integer(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (process, {
           pid = -1 :: integer(),
           state = "unknown" :: string(),
           exitcode = -1 :: integer(),
           signal = -1 :: integer(),
           comment = "" :: string()
    }).
-record (project, {
           id = 0 :: pos_integer(),
           name :: string(),
           acl = "all" :: string(),
           hooks = [] :: [hook_id()],
           priority = 0 :: integer(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (group, {
           id = 0 :: pos_integer(),
           name :: string(),
           acl = "all" :: string(),
           priority = 0 :: integer(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (user, {
           id :: user_id(),
           name :: string(),
           acl = "" :: string(),
           groups = [] :: [pos_integer()],
           projects = [] :: [pos_integer()],
           priority = 0 :: integer(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (queue, {
           id = 0 :: pos_integer(),
           name :: string(),
           state = stopped :: atom(),
           jobs = [] :: [string()],
           nodes = [] :: [node_id()],
           users = [] :: [user_id()],
           admins = [] :: [user_id()],
           hooks = [] :: [hook_id()],
           priority = 0 :: integer(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (scheduler, {
           id = 0 :: pos_integer(),
           name :: string(),
           state = enabled :: atom(),
           start_time = "" :: string(),
           stop_time = "" :: string(),
           run_interval = 30000 :: pos_integer(),
           path :: #executable{},
           family = "fcfs" :: string(),
           version = "" :: string(),
           cu = 0 :: pos_integer(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (timetable, {
           start_time :: pos_integer(),
           job_id :: string(),
           job_nodes = [] :: [node_id()]
    }).
-record (relocation, {
           id :: relocation_id(),
           job_id :: job_id(),
           template_node_id :: node_id(),
           canceled = false :: atom()
    }).
-record (subscriber, {
           ref :: {atom(), atom()},
           event = any_event :: atom(),
           revision = 0 :: pos_integer()
    }).
-record (image, {
           name :: string(),
           id :: image_id(),
           tags = [] :: [string()],
           size = 0 :: pos_integer(),
           kind :: atom(),
           status :: string(),
           remote_id :: remote_id(),
           created = "" :: string(),
           updated = "" :: string(),
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (credential, {
           id :: credential_id(),
           remote_id :: remote_id(),
           tenant_name :: string(),
           tenant_domain_name :: string(),
           username :: string(),
           password :: string(),
           key_name = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (remote, {
           id :: remote_id(),
           account_id :: account_id(),
           default_image_id :: image_id(),
           default_flavor_id :: node_id(),
           name :: atom(),
           kind = local :: atom(),
           server :: string(),
           port = 8444 :: pos_integer(),
           revision = 0 :: pos_integer()
    }).
-record (account, {
           id :: account_id(),
           name :: atom(),
           price_list = "" :: string(),
           users = [] :: [user_id()],
           admins = [] :: [user_id()],
           comment = "" :: string(),
           revision = 0 :: pos_integer()
    }).
-record (metric, {
           name :: atom(),
           value_integer = 0 :: pos_integer(),
           value_float64 = 0.0 :: float()
    }).
-record (scheduler_result, {
           timetable = [] :: [#timetable{}],
           metrics = [] :: [#metric{}],
           request_id :: string(),
           status = 0 :: pos_integer(),
           astro_time = 0 :: float(),
           idle_time = 0 :: float(),
           work_time = 0 :: float()
    }).
-record (boot_info, {
           node_host :: string(),
           node_port = 0 :: pos_integer(),
           parent_host :: string(),
           parent_port = 0 :: pos_integer()
    }).
-record (test, {
           id = 1 :: pos_integer(),
           name = "dev0" :: string(),
           state = enabled :: atom(),
           state8 = enabled :: atom(),
           start_time3 = "30 22:14:53" :: string(),
           stop_time = [] :: [string()],
           hooks :: [{hook_id(), #resource{}, #user{}}],
           comment :: string(),
           revision = 0 :: pos_integer()
    }).

