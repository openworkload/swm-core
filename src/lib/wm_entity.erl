-module(wm_entity).
-behaviour(json_rec_model).

-include_lib("wm_entity.hrl").
-include("wm_log.hrl").

-export([ new/1,
          rec/1,
          pretty/1,
          get_attr/2,
          get_type/2,
          set_attr/2,
          get_names/1,
          get_fields/1,
          extract_json_field_info/1,
          get_incomparible_fields/1,
          descriptions_to_recs/1
        ]).

% https://www.python.org/about/success/cog
-define(ENTITIES, [global,
                   executable,
                   malfunction,
                   table,
                   hook,
                   grid,
                   cluster,
                   partition,
                   node,
                   resource,
                   service,
                   role,
                   job,
                   process,
                   project,
                   group,
                   user,
                   queue,
                   scheduler,
                   timetable,
                   subscriber,
                   image,
                   credential,
                   remote,
                   account,
                   metric,
                   scheduler_result,
                   boot_info,
                   test]).
-compile({parse_transform, exprecs}).
-export_records(?ENTITIES).

new(<<"global">>) -> '#new-global'();
new(global) -> '#new-global'();
new(<<"executable">>) -> '#new-executable'();
new(executable) -> '#new-executable'();
new(<<"malfunction">>) -> '#new-malfunction'();
new(malfunction) -> '#new-malfunction'();
new(<<"table">>) -> '#new-table'();
new(table) -> '#new-table'();
new(<<"hook">>) -> '#new-hook'();
new(hook) -> '#new-hook'();
new(<<"grid">>) -> '#new-grid'();
new(grid) -> '#new-grid'();
new(<<"cluster">>) -> '#new-cluster'();
new(cluster) -> '#new-cluster'();
new(<<"partition">>) -> '#new-partition'();
new(partition) -> '#new-partition'();
new(<<"node">>) -> '#new-node'();
new(node) -> '#new-node'();
new(<<"resource">>) -> '#new-resource'();
new(resource) -> '#new-resource'();
new(<<"service">>) -> '#new-service'();
new(service) -> '#new-service'();
new(<<"role">>) -> '#new-role'();
new(role) -> '#new-role'();
new(<<"job">>) -> '#new-job'();
new(job) -> '#new-job'();
new(<<"process">>) -> '#new-process'();
new(process) -> '#new-process'();
new(<<"project">>) -> '#new-project'();
new(project) -> '#new-project'();
new(<<"group">>) -> '#new-group'();
new(group) -> '#new-group'();
new(<<"user">>) -> '#new-user'();
new(user) -> '#new-user'();
new(<<"queue">>) -> '#new-queue'();
new(queue) -> '#new-queue'();
new(<<"scheduler">>) -> '#new-scheduler'();
new(scheduler) -> '#new-scheduler'();
new(<<"timetable">>) -> '#new-timetable'();
new(timetable) -> '#new-timetable'();
new(<<"subscriber">>) -> '#new-subscriber'();
new(subscriber) -> '#new-subscriber'();
new(<<"image">>) -> '#new-image'();
new(image) -> '#new-image'();
new(<<"credential">>) -> '#new-credential'();
new(credential) -> '#new-credential'();
new(<<"remote">>) -> '#new-remote'();
new(remote) -> '#new-remote'();
new(<<"account">>) -> '#new-account'();
new(account) -> '#new-account'();
new(<<"metric">>) -> '#new-metric'();
new(metric) -> '#new-metric'();
new(<<"scheduler_result">>) -> '#new-scheduler_result'();
new(scheduler_result) -> '#new-scheduler_result'();
new(<<"boot_info">>) -> '#new-boot_info'();
new(boot_info) -> '#new-boot_info'();
new(<<"test">>) -> '#new-test'();
new(test) -> '#new-test'();
new(_) -> undefined.

rec(#global{}) -> true;
rec(#executable{}) -> true;
rec(#malfunction{}) -> true;
rec(#table{}) -> true;
rec(#hook{}) -> true;
rec(#grid{}) -> true;
rec(#cluster{}) -> true;
rec(#partition{}) -> true;
rec(#node{}) -> true;
rec(#resource{}) -> true;
rec(#service{}) -> true;
rec(#role{}) -> true;
rec(#job{}) -> true;
rec(#process{}) -> true;
rec(#project{}) -> true;
rec(#group{}) -> true;
rec(#user{}) -> true;
rec(#queue{}) -> true;
rec(#scheduler{}) -> true;
rec(#timetable{}) -> true;
rec(#subscriber{}) -> true;
rec(#image{}) -> true;
rec(#credential{}) -> true;
rec(#remote{}) -> true;
rec(#account{}) -> true;
rec(#metric{}) -> true;
rec(#scheduler_result{}) -> true;
rec(#boot_info{}) -> true;
rec(#test{}) -> true;
rec(_) -> false.

get_type(global, Attr) when is_atom(Attr) ->
  case Attr of
    name -> atom;
    value -> string;
    comment -> string;
    revision -> integer
  end;
get_type(executable, Attr) when is_atom(Attr) ->
  case Attr of
    name -> string;
    path -> string;
    user -> string;
    comment -> string;
    revision -> integer
  end;
get_type(malfunction, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> binary;
    failures -> {list, {atom, any}};
    comment -> string;
    revision -> integer
  end;
get_type(table, Attr) when is_atom(Attr) ->
  case Attr of
    name -> binary;
    fields -> {list, any};
    revision -> integer
  end;
get_type(hook, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    event -> atom;
    state -> atom;
    executable -> {list, any};
    comment -> string;
    revision -> integer
  end;
get_type(grid, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    state -> atom;
    manager -> string;
    clusters -> {list, string};
    hooks -> {list, string};
    scheduler -> integer;
    resources -> {list, {record, resource}};
    properties -> {list, {atom, any}};
    comment -> string;
    revision -> integer
  end;
get_type(cluster, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    state -> atom;
    manager -> string;
    partitions -> {list, string};
    hooks -> {list, string};
    scheduler -> integer;
    resources -> {list, {record, resource}};
    properties -> {list, {atom, any}};
    comment -> string;
    revision -> integer
  end;
get_type(partition, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    state -> atom;
    manager -> string;
    nodes -> {list, string};
    partitions -> {list, string};
    hooks -> {list, string};
    scheduler -> integer;
    jobs_per_node -> integer;
    resources -> {list, {record, resource}};
    properties -> {list, {atom, any}};
    subdivision -> atom;
    subdivision_id -> string;
    created -> string;
    updated -> string;
    external_id -> string;
    addresses -> map;
    comment -> string;
    revision -> integer
  end;
get_type(node, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    host -> string;
    api_port -> integer;
    parent -> string;
    state_power -> atom;
    state_alloc -> atom;
    roles -> {list, integer};
    resources -> {list, {record, resource}};
    properties -> {list, {atom, any}};
    subdivision -> atom;
    subdivision_id -> string;
    malfunctions -> {list, integer};
    comment -> string;
    remote_id -> string;
    is_template -> atom;
    gateway -> string;
    prices -> map;
    revision -> integer
  end;
get_type(resource, Attr) when is_atom(Attr) ->
  case Attr of
    name -> string;
    count -> integer;
    hooks -> {list, string};
    properties -> {list, {atom, any}};
    prices -> map;
    usage_time -> integer;
    resources -> {list, {record, resource}}
  end;
get_type(service, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    modules -> {list, string};
    tables -> {list, atom};
    comment -> string;
    revision -> integer
  end;
get_type(role, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    services -> {list, integer};
    comment -> string;
    revision -> integer
  end;
get_type(job, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    cluster_id -> string;
    nodes -> {list, string};
    state -> string;
    job_class -> {list, atom};
    start_time -> string;
    submit_time -> string;
    end_time -> string;
    duration -> integer;
    job_stdin -> string;
    job_stdout -> string;
    job_stderr -> string;
    input_files -> {list, string};
    output_files -> {list, string};
    workdir -> string;
    user_id -> string;
    hooks -> {list, string};
    env -> {list, {string, string}};
    deps -> {list, {atom, string}};
    steps -> {list, string};
    projects -> {list, integer};
    account_id -> string;
    gang_id -> string;
    task_id -> string;
    script -> binary;
    request -> {list, {record, resource}};
    resources -> {list, {record, resource}};
    container -> string;
    relocatable -> atom;
    exitcode -> integer;
    signal -> integer;
    priority -> integer;
    comment -> string;
    revision -> integer
  end;
get_type(process, Attr) when is_atom(Attr) ->
  case Attr of
    pid -> integer;
    state -> string;
    exitcode -> integer;
    signal -> integer;
    comment -> string
  end;
get_type(project, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    acl -> string;
    hooks -> {list, string};
    priority -> integer;
    comment -> string;
    revision -> integer
  end;
get_type(group, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    acl -> string;
    priority -> integer;
    comment -> string;
    revision -> integer
  end;
get_type(user, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> string;
    acl -> string;
    groups -> {list, integer};
    projects -> {list, integer};
    priority -> integer;
    comment -> string;
    revision -> integer
  end;
get_type(queue, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    state -> atom;
    jobs -> {list, string};
    nodes -> {list, string};
    users -> {list, string};
    admins -> {list, string};
    hooks -> {list, string};
    priority -> integer;
    comment -> string;
    revision -> integer
  end;
get_type(scheduler, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    state -> atom;
    start_time -> string;
    stop_time -> string;
    run_interval -> integer;
    path -> {list, string};
    family -> string;
    version -> string;
    cu -> integer;
    comment -> string;
    revision -> integer
  end;
get_type(timetable, Attr) when is_atom(Attr) ->
  case Attr of
    start_time -> integer;
    job_id -> string;
    job_nodes -> {list, string}
  end;
get_type(subscriber, Attr) when is_atom(Attr) ->
  case Attr of
    ref -> {list, string};
    event -> atom;
    revision -> integer
  end;
get_type(image, Attr) when is_atom(Attr) ->
  case Attr of
    name -> string;
    id -> string;
    tags -> {list, string};
    size -> integer;
    kind -> atom;
    status -> string;
    created -> string;
    updated -> string;
    comment -> string;
    revision -> integer
  end;
get_type(credential, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    remote_id -> string;
    tenant_name -> string;
    tenant_domain_name -> string;
    username -> string;
    password -> string;
    key_name -> string;
    revision -> integer
  end;
get_type(remote, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    account_id -> string;
    name -> atom;
    kind -> atom;
    server -> string;
    port -> integer;
    revision -> integer
  end;
get_type(account, Attr) when is_atom(Attr) ->
  case Attr of
    id -> string;
    name -> atom;
    price_list -> string;
    users -> {list, string};
    admins -> {list, string};
    comment -> string;
    revision -> integer
  end;
get_type(metric, Attr) when is_atom(Attr) ->
  case Attr of
    name -> atom;
    value_integer -> integer;
    value_float64 -> {list, string}
  end;
get_type(scheduler_result, Attr) when is_atom(Attr) ->
  case Attr of
    timetable -> {list, {record, timetable}};
    metrics -> {list, {record, metric}};
    request_id -> string;
    status -> integer;
    astro_time -> {list, {record, metric}};
    idle_time -> {list, {record, metric}};
    work_time -> {list, {record, metric}}
  end;
get_type(boot_info, Attr) when is_atom(Attr) ->
  case Attr of
    node_host -> string;
    node_port -> integer;
    parent_host -> string;
    parent_port -> integer
  end;
get_type(test, Attr) when is_atom(Attr) ->
  case Attr of
    id -> integer;
    name -> string;
    state -> atom;
    state8 -> atom;
    start_time3 -> string;
    stop_time -> {list, string};
    hooks -> {list, {record, {hook_id, resource, user}}};
    comment -> string;
    revision -> integer
  end.

get_names(all) -> ?ENTITIES;
get_names(local) -> [job];
get_names(local_bag) -> [subscriber, timetable];
get_names(non_replicable) -> [schema, subscriber, timetable, job];
get_names(with_ids) ->
  [malfunction, hook, grid, cluster, partition, node, service, role, job, project, group, user, queue, scheduler, image, credential, remote, account, test].


%% @doc get all record field names
get_fields(Rec) ->
  '#info-'(Rec).

%% @doc get an attribute by name
get_attr(Attr, Rec) when is_atom(Attr) ->
  '#get-'(Attr, Rec).

%% @doc set an attribute by name
set_attr({Attr, Value}, Rec) when is_atom(Attr) ->
  '#set-'([{Attr,Value}], Rec);

set_attr(Xs, Rec) when is_list(Xs) ->
  lists:foldl(fun({Attr, Value}, Acc) -> set_attr({Attr, Value}, Acc) end, Rec, Xs).

pretty(Recs) when is_list(Recs) ->
  lists:map(fun(R) -> pretty(R) end, Recs);
pretty(Rec) ->
  RF = fun(R,L) when R == element(1, Rec) ->
         Flds = '#info-'(R),
         true = (L == length(Flds)),
         Flds
       end,
  [io_lib_pretty:print(Rec, RF),"\n"].

decode_json_default(<<>>, _) ->
  "";
decode_json_default(X, atom) when is_binary(X) ->
  binary_to_atom(X, utf8);
decode_json_default(X, any) when is_binary(X) ->
  binary_to_atom(X, utf8);
decode_json_default(X, string) when is_binary(X) ->
  binary:bin_to_list(X);
decode_json_default(_, {record,R}) ->
  wm_entity:new(R);
decode_json_default(X, {list,T}) when is_list(X)->
  [decode_json_default(E,T) || E <- X];
decode_json_default(X, _) ->
  X.

decode_json_type(<<" ",X/binary>>) ->
  decode_json_type(X);
decode_json_type(<<"{",X/binary>>) ->
  Skip = byte_size(X) - 1,
  <<Y:Skip/binary, "}">> = X,
  BinList = binary:split(Y, [<<",">>], [global]),
  AtomList = lists:map(fun(Item) -> decode_json_type(Item) end, BinList),
  list_to_tuple(AtomList);
decode_json_type(<<"#",X/binary>>) ->
  {record, decode_json_type(X)};
decode_json_type(<<"[",X/binary>>) ->
  Skip = byte_size(X) - 1,
  <<Y:Skip/binary, "]">> = X,
  {list, decode_json_type(Y)};
decode_json_type(X) ->
  Skip = byte_size(X) - 2,
  case X of
    <<Y:Skip/binary, "()">> ->
      binary_to_atom(Y, utf8);
    <<Y:Skip/binary, "{}">> ->
      binary_to_atom(Y, utf8);
    Y ->
      binary_to_atom(Y, utf8)
  end.

extract_json_field_info({NameBin, {struct, [{<<"type">>, TypeBin}]}}) ->
  extract_json_field_info({NameBin, {struct, [{<<"default">>, []},
                                              {<<"type">>, TypeBin}]}});
extract_json_field_info({NameBin, {struct, [{<<"default">>, DefaultBin},
                                            {<<"type">>, TypeBin}]}}) ->
  Name = binary_to_atom(NameBin, utf8),
  Type = decode_json_type(TypeBin),
  Default = decode_json_default(DefaultBin, Type),
  ?LOG_DEBUG("Extract JSON field info: name=~p; default=~p; type=~p",
              [Name, Default, Type]),
  {Name, Default, Type}.

%% @doc The function returns table of properties that can be different on
%% different nodes and this is expected, so we treat such entities as identical
get_incomparible_fields(node) ->
  [state_power, state_alloc, revision];
get_incomparible_fields(_) ->
  [].

descriptions_to_recs(Ds) ->
  descriptions_to_recs(Ds, []).

descriptions_to_recs([], Recs) ->
  Recs;
descriptions_to_recs([{Name, AttrPairs}|T], Recs) ->
  Rec1 = ?MODULE:new(Name),
  Rec2 = description_to_entity(AttrPairs, Rec1),
  descriptions_to_recs(T, [Rec2|Recs]).

description_to_entity([], Rec) ->
  Rec;
description_to_entity([{resources,ResDescList}|T], Rec) when is_list(ResDescList) ->
  F = fun({resource, ResAttrs}) when is_list(ResAttrs) ->
        ResRec = ?MODULE:new(resource),
        description_to_entity(ResAttrs, ResRec)
      end,
  ResRecs = lists:map(F, ResDescList),
  Rec2 = ?MODULE:set_attr({resources, ResRecs}, Rec),
  description_to_entity(T, Rec2);
description_to_entity([AttrPair|T], Rec) ->
  Rec2 = ?MODULE:set_attr(AttrPair, Rec),
  description_to_entity(T, Rec2).

