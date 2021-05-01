-module(wm_admin).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%TODO Do not call wm_db directly if possible

-record(mstate, {root = "" :: string(), spool = "" :: string()}).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(DEFAULT_CONN_TIMEOUT, 60000).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% ============================================================================
%% Server callbacks
%% ============================================================================

-spec init(term()) -> {ok, term()} | {ok, term(), hibernate | infinity | non_neg_integer()} | {stop, term()} | ignore.
-spec handle_call(term(), term(), term()) ->
                     {reply, term(), term()} |
                     {reply, term(), term(), hibernate | infinity | non_neg_integer()} |
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()} |
                     {stop, term(), term(), term()}.
-spec handle_cast(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec handle_info(term(), term()) ->
                     {noreply, term()} |
                     {noreply, term(), hibernate | infinity | non_neg_integer()} |
                     {stop, term(), term()}.
-spec terminate(term(), term()) -> ok.
-spec code_change(term(), term(), term()) -> {ok, term()}.
handle_call({grid, route, From, To}, _From, MState) ->
    ?LOG_DEBUG("Requested route from ~p to ~p", [From, To]),
    Result = [{atom, R} || R <- get_route(From, To)],
    {reply, Result, MState};
handle_call({grid, tree, static}, _From, MState) ->
    {reply, {map, wm_topology:get_tree(static)}, MState};
handle_call({grid, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(grid, Ent, Attr, Value), MState};
handle_call({grid, sim, start, _}, _From, MState) ->
    ?LOG_DEBUG("Starting simulation module"),
    start_sim_module(MState),
    wm_sim:start_all(),
    {reply, {string, "Simulation has been started"}, MState};
handle_call({grid, sim, stop, _}, _From, MState) ->
    ?LOG_DEBUG("Stopping simulation"),
    wm_sim:stop_all(),
    wm_root_sup:stop_child(wm_sim),
    {reply, {string, "Simulation has been stopped"}, MState};
handle_call({cluster, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(cluster, Ent, Attr, Value), MState};
handle_call({cluster, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(cluster, Ent, Attr), MState};
handle_call({cluster, list}, _From, MState) ->
    {reply, wm_conf:select([cluster], all), MState};
handle_call({cluster, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(cluster, Ent), MState};
handle_call({partition, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(partition, Ent, Attr, Value), MState};
handle_call({partition, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(partition, Ent, Attr), MState};
handle_call({partition, list}, _From, MState) ->
    {reply, wm_conf:select([partition], all), MState};
handle_call({partition, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(partition, Ent), MState};
handle_call({node, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(node, Ent, Attr, Value), MState};
handle_call({node, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(node, Ent, Attr), MState};
handle_call({node, list}, _From, MState) ->
    {reply, wm_conf:select([node], all), MState};
handle_call({node, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(node, Ent), MState};
handle_call({node, startsim, Ent}, _From, MState) ->
    start_sim_module(MState),
    {reply, process_startsim(node, Ent), MState};
handle_call({node, stopsim, Ent}, _From, MState) ->
    start_sim_module(MState),
    {reply, process_stopsim(node, Ent), MState};
handle_call({user, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(user, Ent, Attr, Value), MState};
handle_call({user, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(user, Ent, Attr), MState};
handle_call({user, list}, _From, MState) ->
    {reply, wm_conf:select([user], all), MState};
handle_call({user, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(user, Ent), MState};
handle_call({queue, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(queue, Ent, Attr, Value), MState};
handle_call({queue, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(queue, Ent, Attr), MState};
handle_call({queue, list}, _From, MState) ->
    {reply, wm_conf:select([queue], all), MState};
handle_call({queue, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(queue, Ent), MState};
handle_call({job, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(job, Ent, Attr, Value), MState};
handle_call({job, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(job, Ent, Attr), MState};
handle_call({job, list}, _From, MState) ->
    {reply, wm_conf:select([job], all), MState};
handle_call({job, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(job, Ent), MState};
handle_call({scheduler, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(scheduler, Ent, Attr, Value), MState};
handle_call({scheduler, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(scheduler, Ent, Attr), MState};
handle_call({scheduler, list}, _From, MState) ->
    {reply, wm_conf:select([scheduler], all), MState};
handle_call({scheduler, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(scheduler, Ent), MState};
handle_call({image, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(image, Ent, Attr, Value), MState};
handle_call({image, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(image, Ent, Attr), MState};
handle_call({image, list, system}, _From, MState) ->
    {reply, wm_container:list_images(unregistered), MState};
handle_call({image, list}, _From, MState) ->
    {reply, wm_conf:select([image], all), MState};
handle_call({image, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(image, Ent), MState};
handle_call({image, register, ImageID}, _From, MState) ->
    {reply, wm_container:register_image(ImageID), MState};
handle_call({global, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(global, Ent, Attr, Value), MState};
handle_call({global, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(global, Ent, Attr), MState};
handle_call({global, list}, _From, MState) ->
    {reply, wm_conf:select([global], all), MState};
handle_call({global, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(global, Ent), MState};
handle_call({global, import, Descriptions}, _From, MState) ->
    Records = wm_entity:descriptions_to_recs(Descriptions),
    case wm_db:ensure_running() of
        ok ->
            N = wm_conf:import(Records, 0),
            %TODO reload services after new configuration is imported?
            ?LOG_DEBUG("Total imported records+empty tables: ~p", [N]),
            {reply, N, MState};
        {error, Reason} ->
            ?LOG_ERROR("~p", [Reason]),
            {reply, {error, Reason}, MState}
    end;
handle_call({global, export}, _From, MState) ->
    Tables = wm_entity:get_names(all),
    {reply, wm_conf:select(Tables, all), MState};
handle_call({global, update, Bin}, _From, MState) ->
    case wm_db:ensure_running() of
        ok ->
            {struct, SchemaJson} = wm_json:decode(Bin),
            %TODO Suspend and then resume processes that use DB
            Result = wm_db:upgrade_schema(SchemaJson),
            %TODO reload services after the schema is updated
            {reply, {list, Result}, MState};
        {error, Reason} ->
            ?LOG_ERROR("~p", [Reason]),
            {reply, {error, Reason}, MState}
    end;
handle_call({remote, set, Ent, Attr, Value}, _From, MState) ->
    {reply, process_set_param(remote, Ent, Attr, Value), MState};
handle_call({remote, get, Ent, Attr}, _From, MState) ->
    {reply, process_get_param(remote, Ent, Attr), MState};
handle_call({remote, list}, _From, MState) ->
    {reply, wm_conf:select([remote], all), MState};
handle_call({remote, show, Ent}, _From, MState) ->
    {reply, process_show_by_name(remote, Ent), MState};
handle_call({TabNameBin, create, Name, Args}, _From, MState) ->
    {reply, process_create(TabNameBin, Name, Args), MState};
handle_call({TabNameBin, clone, From, To, Args}, _From, MState) ->
    {reply, process_clone(TabNameBin, From, To, Args), MState};
handle_call({TabNameBin, remove, Name, Args}, _From, MState) ->
    {reply, process_remove(TabNameBin, Name, Args), MState};
handle_call(Msg, From, MState) ->
    ?LOG_DEBUG("Unknown call message from ~p: ~p", [From, Msg]),
    {reply, ok, MState}.

handle_cast(Msg, MState) ->
    ?LOG_DEBUG("Unknown cast message: ~p", [Msg]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

handle_info(_Info, Data) ->
    {noreply, Data}.

code_change(_OldVsn, Data, _Extra) ->
    {ok, Data}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @hidden
init(Args) ->
    ?LOG_INFO("Load administration service"),
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    ?LOG_DEBUG("Module state: ~p", [MState]),
    {ok, MState}.

parse_args([], MState) ->
    MState;
parse_args([{root, Root} | T], MState) ->
    parse_args(T, MState#mstate{root = Root});
parse_args([{spool, Spool} | T], MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

process_set_param(Tab, Ent, AttrStr, ValueRaw) ->
    Attr = list_to_existing_atom(AttrStr),
    Value =
        case wm_entity:get_type(Tab, Attr) of
            atom ->
                list_to_atom(hd(ValueRaw));
            list ->
                ValueRaw; %% TODO handle nest lists and list of records
            integer ->
                list_to_integer(hd(ValueRaw));
            string ->
                lists:flatten(ValueRaw)
        end,
    {atom, wm_conf:update(Tab, {name, Ent}, {Attr, Value})}.

process_show_by_name(Tab, Name) ->
    case wm_conf:select(Tab, {name, Name}) of
        {ok, X} ->
            X;
        {error, not_found} ->
            {atom, not_found}
    end.

process_get_param(Tab, Ent, Attr) ->
    Name = wm_entity:get_attr(name, Ent),
    ?LOG_DEBUG("Get ~p of ~p from table: ~p", [Attr, Name, Tab]),
    case wm_conf:select(Tab, {name, Name}) of
        {ok, X} ->
            case wm_entity:get_attr(Attr, X) of
                P when is_atom(P) ->
                    {atom, [P]};
                P when is_list(P) ->
                    {string, [X]}
            end;
        {error, not_found} ->
            {atom, not_found}
    end.

process_startsim(node, Name) ->
    ?LOG_INFO("Start simulation node ~p", [Name]),
    wm_sim:start_node(Name),
    {string, io_lib:format("Node ~s has been started", [Name])}.

process_stopsim(node, Name) ->
    ?LOG_INFO("Stop simulation node ~p", [Name]),
    wm_sim:stop_node(Name),
    {string, io_lib:format("Node ~s has been stopped", [Name])}.

start_sim_module(MState) ->
    Args = [{sim_type, partition_per_node}, {sim_spool, wm_utils:get_env("SWM_SPOOL")}, {root, MState#mstate.root}],
    ?LOG_DEBUG("Start wm_sim with arguments: ~p", [Args]),
    case wm_root_sup:start_child(wm_sim, [Args], worker) of
        {error, {already_started, _}} ->
            ?LOG_DEBUG("Simulation module has already been started");
        Msg ->
            ?LOG_DEBUG("Simulation module starting result: ~p", [Msg])
    end.

new_defaults(remote, _, Rec0) ->
    Rec0;
new_defaults(queue, _, Rec0) ->
    Rec0;
new_defaults(scheduler, _, Rec0) ->
    Rec0;
new_defaults(user, _, Rec0) ->
    Rec0;
new_defaults(grid, _, Rec0) ->
    Rec0;
new_defaults(cluster, _, Rec0) ->
    Rec0;
new_defaults(partition, _, Rec0) ->
    Rec0;
new_defaults(node, Defaults, Rec0) ->
    Host =
        case maps:get(host, Defaults, not_found) of
            not_found ->
                wm_utils:get_my_hostname();
            DefaultHost ->
                DefaultHost
        end,
    Rec1 = wm_entity:set_attr({host, Host}, Rec0),
    Port =
        case maps:get(api_port, Defaults, not_found) of
            not_found ->
                wm_core:allocate_port();
            DefaultPort ->
                DefaultPort
        end,
    wm_entity:set_attr({api_port, Port}, Rec1).

process_create(user, Name, [ID]) ->
    User1 = wm_entity:set_attr([{id, ID}, {name, Name}], wm_entity:new(user)),
    User2 = new_defaults(user, maps:new(), User1),
    case wm_conf:select(account, {name, Name}) of
        {error, not_found} ->
            ?LOG_DEBUG("Created default account for user ~p", [Name]),
            Account =
                wm_entity:set_attr([{id, wm_utils:uuid(v4)}, {name, Name}, {admins, [ID]}], wm_entity:new(account)),
            wm_conf:update([Account]);
        _ ->
            ?LOG_DEBUG("Default account for user ~p already exists", [Name])
    end,
    ?LOG_DEBUG("Created user ~p", [Name]),
    wm_conf:update([User2]),
    {string, ID};
process_create(Tab, Name, []) ->
    ID = wm_utils:uuid(v4),
    process_create(Tab, Name, [ID]);
process_create(Tab, Name, [ID]) ->
    ?LOG_DEBUG("Create ~p ~p (ID=~p)", [Tab, Name, ID]),
    Rec1 = wm_entity:set_attr([{id, ID}, {name, Name}], wm_entity:new(Tab)),
    Rec2 = new_defaults(Tab, maps:new(), Rec1),
    wm_conf:update([Rec2]),
    ?LOG_DEBUG("Created record: ~p", [Rec2]),
    {string, ID}.

process_clone(Tab, From, To, Args) ->
    ?LOG_DEBUG("Clone ~p ~p -> ~p (args=~p)", [Tab, From, To, Args]),
    Tab = list_to_existing_atom(binary_to_list(Tab)),
    case wm_conf:select(Tab, {name, From}) of
        {ok, Rec1} ->
            ID = wm_utils:uuid(v4),
            Rec2 = wm_entity:set_attr({id, ID}, Rec1),
            Rec3 = wm_entity:set_attr({name, To}, Rec2),
            Rec4 = new_defaults(Tab, maps:new(), Rec3),
            wm_conf:update([Rec4]),
            {string, ID};
        {error, not_found} ->
            ?LOG_DEBUG("Cloning ~p ~p not found", [Tab, From]),
            {atom, not_found}
    end.

process_remove(Tab, Name, Args) ->
    ?LOG_DEBUG("Remove ~p ~p (args=~p)", [Tab, Name, Args]),
    ID = case wm_conf:select(Tab, {name, Name}) of
             {ok, Rec} ->
                 wm_entity:get_attr(id, Rec);
             {error, not_found} ->
                 ?LOG_DEBUG("Could not find ~p ~p", [Tab, Name]),
                 "UNKNOWN"
         end,
    wm_conf:delete(Tab, ID),
    ?LOG_DEBUG("Removed ~p ID: ~p", [Tab, ID]),
    {string, ID}.

get_route(From, To) ->
    RouteID = wm_utils:uuid(v4),
    wm_pinger:start_route(From, To, RouteID, self()),
    ?LOG_DEBUG("Waiting for route ~p", [RouteID]),
    Ms = wm_conf:g(conn_timeout, {?DEFAULT_CONN_TIMEOUT, integer}),
    receive
        {route, _, _, RouteID, _, done, Route} ->
            Route;
        X ->
            ?LOG_DEBUG("Unexpected message: ~p", [X]),
            []
    after Ms ->
        ?LOG_ERROR("Route timeout (~pms) is detected (ID=~p)", [Ms, RouteID]),
        []
    end.
