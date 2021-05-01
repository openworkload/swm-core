-module(wm_ctl).

-export([grid/2, cluster/2, partition/2, node/2, user/2, queue/2, scheduler/2, image/2, overview/2, global/2,
         remote/2]).

%% ============================================================================
%% API functions
%% ============================================================================

overview(grid, ConnArgs) ->
    Format = "%10A %10I %10D %10O %10B",
    wm_ctl_cli:overview({header, grid}, Format, ""),
    case rpc_get(cluster, ConnArgs) of
        Xs1 when is_list(Xs1) ->
            [wm_ctl_cli:overview({{grid, cluster}, X}, Format, "CLUSTERS") || X <- Xs1];
        {error, E1} ->
            Str1 = inet:format_error(E1),
            fatal_error(Str1 ++ " (check SWM_API_PORT and SWM_API_HOST)")
    end,
    case rpc_get(partition, ConnArgs) of
        Xs2 when is_list(Xs2) ->
            [wm_ctl_cli:overview({{grid, partition}, X}, Format, "PARTITIONS") || X <- Xs2];
        {error, E2} ->
            Str2 = inet:format_error(E2),
            fatal_error(Str2 ++ " (check SWM_API_PORT and SWM_API_HOST)")
    end,
    case rpc_get(node, ConnArgs) of
        Xs3 when is_list(Xs3) ->
            [wm_ctl_cli:overview({{grid, node}, X}, Format, "NODES") || X <- Xs3];
        {error, E3} ->
            Str3 = inet:format_error(E3),
            fatal_error(Str3 ++ " (check SWM_API_PORT and SWM_API_HOST)")
    end;
overview(jobs, ConnArgs) ->
    Format = "%10A %10Q %10R %10E %10C",
    wm_ctl_cli:overview({header, jobs}, Format, ""),
    case rpc_get(job, ConnArgs) of
        Xs when is_list(Xs) ->
            [wm_ctl_cli:overview({jobs, X}, Format, "JOBS") || X <- Xs];
        {error, E} ->
            Str = inet:format_error(E),
            fatal_error(Str ++ " (check SWM_API_PORT and SWM_API_HOST)")
    end.

remote({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["list" | T] ->
            remote(list, T, Ent, ConnArgs);
        ["show" | T] ->
            remote(show, T, Ent, ConnArgs);
        ["set" | T] ->
            remote(set, T, Ent, ConnArgs);
        ["create" | T] ->
            remote(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            remote(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            remote(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent;
        Else ->
            unknown_arg(Else),
            Ent
    end.

global({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["list" | T] ->
            global(list, T, Ent, ConnArgs);
        ["show" | T] ->
            global(show, T, Ent, ConnArgs);
        ["set" | T] ->
            global(set, T, Ent, ConnArgs);
        ["export" | T] ->
            global(export, T, Ent, ConnArgs);
        ["import" | T] ->
            global(import, T, Ent, ConnArgs);
        ["update" | T] ->
            global(update, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent;
        Else ->
            unknown_arg(Else),
            Ent
    end.

grid({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["route" | T] ->
            grid(route, T, Ent, ConnArgs);
        ["list" | T] ->
            grid(list, T, Ent, ConnArgs);
        ["show" | T] ->
            grid(show, T, Ent, ConnArgs);
        ["ca" | T] ->
            grid(ca, T, Ent, ConnArgs);
        ["sim" | T] ->
            grid(sim, T, Ent, ConnArgs);
        ["create" | T] ->
            grid(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            grid(remove, T, Ent, ConnArgs);
        ["tree" | T] ->
            grid(tree, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent;
        Else ->
            unknown_arg(Else),
            Ent
    end.

cluster({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            cluster(set, T, Ent, ConnArgs);
        ["list" | T] ->
            cluster(list, T, Ent, ConnArgs);
        ["show" | T] ->
            cluster(show, T, Ent, ConnArgs);
        ["ca" | T] ->
            cluster(ca, T, Ent, ConnArgs);
        ["create" | T] ->
            cluster(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            cluster(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            cluster(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

partition({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            partition(set, T, Ent, ConnArgs);
        ["list" | T] ->
            partition(list, T, Ent, ConnArgs);
        ["show" | T] ->
            partition(show, T, Ent, ConnArgs);
        ["create" | T] ->
            partition(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            partition(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            partition(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

node({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            node(set, T, Ent, ConnArgs);
        ["list" | T] ->
            node(list, T, Ent, ConnArgs);
        ["show" | T] ->
            node(show, T, Ent, ConnArgs);
        ["cert" | T] ->
            node(cert, T, Ent, ConnArgs);
        ["startsim" | T] ->
            node(startsim, T, Ent, ConnArgs);
        ["stopsim" | T] ->
            node(stopsim, T, Ent, ConnArgs);
        ["create" | T] ->
            node(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            node(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            node(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

user({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            user(set, T, Ent, ConnArgs);
        ["list" | T] ->
            user(list, T, Ent, ConnArgs);
        ["show" | T] ->
            user(show, T, Ent, ConnArgs);
        ["cert" | T] ->
            user(cert, T, Ent, ConnArgs);
        ["create" | T] ->
            user(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            user(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            user(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

queue({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            queue(set, T, Ent, ConnArgs);
        ["list" | T] ->
            queue(list, T, Ent, ConnArgs);
        ["show" | T] ->
            queue(show, T, Ent, ConnArgs);
        ["create" | T] ->
            queue(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            queue(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            queue(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

scheduler({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            scheduler(set, T, Ent, ConnArgs);
        ["list" | T] ->
            scheduler(list, T, Ent, ConnArgs);
        ["show" | T] ->
            scheduler(show, T, Ent, ConnArgs);
        ["create" | T] ->
            scheduler(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            scheduler(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            scheduler(clone, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

image({ArgsDict, Ent}, ConnArgs) ->
    case wm_args:fetch(free_arg, unknown, ArgsDict) of
        ["use" | T] ->
            get_entity_submode(hd(T));
        ["set" | T] ->
            image(set, T, Ent, ConnArgs);
        ["list" | T] ->
            image(list, T, Ent, ConnArgs);
        ["show" | T] ->
            image(show, T, Ent, ConnArgs);
        ["create" | T] ->
            image(create, T, Ent, ConnArgs);
        ["remove" | T] ->
            image(remove, T, Ent, ConnArgs);
        ["clone" | T] ->
            image(clone, T, Ent, ConnArgs);
        ["register" | T] ->
            image(register, T, Ent, ConnArgs);
        [Unknown | _] ->
            unknown_arg(Unknown),
            Ent
    end.

%% ============================================================================
%% Implementation functions
%% ============================================================================

get_entity_submode(Ent) ->
    Ent.

unknown_arg(Arg) ->
    io:format("Command not found: ~s~n", [Arg]).

global(list, _, Ent, ConnArgs) ->
    rpc_list(global, "%26N %24V %0C", ConnArgs),
    get_entity_submode(Ent);
global(show, Args, Ent, ConnArgs) ->
    rpc_show(global, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
global(set, Args, Ent, ConnArgs) ->
    rpc_set(global, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
global(import, [File | _Args], Ent, _ConnArgs) ->
    case filelib:is_file(File) of
        false ->
            io:format("No such file: ~p~n", [File]);
        true ->
            Data = consult(File),
            case wm_rpc:call(wm_admin, global, {import, Data}) of
                [] ->
                    fatal_error("Imported nothing");
                List when is_list(List) ->
                    case hd(List) of
                        {integer, N} ->
                            io:format("Number of imported entities: ~p~n", [N]);
                        {string, S} ->
                            io:format("~p~n", S);
                        Error ->
                            fatal_error(Error)
                    end;
                {error, E} ->
                    Str = inet:format_error(E),
                    fatal_error(Str ++ " (check SWM_API_PORT and SWM_API_HOST)")
            end
    end,
    get_entity_submode(Ent);
global(export, [], Ent, _ConnArgs) ->
    Answer = wm_rpc:call(wm_admin, global, {export}),
    io:format("~nAnswer:~n~p~n", [Answer]),
    get_entity_submode(Ent);
global(update, ["schema" | Args], Ent, ConnArgs) ->
    SchemaFile = hd(Args),
    case filelib:is_file(SchemaFile) of
        false ->
            io:format("No such file: ~p~n", [SchemaFile]);
        true ->
            {ok, Data} = file:read_file(SchemaFile),
            case wm_rpc:call(wm_admin, global, {update, Data}) of
                List when is_list(List) ->
                    F = fun Print({ok, Z}) ->
                                Print(Z);
                            Print(L) when is_list(L) ->
                                [Print(E) || E <- L];
                            Print(Z) ->
                                io:format("~p~n", [Z])
                        end,
                    [F(X) || X <- List];
                Error ->
                    fatal_error(Error)
            end
    end,
    get_entity_submode(Ent).

grid(route, [From, To | _], Ent, ConnArgs) ->
    rpc_generic(grid, {route, From, To}, ConnArgs),
    get_entity_submode(Ent);
grid(tree, ["static" | _], Ent, ConnArgs) ->
    case wm_rpc:call(wm_admin, grid, {tree, static}) of
        [{map, Map}] ->
            wm_ctl_cli:show(tree, Map);
        {string, String} ->
            io:format("~s~n", [String])
    end,
    get_entity_submode(Ent);
grid(sim, [Action | T], Ent, ConnArgs) ->
    case Action of
        "start" ->
            case wm_rpc:call(wm_admin, grid, {sim, start, T}) of
                Xs when is_list(Xs) ->
                    [io:format("~p~n", [X]) || {_, X} <- Xs];
                {error, Error} ->
                    fatal_error(Error)
            end;
        "stop" ->
            case wm_rpc:call(wm_admin, grid, {sim, stop, T}) of
                Xs when is_list(Xs) ->
                    [io:format("~p~n", [X]) || {_, X} <- Xs];
                {error, Error} ->
                    fatal_error(Error)
            end
    end,
    get_entity_submode(Ent);
grid(ca, [Action | Args], Ent, _) ->
    %TODO connect to SWM, add a grid and get ID (and name?)
    GridName = "grid",
    GridID = wm_utils:uuid(v4),
    case Action of
        "create" ->
            wm_cert:create(grid, GridID, GridName)
    end,
    get_entity_submode(Ent);
grid(show, _, Ent, ConnArgs) ->
    overview(grid, ConnArgs),
    overview(jobs, ConnArgs),
    get_entity_submode(Ent);
grid(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(grid, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
grid(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

cluster(set, Args, Ent, ConnArgs) ->
    rpc_set(cluster, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
cluster(get, Args, Ent, ConnArgs) ->
    rpc_get(cluster, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
cluster(show, Args, Ent, ConnArgs) ->
    rpc_show(cluster, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
cluster(list, _, Ent, ConnArgs) ->
    rpc_list(cluster, "%10N %8S %12P %0C", ConnArgs),
    get_entity_submode(Ent);
cluster(ca, [Action | Args], Ent, _) ->
    %TODO connect to SWM, add a cluser, get ID (and name?)
    ClusterID = wm_utils:uuid(v4),
    ClusterName = "cluster",
    case Action of
        "create" ->
            wm_cert:create(cluster, ClusterID, ClusterName)
    end,
    get_entity_submode(Ent);
cluster(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(cluster, Name, Args, ConnArgs),
    get_entity_submode(Ent);
cluster(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(cluster, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
cluster(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(cluster, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
cluster(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

partition(set, Args, Ent, ConnArgs) ->
    rpc_set(partition, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
partition(get, Args, Ent, ConnArgs) ->
    rpc_get(partition, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
partition(show, Args, Ent, ConnArgs) ->
    rpc_show(partition, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
partition(list, _, Ent, ConnArgs) ->
    rpc_list(partition, "%16N %8S %10H %0C", ConnArgs),
    get_entity_submode(Ent);
partition(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(partition, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
partition(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(partition, Name, Args, ConnArgs),
    get_entity_submode(Ent);
partition(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(partition, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
partition(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

node(set, Args, Ent, ConnArgs) ->
    rpc_set(node, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
node(get, Args, Ent, ConnArgs) ->
    rpc_get(node, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
node(show, Args, Ent, ConnArgs) ->
    rpc_show(node, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
node(cert, [Action | Args], Ent, _) ->
    %TODO connect to SWM, add a node, get ID and name
    NodeID = wm_utils:uuid(v4),
    NodeName = "node",
    case Action of
        "create" ->
            wm_cert:create(node, NodeID, NodeName)
    end,
    get_entity_submode(Ent);
node(list, _, Ent, ConnArgs) ->
    rpc_list(node, "%19N %6S %8A %6P %27H %0G", ConnArgs),
    get_entity_submode(Ent);
node(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(node, Name, Args, ConnArgs),
    get_entity_submode(Ent);
node(startsim, [Name | _], Ent, ConnArgs) ->
    rpc_generic(node, {startsim, Name}, ConnArgs),
    get_entity_submode(Ent);
node(stopsim, [Name | _], Ent, ConnArgs) ->
    rpc_generic(node, {stopsim, Name}, ConnArgs),
    get_entity_submode(Ent);
node(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(node, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
node(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(node, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
node(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

user(set, Args, Ent, ConnArgs) ->
    rpc_set(user, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
user(get, Args, Ent, ConnArgs) ->
    rpc_get(user, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
user(show, Args, Ent, ConnArgs) ->
    rpc_show(user, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
user(list, _, Ent, ConnArgs) ->
    rpc_list(user, "%16N %8G %12P %0C", ConnArgs),
    get_entity_submode(Ent);
user(cert, [Action | Args], Ent, _) ->
    %TODO get user ID and Name from DB first and put it to the new certificate
    UserID = "notimplemented",
    UserName = "notimplemented",
    case Action of
        "create" ->
            wm_cert:create(user, UserID, UserName)
    end,
    get_entity_submode(Ent);
user(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(user, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
user(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(user, Name, Args, ConnArgs),
    get_entity_submode(Ent);
user(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(user, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
user(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

queue(set, Args, Ent, ConnArgs) ->
    rpc_set(queue, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
queue(get, Args, Ent, ConnArgs) ->
    rpc_get(queue, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
queue(show, Args, Ent, ConnArgs) ->
    rpc_show(queue, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
queue(list, _, Ent, ConnArgs) ->
    rpc_list(queue, "%16N %8S %8H %8J %0C", ConnArgs),
    get_entity_submode(Ent);
queue(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(queue, Name, Args, ConnArgs),
    get_entity_submode(Ent);
queue(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(queue, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
queue(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(queue, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
queue(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

scheduler(set, Args, Ent, ConnArgs) ->
    rpc_set(scheduler, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
scheduler(get, Args, Ent, ConnArgs) ->
    rpc_get(scheduler, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
scheduler(show, Args, Ent, ConnArgs) ->
    rpc_show(scheduler, Args, Ent, ConnArgs);
scheduler(list, _, Ent, ConnArgs) ->
    rpc_list(scheduler, "%24N %10S %0C", ConnArgs),
    get_entity_submode(Ent);
scheduler(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(scheduler, Name, Args, ConnArgs),
    get_entity_submode(Ent);
scheduler(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(scheduler, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
scheduler(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(scheduler, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
scheduler(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

image(set, Args, Ent, ConnArgs) ->
    rpc_set(image, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
image(get, Args, Ent, ConnArgs) ->
    rpc_get(image, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
image(show, Args, Ent, ConnArgs) ->
    rpc_show(image, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
image(list, ["system" | _], Ent, _ConnArgs) ->
    Format = "%25N %0I",
    case wm_rpc:call(wm_admin, image, {list, system}) of
        List when is_list(List) ->
            [wm_ctl_cli:list(image, X, Format) || X <- List];
        {ok, Answer} ->
            wm_ctl_cli:list(image, Answer, Format);
        Error ->
            fatal_error("unexpected response: " ++ io_lib:format("~p", [Error]))
    end,
    get_entity_submode(Ent);
image(list, _, Ent, ConnArgs) ->
    rpc_list(image, "%25N %30I %0C", ConnArgs),
    get_entity_submode(Ent);
image(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(image, Name, Args, ConnArgs),
    get_entity_submode(Ent);
image(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(image, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
image(register, [ImageID | _], Ent, ConnArgs) ->
    rpc_generic(image, {register, ImageID}, ConnArgs),
    get_entity_submode(Ent);
image(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

remote(set, Args, Ent, ConnArgs) ->
    rpc_set(remote, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
remote(get, Args, Ent, ConnArgs) ->
    rpc_get(remote, Args, Ent, ConnArgs),
    get_entity_submode(Ent);
remote(show, Args, Ent, ConnArgs) ->
    rpc_show(remote, Args, Ent, ConnArgs);
remote(list, _, Ent, ConnArgs) ->
    rpc_list(remote, "%24N %10A %10K %0C", ConnArgs),
    get_entity_submode(Ent);
remote(remove, [Name | Args], Ent, ConnArgs) ->
    generic_remove(remote, Name, Args, ConnArgs),
    get_entity_submode(Ent);
remote(clone, [From | Args], Ent, ConnArgs) when Args =/= [] ->
    generic_clone(remote, {From, hd(Args)}, Args, ConnArgs),
    get_entity_submode(Ent);
remote(create, [Name | Args], Ent, ConnArgs) ->
    generic_create(remote, Name, Args, ConnArgs, no_cert),
    get_entity_submode(Ent);
remote(_, [], Ent, _) ->
    fatal_error("Wrong number of arguments."),
    get_entity_submode(Ent).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rpc_set(_, [], _, _) ->
    io:format("Parameter not specified~n");
rpc_set(_, [_], _, _) ->
    io:format("Value not specified~n");
rpc_set(Tab, [Param, Value], Ent, ConnArgs) ->
    Answer = wm_rpc:call(wm_admin, Tab, {set, Ent, Param, Value}),
    io:format("~p~n", [Answer]).

rpc_get(_, [], _, _) ->
    io:format("Parameter not specified~n");
rpc_get(Tab, [Param | _], Ent, ConnArgs) ->
    Host = maps:get(host, ConnArgs),
    Port = maps:get(port, ConnArgs),
    wm_rpc:call(wm_admin, Tab, {get, Ent, Param}, {localhost, Port}).

rpc_get(Tab, ConnArgs) ->
    wm_rpc:call(wm_admin, Tab, {list}).

rpc_show(Tab, Args, Ent, ConnArgs) ->
    A = case Args of
            [] ->
                case Ent of
                    [] ->
                        fatal_error("object not specified");
                    _ ->
                        [get_entity_submode(Ent)]
                end;
            _ ->
                Args
        end,
    Xs = wm_rpc:call(wm_admin, Tab, {show, hd(A)}),
    wm_ctl_cli:show(Tab, Xs).

rpc_list(Tab, Format, ConnArgs) ->
    case rpc_get(Tab, ConnArgs) of
        List when is_list(List) ->
            [wm_ctl_cli:list(Tab, X, Format) || X <- List];
        {ok, Answer} ->
            wm_ctl_cli:list(Tab, Answer, Format);
        {error, Error} ->
            Str = inet:format_error(Error),
            fatal_error(Str ++ " (check SWM_API_PORT and SWM_API_HOST)")
    end.

rpc_generic(Command, Args, ConnArgs) ->
    Answer = wm_rpc:call(wm_admin, Command, Args),
    print_rpc_answer(Answer).

generic_create(Entity, Name, Args, ConnArgs, NeedCert) ->
    case wm_rpc:call(wm_admin, Entity, {create, Name, Args}) of
        List when is_list(List), List =/= [] ->
            IDs = [ID || {string, ID} <- List],
            case NeedCert of
                with_cert ->
                    [wm_cert:create(Entity, ID, Name) || ID <- IDs];
                no_cert ->
                    ok
            end,
            F = fun(ID) -> io:format("Created ~p: ~p~n", [Entity, ID]) end,
            [F(ID) || ID <- IDs];
        Error ->
            fatal_error(Error)
    end.

generic_clone(Entity, {From, To}, Args, ConnArgs) ->
    case wm_rpc:call(wm_admin, Entity, {clone, From, To, Args}) of
        List when is_list(List), List =/= [] ->
            IDs = [ID || {string, ID} <- List],
            F = fun(ID) -> io:format("Cloned ~p: ~p~n", [Entity, ID]) end,
            [F(X) || X <- IDs];
        Error ->
            fatal_error(Error)
    end.

generic_remove(Entity, Name, Args, ConnArgs) ->
    case wm_rpc:call(wm_admin, Entity, {remove, Name, Args}) of
        List when is_list(List), List =/= [] ->
            IDs = [ID || {string, ID} <- List],
            F = fun(ID) -> io:format("Removed ~p: ~p~n", [Entity, ID]) end,
            [F(X) || X <- IDs];
        Error ->
            fatal_error(Error)
    end.

print_rpc_answer([]) ->
    ok;
print_rpc_answer([X | T]) ->
    print_rpc_answer(X),
    print_rpc_answer(T);
print_rpc_answer({ok, X}) ->
    print_rpc_answer(X);
print_rpc_answer({string, Str}) ->
    io:format("~s~n", [lists:flatten(Str)]);
print_rpc_answer({atom, Atom}) ->
    io:format("~p~n", [Atom]);
print_rpc_answer(Other) ->
    io:format("OTHER: ~p~n", [Other]).

fatal_error(Msg) when is_list(Msg) ->
    io:format("[ERROR] ~s~n", [lists:flatten(Msg)]);
fatal_error(Msg) ->
    io:format("[ERROR] ~p~n", [Msg]).

consult(File) ->
    case file:read_file(File) of
        {ok, B} ->
            S1 = binary_to_list(B),
            FQDN = wm_utils:get_my_fqdn(),
            Spool = os:getenv("SWM_SPOOL"),
            Root = os:getenv("SWM_ROOT"),
            User = os:getenv("SWM_ADMIN_USER"),
            UserId = os:getenv("SWM_ADMIN_ID"),
            S2 = re:replace(S1, "_HOSTNAME_", FQDN, [global, {return, list}]),
            S3 = re:replace(S2, "_SWM_SPOOL_", Spool, [global, {return, list}]),
            S4 = re:replace(S3, "_SWM_ROOT_", Root, [global, {return, list}]),
            S5 = re:replace(S4, "_USER_NAME_", User, [global, {return, list}]),
            S6 = re:replace(S5, "_SWM_USER_ID_", UserId, [global, {return, list}]),
            {ok, Tokens, _} = erl_scan:string(S6),
            {ok, Terms} = erl_parse:parse_term(Tokens),
            Terms;
        {error, {Line, Mod, Term}} ->
            io:format("Parsing error at ~p:~p, term: ~p~n", [Line, Mod, Term]),
            error;
        {error, Error} ->
            fatal_error(Error)
    end.
