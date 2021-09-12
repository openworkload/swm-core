-module(wm_gate).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([create_partition/4, delete_partition/4, partition_exists/4, get_partition/4, list_partitions/3]).
-export([list_images/3, get_image/4]).
-export([list_flavors/3]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").

-record(mstate, {spool = "" :: string, children = #{} :: #{}}).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec create_partition(atom() | pid(), #remote{}, #credential{}, map()) -> {ok, string()}.
create_partition(CallbackModule, Remote, Creds, Options) ->
    {ok, _Ref} = gen_server:call(?MODULE, {create_partition, CallbackModule, Remote, Creds, Options}).

-spec delete_partition(atom() | pid(), #remote{}, #credential{}, string()) -> {ok, string()}.
delete_partition(CallbackModule, Remote, Creds, PartExtId) ->
    {ok, _Ref} = gen_server:call(?MODULE, {delete_partition, CallbackModule, PartExtId, Remote, Creds}).

-spec partition_exists(atom() | pid(), #remote{}, #credential{}, string()) -> {ok, string()}.
partition_exists(CallbackModule, Remote, Creds, PartExtIdOrName) ->
    {ok, _Ref} = gen_server:call(?MODULE, {partition_exists, CallbackModule, PartExtIdOrName, Remote, Creds}).

-spec get_partition(atom() | pid(), #remote{}, #credential{}, string()) -> {ok, string()}.
get_partition(CallbackModule, Remote, Creds, PartExtId) ->
    {ok, _Ref} = gen_server:call(?MODULE, {get_partition, CallbackModule, PartExtId, Remote, Creds}).

-spec list_partitions(atom() | pid(), #remote{}, #credential{}) -> {ok, string()}.
list_partitions(CallbackModule, Remote, Creds) ->
    {ok, _Ref} = gen_server:call(?MODULE, {list_partitions, CallbackModule, Remote, Creds}).

-spec list_images(atom() | pid(), #remote{}, #credential{}) -> {ok, string()}.
list_images(CallbackModule, Remote, Creds) ->
    {ok, _Ref} = gen_server:call(?MODULE, {list_images, CallbackModule, Remote, Creds}).

-spec get_image(atom() | pid(), #remote{}, #credential{}, string()) -> {ok, string()}.
get_image(CallbackModule, Remote, Creds, ImageID) ->
    {ok, _Ref} = gen_server:call(?MODULE, {get_image, CallbackModule, Remote, Creds, ImageID}).

-spec list_flavors(atom() | pid(), #remote{}, #credential{}) -> {ok, string()}.
list_flavors(CallbackModule, Remote, Creds) ->
    {ok, _Ref} = gen_server:call(?MODULE, {list_flavors, CallbackModule, Remote, Creds}).

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
init(Args) ->
    process_flag(trap_exit, true),
    MState = parse_args(Args, #mstate{}),
    {ok, MState}.

handle_call({create_partition, CallbackModule, Remote, Creds, Options}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> do_partition_create(Remote, Creds, Spool, Options) end,
                     partition_spawned,
                     CallbackModule,
                     MState);
handle_call({delete_partition, CallbackModule, PartExtId, Remote, Creds}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> do_partition_delete(Remote, Creds, PartExtId, Spool) end,
                     partition_deleted,
                     CallbackModule,
                     MState);
handle_call({partition_exists, CallbackModule, PartExtIdOrName, Remote, Creds}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() ->
                        case fetch_partition(Remote, Creds, PartExtIdOrName, Spool) of
                            {ok, _} ->
                                {ok, true};
                            _ ->
                                {ok, false}
                        end
                     end,
                     partition_exists,
                     CallbackModule,
                     MState);
handle_call({list_images, CallbackModule, Remote, Creds}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> fetch_images(Remote, Creds, Spool) end, list_images, CallbackModule, MState);
handle_call({get_image, CallbackModule, Remote, Creds, ImageID}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> fetch_image(Remote, Creds, ImageID, Spool) end, get_image, CallbackModule, MState);
handle_call({list_flavors, CallbackModule, Remote, Creds}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> fetch_flavors(Remote, Creds, Spool) end, list_flavors, CallbackModule, MState);
handle_call({list_partitions, CallbackModule, Remote, Creds}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> fetch_partitions(Remote, Creds, Spool) end, list_partitions, CallbackModule, MState);
handle_call({get_partition, CallbackModule, PartExtId, Remote, Creds}, _, MState = #mstate{spool = Spool}) ->
    handle_http_call(fun() -> fetch_partition(Remote, Creds, PartExtId, Spool) end,
                     partition_fetched,
                     CallbackModule,
                     MState);
handle_call(Msg, From, MState) ->
    ?LOG_INFO("Got not handled call message ~p from ~p", [Msg, From]),
    {reply, {error, not_handled}, MState}.

handle_cast(Msg, MState) ->
    ?LOG_INFO("Got not handled cast message ~p", [Msg]),
    {noreply, MState}.

handle_info({'EXIT', From, normal}, MState = #mstate{children = Children}) ->
    {noreply, MState#mstate{children = maps:remove(From, Children)}};
handle_info({'EXIT', From, Reason}, MState = #mstate{children = Children}) ->
    case maps:get(From, Children, undefined) of
        undefined ->
            ?LOG_INFO("Got orphaned EXIT message from ~p", [From, Reason]),
            {noreply, MState};
        {CallbackModule, Ref} ->
            ?LOG_INFO("Received EXIT from ~p, propagate notification to ~p with ref ~p", [From, CallbackModule, Ref]),
            ok = wm_utils:cast(CallbackModule, {Ref, 'EXIT', Reason}),
            {noreply, MState#mstate{children = maps:remove(From, Children)}}
    end;
handle_info(Info, MState) ->
    ?LOG_INFO("Got not handled message ~p", [Info]),
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_OldVsn, MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% Implementation functions
%% ============================================================================

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec get_address(string(), #remote{}) -> string().
get_address(SectionName, Remote) ->
    "/" ++ atom_to_list(wm_entity:get_attr(kind, Remote)) ++ "/" ++ SectionName.

-spec get_auth_headers(#credential{}) -> [tuple()].
get_auth_headers(Creds) ->
    Username = wm_entity:get_attr(username, Creds),
    Password = wm_entity:get_attr(password, Creds),
    [{<<"Accept">>, <<"application/json">>},
     {<<"username">>, list_to_binary(Username)},
     {<<"password">>, list_to_binary(Password)}].

-spec open_connection(#remote{}, string()) -> pid().
open_connection(Remote, Spool) ->
    DefaultCA = filename:join([Spool, "secure/cluster/cert.pem"]),
    DefaultKey = filename:join([Spool, "secure/node/key.pem"]),
    CA = wm_conf:g(cluster_cert, {DefaultCA, string}),
    Key = wm_conf:g(node_key, {DefaultKey, string}),
    Server = wm_entity:get_attr(server, Remote),
    Port = wm_entity:get_attr(port, Remote),
    ConnOpts =
        #{transport => tls,
          protocols => [http],
          tls_opts => [{cacertfile, CA}, {keyfile, Key}]},
    ConnPid =
        case gun:open(Server, Port, ConnOpts) of
            {ok, Pid} ->
                ?LOG_DEBUG("Opened connection to ~p:~p, pid=~p", [Server, Port, Pid]),
                Pid;
            OpenError ->
                Msg = io_lib:format("Connection opening error: ~p", [OpenError]),
                ?LOG_WARN(Msg),
                exit(Msg)
        end,
    case gun:await_up(ConnPid) of
        {ok, Protocol} ->
            ?LOG_DEBUG("Connection is UP, protocol: ~p", [Protocol]),
            ConnPid;
        {error, Error} ->
            ?LOG_WARN(io_lib:format("Awaiting of connection ~p failed: ~p", [ConnPid, Error])),
            exit(Error)
    end.

-spec close_connection(pid()) -> ok.
close_connection(ConnPid) ->
    gun:close(ConnPid).

-spec wait_response_boby(pid(), reference()) -> {ok, term()} | {error, term()}.
wait_response_boby(ConnPid, StreamRef) ->
    case gun:await(ConnPid, StreamRef) of
        {response, nofin, 200, _} ->
            case gun:await_body(ConnPid, StreamRef) of
                {ok, Body} ->
                    ?LOG_DEBUG("Response body: ~p", [Body]),
                    {ok, Body};
                ResponseError ->
                    ?LOG_WARN("Response error: ~p", [ResponseError]),
                    {error, ResponseError}
            end;
        {response, nofin, 404, _} ->
            ?LOG_WARN("Waiting response: not found"),
            {error, not_found};
        AwaitError ->
            ?LOG_WARN("Await error: ~p", [AwaitError]),
            {error, AwaitError}
    end.

-spec handle_http_call(fun(() -> {atom(), string(), any()}), atom(), atom() | pid(), #mstate{}) ->
                          {atom(), {atom(), string()}, #mstate{}}.
handle_http_call(Func, Label, CallbackModule, MState = #mstate{children = Children}) ->
    Ref = wm_utils:uuid(v4),
    Pid = proc_lib:spawn_link(fun() ->
                                 Reply =
                                     case Func() of
                                         {ok, Answer} ->
                                             {Label, Ref, Answer};
                                         {error, Error} ->
                                             {error, Ref, Error}
                                     end,
                                 ok = wm_utils:cast(CallbackModule, Reply)
                              end),
    {reply, {ok, Ref}, MState#mstate{children = Children#{Pid => {CallbackModule, Ref}}}}.

-spec do_partition_create(#remote{}, #credential{}, string(), map()) -> {ok, string(), string()} | {error, string()}.
do_partition_create(Remote, Creds, Spool, Options) ->
    ConnPid = open_connection(Remote, Spool),
    Headers =
        get_auth_headers(Creds)
        ++ [{<<"partname">>, list_to_binary(maps:get(name, Options, ""))},
            {<<"tenantname">>, list_to_binary(maps:get(tenant_name, Options, ""))},
            {<<"imagename">>, list_to_binary(maps:get(image_name, Options, ""))},
            {<<"flavorname">>, list_to_binary(maps:get(flavor_name, Options, ""))},
            {<<"keyname">>, list_to_binary(maps:get(key_name, Options, ""))},
            {<<"count">>, integer_to_binary(maps:get(nodes_count, Options, 1))}],
    StreamRef = gun:post(ConnPid, get_address("partitions", Remote), Headers),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                wm_gate_parsers:parse_partition_created(BinBody);
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.

-spec do_partition_delete(#remote{}, #credential{}, string(), string()) -> {ok, string()} | {error, any()}.
do_partition_delete(Remote, Creds, PartExtId, Spool) ->
    ConnPid = open_connection(Remote, Spool),
    Headers = get_auth_headers(Creds),
    StreamRef = gun:delete(ConnPid, get_address("partitions/" ++ PartExtId, Remote), Headers),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                wm_gate_parsers:parse_partition_deleted(BinBody);
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.

-spec fetch_images(#remote{}, #credential{}, string()) -> {ok, [#image{}]} | {error, any()}.
fetch_images(Remote, Creds, Spool) ->
    ConnPid = open_connection(Remote, Spool),
    StreamRef = gun:get(ConnPid, get_address("images", Remote), get_auth_headers(Creds)),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                RemoteId = wm_entity:get_attr(id, Remote),
                {ok, Images} = wm_gate_parsers:parse_images(BinBody),
                {ok, [wm_entity:set_attr({remote_id, RemoteId}, Image) || Image <- Images]};
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.

-spec fetch_image(#remote{}, #credential{}, string(), string()) -> {ok, [#image{}]} | {error, string()}.
fetch_image(Remote, Creds, ImageID, Spool) ->
    ConnPid = open_connection(Remote, Spool),
    StreamRef = gun:get(ConnPid, get_address("images/" ++ ImageID, Remote), get_auth_headers(Creds)),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                wm_gate_parsers:parse_image(BinBody);
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.

-spec fetch_flavors(#remote{}, #credential{}, string()) -> {ok, [#image{}]} | {error, string()}.
fetch_flavors(Remote, Creds, Spool) ->
    ?LOG_DEBUG("Fetch flavors from ~p", [wm_entity:get_attr(name, Remote)]),
    ConnPid = open_connection(Remote, Spool),
    StreamRef = gun:get(ConnPid, get_address("flavors", Remote), get_auth_headers(Creds)),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                wm_gate_parsers:parse_flavors(BinBody, Remote);
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.

-spec fetch_partitions(#remote{}, #credential{}, string()) -> {ok, [#image{}]} | {error, string()}.
fetch_partitions(Remote, Creds, Spool) ->
    ConnPid = open_connection(Remote, Spool),
    StreamRef = gun:get(ConnPid, get_address("partitions", Remote), get_auth_headers(Creds)),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                wm_gate_parsers:parse_partitions(BinBody);
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.

-spec fetch_partition(#remote{}, #credential{}, string(), string()) -> {ok, [#partition{}]} | {error, string()}.
fetch_partition(Remote, Creds, PartExtIdOrName, Spool) ->
    ConnPid = open_connection(Remote, Spool),
    StreamRef = gun:get(ConnPid, get_address("partitions/" ++ PartExtIdOrName, Remote), get_auth_headers(Creds)),
    Result =
        case wait_response_boby(ConnPid, StreamRef) of
            {ok, BinBody} ->
                wm_gate_parsers:parse_partition(BinBody);
            {error, Error} ->
                {error, Error}
        end,
    close_connection(ConnPid),
    Result.
