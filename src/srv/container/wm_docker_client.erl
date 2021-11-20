-module(wm_docker_client).

-behaviour(gen_server).

-export([start_link/5, get/3, post/5, ws_upgrade/4, delete/4, send/3, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_log.hrl").

-define(WS_KEEP_ALIVE, 30000).
-define(HTTP_TIMEOUT, 20000).
-define(HTTP_KEEP_ALIVE, 20000).
-define(HTTP_RETRIES, 1).
-define(COMMAND_RETRIES, 3).

-record(mstate,
        {owner = undefined :: pid(),
         mref = undefined :: reference(),
         conn_pid = undefined :: pid(),
         stream = undefined :: reference(),
         data = <<>> :: binary(),
         data_type = -1 :: integer(),
         data_size = 0 :: integer(),
         hdrs = [] :: list(),
         reqid = "" :: list(),
         steps = [] :: list(),
         command = undefined :: term(),
         ws_ping_timer = undefined :: reference(),
         retries = ?COMMAND_RETRIES :: integer()}).

%% @reference https://ninenines.eu/docs/en/gun/1.0/guide/
%% @reference https://medium.com/@tojeevansingh/tutorial-using-cowboy-gun-client-websocket-6f30ba225acd

%% ============================================================================
%% API
%% ============================================================================

-spec start_link(string(), integer(), pid() | [], term(), string()) -> {ok, pid()}.
start_link(Addr, Port, Owner, ReqID, Reason) ->
    Args = {Owner, Addr, Port, ReqID, Reason},
    gen_server:start_link(?MODULE, Args, []).

-spec get(string(), list(), term()) -> binary().
get(Path, Hdr, HttpProcPid) ->
    wm_utils:protected_call(HttpProcPid, {get_start, Path, Hdr}, []),
    Timeout = wm_conf:g(cont_timeout, {?HTTP_TIMEOUT, integer}),
    receive
        {'$gen_cast', {_, Status, Data, _, _}} ->
            ?LOG_DEBUG("GET: reply: ~p (status=~p)", [Data, Status]),
            Data;
        Other ->
            ?LOG_ERROR("GET: unhandled reply: ~p", [Other])
    after Timeout ->
        ?LOG_DEBUG("HTTP response timeout")
    end.

-spec post(string(), list(), list(), term(), list()) -> binary().
post(Path, Body, Hdr, HttpProcPid, Steps) ->
    Command = {post_start, Path, Body, Hdr, Steps},
    gen_server:call(HttpProcPid, Command).

-spec delete(string(), list(), term(), list()) -> binary().
delete(Path, Hdr, HttpProcPid, Steps) ->
    Command = {delete_start, Path, Hdr, Steps},
    gen_server:call(HttpProcPid, Command).

-spec ws_upgrade(string(), list(), term(), list()) -> binary().
ws_upgrade(Path, Hdr, HttpProcPid, Steps) ->
    Command = {ws_upgrade_start, Path, Hdr, Steps},
    gen_server:call(HttpProcPid, Command).

-spec send(tuple(), term(), list()) -> binary().
send(Frame, HttpProcPid, Steps) ->
    Command = {ws_send, Frame, Steps},
    gen_server:call(HttpProcPid, Command).

-spec stop(pid()) -> atom().
stop(HttpProcPid) ->
    gen_server:call(HttpProcPid, stop).

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
init({Owner, Addr, Port, ReqID, Reason}) ->
    process_flag(trap_exit, true),
    application:ensure_all_started(gun),
    {ConnPid, MRef} = open_conn(Addr, Port),
    MState =
        #mstate{owner = Owner,
                conn_pid = ConnPid,
                mref = MRef,
                reqid = ReqID},
    ?LOG_INFO("HTTP client has been started: ~p:~p (~p)", [Addr, Port, Reason]),
    {ok, MState}.

handle_call({get_start, Path, Hdr} = Command, _, #mstate{} = MState) ->
    MState2 = do_get(Path, Hdr, MState),
    {reply, ok, MState2#mstate{command = Command}};
handle_call({post_start, Path, Body, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    MState2 = do_post(Path, Body, Hdr, MState),
    {reply, ok, MState2#mstate{steps = Steps, command = Command}};
handle_call({delete_start, Path, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    MState2 = do_delete(Path, Hdr, MState),
    {reply, ok, MState2#mstate{steps = Steps, command = Command}};
handle_call({ws_upgrade_start, Path, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    MState2 = do_ws_upgrade(Path, Hdr, MState),
    {reply, ok, MState2#mstate{steps = Steps, command = Command}};
handle_call({ws_send, Frame, Steps} = Command, _, #mstate{stream = Stream, conn_pid = ConnPid} = MState) ->
    ok = gun:ws_send(ConnPid, Stream, Frame),
    {reply, ok, MState#mstate{steps = Steps, command = Command}};
handle_call(stop, _, #mstate{} = MState) ->
    ?LOG_INFO("Docker client is stopped normally"),
    shutdown(MState),
    {stop, normal, shutdown_ok, MState};
handle_call(_, _, #mstate{} = MState) ->
    {reply, not_implemented, MState}.

handle_cast(_Msg, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_ERROR("[HTTP] unknown cast message [~p]", [ConnPid]),
    {noreply, MState}.

handle_info({do_ws_ping, ConnPid}, #mstate{stream = Stream, conn_pid = ConnPid} = MState) ->
    ok = gun:ws_send(ConnPid, Stream, ping),
    {noreply, MState};
handle_info({gun_up, ConnPid, http}, #mstate{} = MState) ->
    ?LOG_DEBUG("[HTTP] UP [~p]", [ConnPid]),
    {noreply, MState};
handle_info({gun_response, ConnPid, _, fin, Status, Hdrs}, #mstate{} = MState) ->
    ?LOG_DEBUG("[HTTP] FIN RESPONSE: ~p [~p]", [Status, ConnPid]),
    NewHdrs = MState#mstate.hdrs ++ Hdrs,
    notify_requestor(<<>>, NewHdrs, Status, MState),
    ok = gun:flush(ConnPid),
    {noreply, MState#mstate{hdrs = []}};
handle_info({gun_response, _, _, nofin, 404, Hdrs}, #mstate{} = MState) ->
    ?LOG_INFO("NOT FOUND (404) response from docker: ~p", [Hdrs]),
    notify_requestor(<<>>, Hdrs, 404, MState),
    shutdown(MState),
    {stop, normal, MState};
handle_info({gun_response, ConnPid, _, nofin, Status, Hdrs}, #mstate{} = MState) when Status =:= 304; Status =:= 101 ->
    ?LOG_DEBUG("[HTTP] NOFIN RESPONSE: ~p [~p]", [Status, ConnPid]),
    NewHdrs = MState#mstate.hdrs ++ Hdrs,
    notify_requestor(<<>>, NewHdrs, 304, MState),
    {noreply, MState#mstate{hdrs = []}};
handle_info({gun_response, ConnPid, _, nofin, Status, Hdrs}, #mstate{} = MState) ->
    ?LOG_DEBUG("[HTTP] NOFIN RESPONSE: ~p ~p [~p]", [Status, Hdrs, ConnPid]),
    NewHdrs = MState#mstate.hdrs ++ Hdrs,
    {noreply, MState#mstate{hdrs = NewHdrs}};
handle_info({gun_data, ConnPid, _, nofin, FrameData}, #mstate{} = MState) ->
    ?LOG_DEBUG("[HTTP] NOFIN DATA: size=~p [~p]", [byte_size(FrameData), ConnPid]),
    {noreply, handle_docker_output(FrameData, MState)};
handle_info({gun_data, ConnPid, _, fin, Data}, #mstate{} = MState) ->
    ?LOG_DEBUG("[HTTP] FIN: frame_size=~p [~p] => notify requestor", [byte_size(Data), ConnPid]),
    OldData = MState#mstate.data,
    Bin = <<OldData/binary, Data/binary>>,
    notify_requestor(Bin, [], [], MState),
    {noreply, MState#mstate{data = Bin}};
handle_info({gun_upgrade, ConnPid, _, _, Headers}, #mstate{} = MState) ->
    ?LOG_DEBUG("[WS] UPGRADE OK [~p]", [ConnPid]),
    Interval = wm_conf:g(ws_ping_interval, {?WS_KEEP_ALIVE, integer}),
    Timer = wm_utils:wake_up_after(Interval, {do_ws_ping, ConnPid}),
    notify_requestor(Headers, [], ok, MState),
    {noreply, MState#mstate{ws_ping_timer = Timer}};
handle_info({gun_upgrade, ConnPid, error, _, Status, _}, #mstate{} = MState) ->
    ?LOG_DEBUG("[WS] UPGRADE ERROR: ~p [~p]", [Status, ConnPid]),
    {noreply, retry_command(MState)};
handle_info({gun_ws, ConnPid, _, {text, Bin}}, #mstate{} = MState) ->
    ?LOG_DEBUG("[WS] TEXT: ~p [~p]", [Bin, ConnPid]),
    % Ignore the text from ws, cause we get the data from regular attach command
    {noreply, MState};
handle_info({gun_ws, ConnPid, _, {close, Status, Data}}, #mstate{} = MState) ->
    ?LOG_DEBUG("[WS] CLOSE: ~p ~p [~p]", [Status, Data, ConnPid]),
    {noreply, MState};
handle_info({gun_error, ConnPid, Msg}, #mstate{} = MState) ->
    ?LOG_DEBUG("[HTTP] ERROR (ignore): ~p [~p]", [Msg, ConnPid]),
    ok = gun:flush(ConnPid),
    notify_requestor(<<>>, [], ok, MState),
    {noreply, MState};
handle_info({gun_down, ConnPid, Proto, Reason, _}, #mstate{} = MState) ->
    ?LOG_DEBUG("CONNECTION DOWN: ~p, proto=~p [~p]", [Reason, Proto, ConnPid]),
    shutdown(MState),
    {stop, normal, MState};
handle_info({'DOWN', MRef, process, ConnPid, Msg = {undef, [{gun_raw, _, _, _} | _]}}, #mstate{mref = MRef} = MState) ->
    ?LOG_DEBUG("DOWN (bug in gun?): ~p [~p]", [Msg, ConnPid]),
    shutdown(MState),
    {stop, shutdown, MState};
handle_info({'DOWN', MRef, process, ConnPid, {shutdown, econnrefused}},
            #mstate{mref = MRef, conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("CAN'T CONNECT TO DOCKER!: [~p]", [ConnPid]),
    shutdown(MState),
    {stop, shutdown, MState};
handle_info({'DOWN', MRef, process, ConnPid, Msg}, #mstate{mref = MRef, conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("DOWN: ~p [~p]", [Msg, ConnPid]),
    shutdown(MState),
    {stop, shutdown, MState};
handle_info({gun_inform, ConnPid, _, Status, Hdrs}, #mstate{} = MState) ->
    ?LOG_DEBUG("GUN INFORM: ~p status=~p [~p]", [Hdrs, Status, ConnPid]),
    NewHdrs = MState#mstate.hdrs ++ Hdrs,
    notify_requestor(<<>>, NewHdrs, Status, MState),
    {noreply, MState};
handle_info({'EXIT', ConnPid, {timeout, Reason}}, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_ERROR("Connection timeout detected: ~p [~p] => RETRY", [Reason, ConnPid]),
    ok = gun:flush(ConnPid),
    {noreply, retry_command(MState)};
handle_info(OtherMsg, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("IGNORE NEW MESSAGE: ~p [~p]", [OtherMsg, ConnPid]),
    {noreply, MState}.

terminate(Reason, MState = #mstate{}) ->
    wm_utils:terminate_msg(?MODULE, Reason),
    shutdown(MState).

code_change(_OldVsn, #mstate{} = MState, _Extra) ->
    {ok, MState}.

%% ============================================================================
%% IMPLEMENTATION
%% ============================================================================

open_conn(Addr, Port) ->
    Timeout = wm_conf:g(conn_timeout, {?HTTP_TIMEOUT, integer}),
    KeepAlive = wm_conf:g(conn_keep_alive, {?HTTP_KEEP_ALIVE, integer}),
    Retries = wm_conf:g(conn_retries, {?HTTP_RETRIES, integer}),
    Opts =
        #{retry_timeout => Timeout,
          retry => Retries,
          http_opts => #{keepalive => KeepAlive}},
    {ok, ConnPid} = gun:open(Addr, Port, Opts),
    ?LOG_DEBUG("Connection to ~p:~p has been opened (~p)", [Addr, Port, ConnPid]),
    MRef = monitor(process, ConnPid),
    {ConnPid, MRef}.

-spec shutdown(#mstate{}) -> ok.
shutdown(#mstate{conn_pid = ConnPid,
                 mref = MRef,
                 ws_ping_timer = Timer}) ->
    ?LOG_DEBUG("Shutdown and demonitor [~p, ~p]", [ConnPid, MRef]),
    catch timer:cancel(Timer),
    demonitor(MRef),
    ok = gun:flush(ConnPid),
    ok = gun:shutdown(ConnPid).

do_get(Path, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("GET: ~p", [Path]),
    Stream = gun:get(ConnPid, Path, Hdr),
    MState#mstate{stream = Stream}.

do_post(Path, Body, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("POST: ~p: ~p ~p [~p]", [Path, Body, Hdr, ConnPid]),
    Stream = gun:post(ConnPid, Path, Hdr, Body),
    MState#mstate{stream = Stream}.

do_delete(Path, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("DELETE: ~p", [Path]),
    Stream = gun:delete(ConnPid, Path, Hdr),
    MState#mstate{stream = Stream}.

do_ws_upgrade(Path, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("WS UPGRADE: ~p (HEADER: ~p)", [Path, Hdr]),
    Res = gun:ws_upgrade(ConnPid, Path, Hdr),
    ?LOG_DEBUG("GUN UPGRADE: ~p~n", [Res]),
    MState.

retry_command(MState = #mstate{command = undefined}) ->
    ?LOG_ERROR("The command will not be retried (undefined)"),
    MState;
retry_command(MState = #mstate{retries = 0}) ->
    ?LOG_INFO("The command will not be retried: no more retries have remained"),
    shutdown(MState),
    exit(normal),
    MState;
retry_command(MState = #mstate{command = Command, retries = RemainedRetries}) ->
    Pid = proc_lib:spawn_link(fun() -> gen_server:call(self(), Command) end),
    ?LOG_INFO("Spawned command retry process [~p]: ~p", [Pid, Command]),
    MState#mstate{command = repeated, retries = RemainedRetries - 1}.

notify_requestor(Data, Hdrs, Meta, MState) ->
    Msg = {MState#mstate.steps, Meta, Data, Hdrs, MState#mstate.reqid},
    gen_server:cast(MState#mstate.owner, Msg).

handle_full_frame(Type, Frame, MState) ->
    notify_requestor(Frame, [], {stream, Type}, MState).

-spec reset_data_state(#mstate{}) -> #mstate{}.
reset_data_state(MState = #mstate{}) ->
    MState#mstate{data = <<>>,
                  data_type = -1,
                  data_size = 0}.

handle_docker_output(<<>>, MState = #mstate{}) ->
    reset_data_state(MState);
handle_docker_output(<<Type:8/integer, 0, 0, 0, FrameSize:32/integer, Data/binary>>, MState) ->
    %% See https://docs.docker.com/engine/api/v1.24 (ATTACH TO A CONTAINER)
    ?LOG_DEBUG("[FRAME] start: type=~p frame_size=~p data_size=~p", [Type, FrameSize, byte_size(Data)]),
    case byte_size(Data) of
        FrameSize ->  % received whole frame
            ?LOG_DEBUG("[FRAME] received: whole frame"),
            handle_full_frame(Type, Data, MState),
            reset_data_state(MState);
        DataSize
            when DataSize
                 > FrameSize ->  % received whole frame plus extra data
            <<Frame:FrameSize/binary, ExtraData/binary>> = Data,
            ?LOG_DEBUG("[FRAME] received: whole frame + extra ~p bytes", [byte_size(ExtraData)]),
            handle_full_frame(Type, Frame, MState),
            handle_docker_output(ExtraData, reset_data_state(MState));
        PartSize ->  % received a part of frame
            ?LOG_DEBUG("[FRAME] recevied: part of frame"),
            OldData = MState#mstate.data,
            Remained = FrameSize - PartSize,
            MState#mstate{data = <<OldData/binary, Data/binary>>,
                          data_type = Type,
                          data_size = Remained}
    end;
handle_docker_output(Data,
                     MState =
                         #mstate{data_size = ExpectedSize,
                                 data = OldData,
                                 data_type = Type}) ->
    DataSize = byte_size(Data),
    case DataSize < ExpectedSize of
        true ->  % received one more frame's part, but we expect another part of the frame in the future
            ?LOG_DEBUG("[FRAME] recevied: one more frame's part, but not the last one"),
            Remained = ExpectedSize - DataSize,
            MState#mstate{data = <<OldData/binary, Data/binary>>, data_size = Remained};
        false ->  % received last part of the frame, plus maybe a part of the next frame
            <<Frame:ExpectedSize/binary, ExtraData/binary>> = Data,
            ?LOG_DEBUG("[FRAME] received: last Handle docker output: ~p + ~p bytes",
                       [byte_size(Frame), byte_size(ExtraData)]),
            handle_full_frame(Type, Frame, MState),
            handle_docker_output(ExtraData, reset_data_state(MState))
    end.
