-module(wm_container).

-behaviour(gen_server).

-export([start_link/1, list_images/1, register_image/1, run/4, communicate/3, clear/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_log.hrl").
-include("../../lib/wm_entity.hrl").

-define(DEFAULT_CONTAINER_TYPE, "docker").

-record(mstate,
        {containers = #{} :: map(),              % ContID => {Owner, Job, HttpPid, LoggerPid}
         execs = #{} :: map(),                   % ContID => ExecPid
         spool = "" :: string(),                 % Spool path
         attachment_pid = undefined :: pid()}).  % PID of the process that attaches to container websocket

%% ============================================================================
%% API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

-spec run(tuple(), string(), map(), pid()) -> term().
run(Job, Cmd, Envs, Owner) ->
    Steps = [create, attach, start, create_exec, start_exec, return_started],
    wm_utils:protected_call(?MODULE, {run, Job, Cmd, Envs, Owner, Steps}, []).

-spec communicate(tuple(), binary(), pid()) -> term().
communicate(Job, Bin, Owner) ->
    Steps = [attach_ws, {send, Bin}, return_sent],
    wm_utils:protected_call(?MODULE, {communicate, Job, Owner, Steps}, []).

-spec list_images(atom()) -> list().
list_images(Type) ->
    wm_utils:protected_call(?MODULE, {list_images, Type}, []).

-spec register_image(string()) -> string().
register_image(ImageID) ->
    wm_utils:protected_call(?MODULE, {register_image, ImageID}, []).

-spec clear(#job{}) -> ok.
clear(Job) ->
    wm_utils:protected_call(?MODULE, {clear_container, Job}, []).

%% ============================================================================
%% CALLBACKS
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
    ?LOG_INFO("Container service has been started"),
    {ok, MState}.

handle_call({clear_container, #job{container = ContID} = Job}, _, #mstate{attachment_pid = AttachmentPid} = MState) ->
    ?LOG_INFO("Clear container ~p", [ContID]),
    Module = get_conteinerizer(),
    ok = Module:delete(Job, self()),
    wm_docker_client:stop(AttachmentPid),
    {reply, ok, clean_containers_map(ContID, MState)};
handle_call({register_image, ImageID}, _, #mstate{} = MState) ->
    Module = get_conteinerizer(),
    case Module:get_unregistered_image(ImageID) of
        not_found ->
            {reply, "Image not found", MState};
        Image ->
            wm_conf:update([Image]),
            Msg = io_lib:format("Image has been registered: ~p", [ImageID]),
            {reply, Msg, MState}
    end;
handle_call({list_images, unregistered}, _, #mstate{} = MState) ->
    Module = get_conteinerizer(),
    Images = Module:get_unregistered_images(),
    {reply, Images, MState};
handle_call({run, Job, Cmd, Envs, Owner, [create | Steps]}, _, #mstate{spool = Spool} = MState) ->
    Module = get_conteinerizer(),
    {ContID, HttpProcPid} = Module:create(Job, Cmd, Envs, self(), Steps),
    NewJob = wm_entity:set_attr({container, ContID}, Job),
    wm_conf:update([NewJob]),
    JobID = wm_entity:get_attr(id, Job),
    {ok, LoggerPid} = wm_container_log:start_link([{spool, Spool}, {job_id, JobID}]),
    Map = maps:put(ContID, {Owner, NewJob, HttpProcPid, LoggerPid}, MState#mstate.containers),
    {reply, {ok, NewJob}, MState#mstate{containers = Map}};
handle_call({communicate, Job, Owner, [attach_ws | Steps]}, _, #mstate{spool = Spool} = MState) ->
    Module = get_conteinerizer(),
    {ContID, HttpProcPid} = Module:attach_ws(Job, self(), Steps),
    JobID = wm_entity:get_attr(id, Job),
    {ok, LoggerPid} = wm_container_log:start_link([{spool, Spool}, {job_id, JobID}]),
    Map = maps:put(ContID, {Owner, Job, HttpProcPid, LoggerPid}, MState#mstate.containers),
    {reply, ok, MState#mstate{containers = Map}}.

%% Next block of handle_cast serves scenarios defined by list of atoms.
%% Each step in the scenario passes tail of the list to the next command
%% that will return the list to that block of handles when finishes.
handle_cast({[attach | Steps], Status, Data, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP ATTACH ~p | ~p | ~p | ~w", [Status, ContID, Data, Steps]),
    Module = get_conteinerizer(),
    {_, Job, _, _} = maps:get(ContID, MState#mstate.containers),
    {ContID, AttachmentPid} = Module:attach(Job, self(), Steps),
    {noreply, MState#mstate{attachment_pid = AttachmentPid}};
handle_cast({[attach_ws | Steps], Status, Data, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP ATTACH WS ~p | ~p | ~p | ~w", [Status, ContID, Data, Steps]),
    Module = get_conteinerizer(),
    {_, Job, _, _} = maps:get(ContID, MState#mstate.containers),
    Module:attach_ws(Job, self(), Steps),
    {noreply, MState};
handle_cast({[start | Steps], Status, Data, _, ContID}, #mstate{} = MState)
    when Status =:= ok; Status =:= 304; Status =:= 101 ->
    ?LOG_DEBUG("STEP START | ~p | ~p | ~w", [ContID, Data, Steps]),
    Module = get_conteinerizer(),
    {_, Job, _, _} = maps:get(ContID, MState#mstate.containers),
    Module:start(Job, Steps),
    {noreply, MState};
handle_cast({[create_exec | Steps], Status, _, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP CREATE EXEC | ~p | ~p | ~p", [Status, ContID, Steps]),
    Module = get_conteinerizer(),
    {_, Job, _, _} = maps:get(ContID, MState#mstate.containers),
    HttpProcPid = Module:create_exec(Job, Steps),
    Map = maps:put(ContID, HttpProcPid, MState#mstate.execs),
    {noreply, MState#mstate{execs = Map}};
handle_cast({[start_exec | Steps], _, Data, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP START EXEC ~p | ~w", [ContID, Steps]),
    Module = get_conteinerizer(),
    {_, Job, _, _} = maps:get(ContID, MState#mstate.containers),
    HttpProcPid = maps:get(ContID, MState#mstate.execs),
    case jsx:decode(Data) of
        [{<<"Id">>, ExecIdBin}] ->
            ExecId = binary_to_list(ExecIdBin),
            Module:start_exec(Job, ExecId, HttpProcPid, Steps);
        Other ->
            ?LOG_ERROR("Exec not created, response: ~p", [Other])
    end,
    {noreply, MState};
handle_cast({[{send, Bin} | Steps], Status, Data, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP SEND | ~p | ~p | ~p | ~w", [Status, ContID, Data, Steps]),
    Module = get_conteinerizer(),
    {_, _, HttpProcPid, _} = maps:get(ContID, MState#mstate.containers),
    Module:send(HttpProcPid, Bin, Steps),
    {noreply, MState};
handle_cast({[return_started | Steps], Status, Data, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP RETURN STARTED ~p | ~p | ~p | ~w", [Status, ContID, Data, Steps]),
    send_event_to_owner(started, ContID, MState),
    {noreply, MState};
handle_cast({[return_sent | Steps], Status, Data, _, ContID}, #mstate{} = MState) ->
    ?LOG_DEBUG("STEP RETURN SENT ~p | ~p | ~p | ~w", [Status, ContID, Data, Steps]),
    send_event_to_owner(sent, ContID, MState),
    {noreply, MState};
handle_cast({_, {stream, 1}, Data, _, ContID}, #mstate{} = MState) ->
    try
        Term = binary_to_term(Data),
        ?LOG_DEBUG("STDOUT from ~p: ~w", [ContID, Term]),
        try
            case element(1, Term) of
                process ->
                    send_event_to_owner({process, Term}, ContID, MState);
                _ ->
                    ?LOG_DEBUG("Unhandled tuple from stdout: ~p", Term)
            end
        catch
            _:_ ->
                ?LOG_DEBUG("Unhandled binary from stdout: ~p", Data)
        end
    catch
        E1:E2 ->
            ?LOG_ERROR("Could not convert binary to term: ~p ~p", [E1, E2])
    end,
    {noreply, MState};
handle_cast({_, {stream, 2}, Data, _, ContID}, #mstate{containers = ContMap} = MState) ->
    % Mainly porter log from container
    try
        BinList = binary:split(Data, <<"\n">>, [global]),
        [?LOG_DEBUG("STDERR from ~p: ~s", [ContID, io_lib:format("~s~n", [binary_to_list(X)])]) || [X] <- BinList],
        {_, _, _, LoggerPid} = maps:get(ContID, ContMap),
        wm_container_log:print(LoggerPid, Data)
    catch
        E1:E2 ->
            ?LOG_ERROR("Could not convert binary to term: ~p ~p", [E1, E2])
    end,
    {noreply, MState};
handle_cast({Steps, Status, Data, Hdrs, ContID}, #mstate{} = MState) ->
    Out = io_lib:format("~s", [Data]),
    ?LOG_DEBUG("RECEIVED DATA: ~p | ~p | ~p | ~w | OUTPUT=~p", [Status, ContID, Hdrs, Steps, Out]),
    {noreply, MState};
handle_cast(_Msg, #mstate{} = MState) ->
    {noreply, MState}.

handle_info(_Info, #mstate{} = MState) ->
    {noreply, MState}.

terminate(Reason, _) ->
    wm_utils:terminate_msg(?MODULE, Reason).

code_change(_, #mstate{} = MState, _) ->
    {ok, MState}.

%% ============================================================================
%% IMPLEMENTATION
%% ============================================================================

parse_args([], #mstate{} = MState) ->
    MState;
parse_args([{spool, Spool} | T], MState) ->
    parse_args(T, MState#mstate{spool = Spool});
parse_args([{_, _} | T], #mstate{} = MState) ->
    parse_args(T, MState).

get_conteinerizer() ->
    S = wm_conf:g(cont_type, {?DEFAULT_CONTAINER_TYPE, string}),
    ModNameStr = "wm_" ++ S,
    ModNameAtom = list_to_atom(ModNameStr),
    {module, Module} = code:ensure_loaded(ModNameAtom),
    Module.

-spec clean_containers_map(string(), #mstate{}) -> #mstate{}.
clean_containers_map(ContID, #mstate{containers = OldMap} = MState) ->
    OldMap = MState#mstate.containers,
    {_, _, _, LoggerPid} = maps:get(ContID, OldMap),
    exit(LoggerPid, shutdown),
    MState#mstate{containers = maps:remove(ContID, OldMap)}.

send_event_to_owner(Event, ContID, #mstate{} = MState) ->
    {Owner, Job, _, _} = maps:get(ContID, MState#mstate.containers),
    JobID = wm_entity:get_attr(id, Job),
    gen_fsm:send_event(Owner, {Event, JobID}).
