-module(wm_gate).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([create_partition/4, delete_partition/4, partition_exists/4, get_partition/4, list_partitions/3]).
-export([list_images/3, get_image/4]).
-export([list_flavors/3]).
-export([get_credentials/1]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").
-include("../../../include/wm_general.hrl").

-record(mstate, {spool = "" :: string(), children = #{} :: #{}, pem_data = <<>> :: binary()}).

-define(CONNECTION_AWAIT_TIMEOUT, timer:seconds(5)).
-define(GATE_RESPONSE_TIMEOUT, 5 * 60 * 1000).
-define(AZURE_CONT_HEADERS, [<<"containerregistryuser">>, <<"containerregistrypass">>]).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec create_partition(atom() | pid(), #remote{}, [{binary(), binary()}], map()) -> {ok, string()}.
create_partition(CallbackModule, Remote, Creds, Options) ->
    {ok, _Ref} = gen_server:call(?MODULE, {create_partition, CallbackModule, Remote, Creds, Options}).

-spec delete_partition(atom() | pid(), #remote{}, [{binary(), binary()}], string()) -> {ok, string()}.
delete_partition(CallbackModule, Remote, Creds, PartExtId) ->
    {ok, _Ref} = gen_server:call(?MODULE, {delete_partition, CallbackModule, PartExtId, Remote, Creds}).

-spec partition_exists(atom() | pid(), #remote{}, [{binary(), binary()}], string()) -> {ok, string()}.
partition_exists(CallbackModule, Remote, Creds, PartExtIdOrName) ->
    {ok, _Ref} = gen_server:call(?MODULE, {partition_exists, CallbackModule, PartExtIdOrName, Remote, Creds}).

-spec get_partition(atom() | pid(), #remote{}, [{binary(), binary()}], string()) -> {ok, string()}.
get_partition(CallbackModule, Remote, Creds, PartExtId) ->
    {ok, _Ref} = gen_server:call(?MODULE, {get_partition, CallbackModule, PartExtId, Remote, Creds}).

-spec list_partitions(atom() | pid(), #remote{}, [{binary(), binary()}]) -> {ok, string()}.
list_partitions(CallbackModule, Remote, Creds) ->
    {ok, _Ref} = gen_server:call(?MODULE, {list_partitions, CallbackModule, Remote, Creds}).

-spec list_images(atom() | pid(), #remote{}, [{binary(), binary()}]) -> {ok, string()}.
list_images(CallbackModule, Remote, Creds) ->
    {ok, _Ref} = gen_server:call(?MODULE, {list_images, CallbackModule, Remote, Creds}).

-spec get_image(atom() | pid(), #remote{}, [{binary(), binary()}], string()) -> {ok, string()}.
get_image(CallbackModule, Remote, Creds, ImageID) ->
    {ok, _Ref} = gen_server:call(?MODULE, {get_image, CallbackModule, Remote, Creds, ImageID}).

-spec list_flavors(atom() | pid(), #remote{}, [{binary(), binary()}]) -> {ok, string()}.
list_flavors(CallbackModule, Remote, Creds) ->
    {ok, _Ref} = gen_server:call(?MODULE, {list_flavors, CallbackModule, Remote, Creds}).

-spec get_credentials(#remote{}) -> {ok, map()} | {error, string()}.
get_credentials(Remote) ->
    gen_server:call(?MODULE, {get_credentials, Remote}).

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
    MState1 = parse_args(Args, #mstate{}),
    MState2 = MState1#mstate{pem_data = read_pem_data(MState1#mstate.spool)},
    {ok, MState2}.

handle_call({get_credentials, Remote}, _, MState = #mstate{}) ->
    ?LOG_DEBUG("Get credentials for remote site: ~p", [wm_entity:get(name, Remote)]),
    {reply, read_credentials_from_file(Remote), MState};
handle_call({create_partition, CallbackModule, Remote, Creds, Options}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> do_partition_create(Remote, Creds, Options, MState) end,
                     partition_spawned,
                     CallbackModule,
                     MState);
handle_call({delete_partition, CallbackModule, PartExtId, Remote, Creds}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> do_partition_delete(Remote, Creds, PartExtId, MState) end,
                     partition_deleted,
                     CallbackModule,
                     MState);
handle_call({partition_exists, CallbackModule, PartExtIdOrName, Remote, Creds}, _, MState = #mstate{}) ->
    handle_http_call(fun() ->
                        case fetch_partition(Remote, Creds, PartExtIdOrName, MState) of
                            {ok, _} ->
                                {ok, true};
                            _ ->
                                {ok, false}
                        end
                     end,
                     partition_exists,
                     CallbackModule,
                     MState);
handle_call({list_images, CallbackModule, Remote, Creds}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> fetch_images(Remote, Creds, MState) end, list_images, CallbackModule, MState);
handle_call({get_image, CallbackModule, Remote, Creds, ImageID}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> fetch_image(Remote, Creds, ImageID, MState) end, get_image, CallbackModule, MState);
handle_call({list_flavors, CallbackModule, Remote, Creds}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> fetch_flavors(Remote, Creds, MState) end, list_flavors, CallbackModule, MState);
handle_call({list_partitions, CallbackModule, Remote, Creds}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> fetch_partitions(Remote, Creds, MState) end, list_partitions, CallbackModule, MState);
handle_call({get_partition, CallbackModule, PartExtId, Remote, Creds}, _, MState = #mstate{}) ->
    handle_http_call(fun() -> fetch_partition(Remote, Creds, PartExtId, MState) end,
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

-spec parse_args(list(), #mstate{}) -> #mstate{}.
parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{spool, Spool} | T], #mstate{} = MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

-spec get_address(string(), #remote{}) -> string().
get_address(SectionName, Remote) ->
    Path = "/" ++ atom_to_list(wm_entity:get(kind, Remote)) ++ "/" ++ SectionName,
    ?LOG_DEBUG("HTTP RPC path: ~p", [Path]),
    Path.

-spec generate_headers([{binary(), binary()}], [binary()], [{binary(), binary()}]) -> [{binary(), binary()}].
generate_headers(Creds, Filter, ExtraHeaders) ->
    FilteredCreds =
        lists:reverse(
            lists:filter(fun({Key, _}) -> not lists:member(Key, Filter) end, Creds)),
    MergedCreds =
        lists:foldl(fun({Key, Value}, Acc) ->
                       case lists:keymember(Key, 1, Acc) of
                           true ->
                               Acc;
                           false ->
                               [{Key, Value} | Acc]
                       end
                    end,
                    FilteredCreds,
                    ExtraHeaders),
    [{<<"Accept">>, <<"application/json">>} | lists:reverse(MergedCreds)].

-spec get_auth_body(binary()) -> [{binary(), binary()}].
get_auth_body(PemData) ->
    list_to_binary([<<"{\"pem_data\": \"">>, PemData, <<"\"}">>]).

-spec open_connection(#remote{}, string()) -> {ok, pid()} | {error | term()}.
open_connection(Remote, Spool) ->
    {CaFile, KeyFile, CertFile} = wm_utils:get_node_cert_paths(Spool),
    ServerFqdn = wm_entity:get(server, Remote),
    Server = hd(string:split(ServerFqdn, ".")),
    Port = wm_entity:get(port, Remote),
    ConnOpts =
        #{transport => tls,
          protocols => [http],
          tls_handshake_timeout => 5000,
          tls_opts =>
              [{versions, ['tlsv1.3', 'tlsv1.2']},
               {verify, verify_peer},
               {fail_if_no_peer_cert, true},
               {partial_chain, wm_utils:get_cert_partial_chain_fun(CaFile)},
               {cacertfile, CaFile},
               {certfile, CertFile},
               {keyfile, KeyFile}]},
    ConnPid =
        case gun:open(Server, Port, ConnOpts) of
            {ok, Pid} ->
                ?LOG_DEBUG("Opened connection to ~s:~p, pid=~p", [Server, Port, Pid]),
                Pid;
            OpenError ->
                Msg = io_lib:format("Connection opening error: ~p, server=~p, port=~p", [OpenError, Server, Port]),
                ?LOG_WARN(Msg),
                exit(Msg)
        end,
    case gun:await_up(ConnPid, ?CONNECTION_AWAIT_TIMEOUT) of
        {ok, Protocol} ->
            ?LOG_DEBUG("Connection is UP, protocol: ~p", [Protocol]),
            {ok, ConnPid};
        {error, Error} ->
            ?LOG_WARN(io_lib:format("Awaiting of connection ~p failed: ~p", [ConnPid, Error])),
            {error, Error}
    end.

-spec close_connection(pid()) -> ok.
close_connection(ConnPid) ->
    gun:close(ConnPid).

-spec wait_response_boby(pid(), reference()) -> {ok, term()} | {error, term()}.
wait_response_boby(ConnPid, StreamRef) ->
    case gun:await(ConnPid, StreamRef, ?GATE_RESPONSE_TIMEOUT) of
        {response, nofin, 200, Headers} ->
            case gun:await_body(ConnPid, StreamRef) of
                {ok, Body} ->
                    ?LOG_DEBUG("Gate response (200) body: ~10000p, headers: ~10000p", [Body, Headers]),
                    {ok, Body};
                ResponseError ->
                    ?LOG_WARN("Gate response (200) error: ~p, headers: ~p", [ResponseError, Headers]),
                    {error, ResponseError}
            end;
        {response, nofin, 307, Headers} ->
            {ok, Body} = gun:await_body(ConnPid, StreamRef),
            ?LOG_WARN("Gate response (307), headers: ~p, body=~p", [Headers, Body]),
            {error, not_found};
        {response, nofin, 422, Headers} ->
            {ok, Body} = gun:await_body(ConnPid, StreamRef),
            ?LOG_WARN("Gate response (422), headers: ~p, body=~p", [Headers, Body]),
            {error, not_found};
        {response, nofin, 404, Headers} ->
            ?LOG_WARN("Gate response (404), headers: ~p", [Headers]),
            {error, not_found};
        {response, nofin, 500, _} ->
            {ok, Body} = gun:await_body(ConnPid, StreamRef),
            ?LOG_WARN("Gate internal error (500): ~p", [Body]),
            {error, "Gate error"};
        {error, Error} ->
            ?LOG_WARN("Gate response error: ~p", [Error]),
            {error, Error}
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

-spec do_partition_create(#remote{}, [{binary(), binary()}], map(), #mstate{}) ->
                             {ok, string(), string()} | {error, string()}.
do_partition_create(Remote, Creds, Options, #mstate{spool = Spool, pem_data = PemData}) ->
    ?LOG_DEBUG("Create partition with options: ~10000p", [Options]),
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            ExtraNodesCount = maps:get(node_count, Options, 1) - 1,  % minus one becuase main node is always created
            ExtraHeaders =
                [{<<"osversion">>, list_to_binary(maps:get(image_name, Options, ""))},
                 {<<"containerimage">>, list_to_binary(maps:get(container_image, Options))},
                 {<<"flavorname">>, list_to_binary(maps:get(flavor_name, Options, ""))},
                 {<<"username">>, list_to_binary(maps:get(user_name, Options, ""))},
                 {<<"count">>, integer_to_binary(ExtraNodesCount)},
                 {<<"jobid">>, list_to_binary(maps:get(job_id, Options))},
                 {<<"partname">>, list_to_binary(maps:get(part_name, Options, ""))},
                 {<<"runtime">>, list_to_binary(get_runtime_parameters_string(Remote))},
                 {<<"location">>, list_to_binary(wm_entity:get(location, Remote))},
                 {<<"ports">>, list_to_binary(maps:get(ports, Options, ""))}],
            Headers = generate_headers(Creds, [], ExtraHeaders), %TODO make remote-dependent exclude list
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Partition creation POST HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef = gun:post(ConnPid, get_address("partitions", Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        wm_gate_parsers:parse_partition_created(BinBody);
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec hide_credentials_from_headers([{binary(), binary()}], [{binary(), binary()}]) -> [{binary(), binary()}].
hide_credentials_from_headers(Headers, Creds) ->
    lists:map(fun({Key, Value}) ->
                 case lists:keyfind(Key, 1, Creds) of
                     false ->
                         {Key, Value};
                     _ ->
                         {Key, <<"*****">>}
                 end
              end,
              Headers).

-spec get_runtime_parameters_string(#remote{}) -> str.
get_runtime_parameters_string(#remote{runtime = RuntimeMap}) ->
    lists:flatten(
        maps:fold(fun (Key, Value, "") ->
                          io_lib:format("~s=~s", [Key, Value]);
                      (Key, Value, Acc) ->
                          io_lib:format("~s,~s=~s", [Acc, Key, Value])
                  end,
                  "",
                  RuntimeMap)).

-spec do_partition_delete(#remote{}, [{binary(), binary()}], string(), #mstate{}) -> {ok, string()} | {error, any()}.
do_partition_delete(Remote, Creds, PartExtId, #mstate{spool = Spool, pem_data = PemData}) ->
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            Headers = generate_headers(Creds, ?AZURE_CONT_HEADERS, []),
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Partition deletion HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef =
                gun:request(ConnPid, <<"DELETE">>, get_address("partitions/" ++ PartExtId, Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        wm_gate_parsers:parse_partition_deleted(BinBody);
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec fetch_images(#remote{}, [{binary(), binary()}], #mstate{}) -> {ok, [#image{}]} | {error, any()}.
fetch_images(Remote, Creds, #mstate{spool = Spool, pem_data = PemData}) ->
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            Extra = [{<<"extra">>, <<"location=eastus;publisher=Canonical;offer=0001-com-ubuntu-server-jammy">>}],
            Headers = generate_headers(Creds, ?AZURE_CONT_HEADERS, Extra),
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Fetch images HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef = gun:request(ConnPid, <<"GET">>, get_address("images", Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        RemoteId = wm_entity:get(id, Remote),
                        {ok, Images} = wm_gate_parsers:parse_images(BinBody),
                        {ok, [wm_entity:set({remote_id, RemoteId}, Image) || Image <- Images]};
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec fetch_image(#remote{}, [{binary(), binary()}], string(), #mstate{}) -> {ok, [#image{}]} | {error, string()}.
fetch_image(Remote, Creds, ImageID, #mstate{spool = Spool, pem_data = PemData}) ->
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            Headers = generate_headers(Creds, ?AZURE_CONT_HEADERS, []),
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Fetch image HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef = gun:request(ConnPid, <<"GET">>, get_address("images/" ++ ImageID, Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        wm_gate_parsers:parse_image(BinBody);
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec fetch_flavors(#remote{}, [{binary(), binary()}], #mstate{}) -> {ok, [#image{}]} | {error, string()}.
fetch_flavors(Remote, Creds, #mstate{spool = Spool, pem_data = PemData}) ->
    ?LOG_DEBUG("Fetch flavors from ~p", [wm_entity:get(name, Remote)]),
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            Extra = [{<<"extra">>, <<"location=eastus">>}],
            Headers = generate_headers(Creds, ?AZURE_CONT_HEADERS, Extra),
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Fetch flavors HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef = gun:request(ConnPid, <<"GET">>, get_address("flavors", Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        wm_gate_parsers:parse_flavors(BinBody, Remote);
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec fetch_partitions(#remote{}, [{binary(), binary()}], #mstate{}) -> {ok, [#image{}]} | {error, string()}.
fetch_partitions(Remote, Creds, #mstate{spool = Spool, pem_data = PemData}) ->
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            Headers = generate_headers(Creds, ?AZURE_CONT_HEADERS, []),
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Fetch partitions HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef = gun:request(ConnPid, <<"GET">>, get_address("partitions", Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        wm_gate_parsers:parse_partitions(BinBody);
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec fetch_partition(#remote{}, [{binary(), binary()}], string(), #mstate{}) ->
                         {ok, [#partition{}]} | {error, string()}.
fetch_partition(Remote, Creds, PartExtIdOrName, #mstate{spool = Spool, pem_data = PemData}) ->
    case open_connection(Remote, Spool) of
        {ok, ConnPid} ->
            Body = get_auth_body(PemData),
            Headers = generate_headers(Creds, ?AZURE_CONT_HEADERS, []),
            HeadersWithoutCredentials = hide_credentials_from_headers(Headers, Creds),
            ?LOG_DEBUG("Fetch partition HTTP headers: ~p", [HeadersWithoutCredentials]),
            StreamRef =
                gun:request(ConnPid, <<"GET">>, get_address("partitions/" ++ PartExtIdOrName, Remote), Headers, Body),
            Result =
                case wait_response_boby(ConnPid, StreamRef) of
                    {ok, BinBody} ->
                        wm_gate_parsers:parse_partition(BinBody);
                    {error, Error} ->
                        {error, Error}
                end,
            close_connection(ConnPid),
            Result;
        {error, Error} ->
            {error, Error}
    end.

-spec read_credentials_from_file(#remote{}) -> {ok, [{binary(), binary()}]} | {error, string()}.
read_credentials_from_file(Remote) ->
    case wm_entity:get(kind, Remote) of
        localhost ->
            {ok, []};
        RemoteKind ->
            FilePath = os:getenv("HOME") ++ "/" ++ ?CREDENTIALS_FILE,
            AbsPath = filename:absname(FilePath),
            case wm_utils:read_file(AbsPath, [binary]) of
                {ok, CredsBin} ->
                    case wm_json:decode(CredsBin) of
                        {struct, CredsStruct} ->
                            RemoteKindBin = atom_to_binary(RemoteKind),
                            case lists:keyfind(RemoteKindBin, 1, CredsStruct) of
                                {RemoteKindBin, {struct, ParamTuples}} ->
                                    {ok, ParamTuples};
                                false ->
                                    ?LOG_ERROR("Cannot find section '~p' in the credentials file", [RemoteKind]),
                                    {error, not_found}
                            end;
                        Error ->
                            ?LOG_ERROR("Cannot parse credentials file ~p: ~p", [AbsPath, Error]),
                            {error, not_found}
                    end;
                {error, Error} ->
                    ?LOG_ERROR("Cannot read file ~p: ~p", [AbsPath, Error]),
                    {error, not_found}
            end
    end.

-spec read_pem_data(string()) -> binary().
read_pem_data(Spool) ->
    {_, KeyFile, CertFile} = wm_utils:get_node_cert_paths(Spool),
    {ok, KeyContent} = file:read_file(KeyFile),
    {ok, CertContent} = file:read_file(CertFile),
    CertLines = binary:split(CertContent, <<"\n">>, [global]),
    {_, CertRest} = lists:splitwith(fun(Line) -> Line =/= <<"-----BEGIN CERTIFICATE-----">> end, CertLines),
    {CertBody, _} = lists:splitwith(fun(Line) -> Line =/= <<"-----END CERTIFICATE-----">> end, CertRest),
    PemData = list_to_binary([KeyContent, CertBody, <<"\n-----END CERTIFICATE-----\n">>]),
    binary:replace(PemData, <<"\n">>, <<"\\n">>, [global]).
