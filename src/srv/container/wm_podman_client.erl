%%% @doc HTTP client for Podman native libpod API over a unix socket (gun).
%%% HTTP/WS client for the Podman libpod API; drives wm_container step orchestration.
-module(wm_podman_client).

-behaviour(gen_server).

-export([start_link/4, get/3, get_status/3, post/5, attach_stdin/4, delete/4, send/3, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("../../lib/wm_log.hrl").

-define(HTTP_TIMEOUT, 20000).
-define(HTTP_KEEP_ALIVE, 20000).
-define(HTTP_RETRIES, 1).
-define(COMMAND_RETRIES, 3).

-record(mstate,
        {owner = undefined :: pid(),
         mref = undefined :: reference(),
         conn_pid = undefined :: pid(),
         stream = undefined :: reference() | undefined,
         %% After gun_upgrade, gun switches the whole connection to gun_raw with
         %% stream_ref=undefined. gun:data/4 must use undefined or gun crashes
         %% (function_clause) and Porter sees EOF on stdin.
         raw_hijack = false :: boolean(),
         data = <<>> :: binary(),
         data_type = -1 :: integer(),
         data_size = 0 :: integer(),
         hdrs = [] :: list(),
         http_status = undefined :: term(),
         reqid = "" :: list(),
         steps = [] :: list(),
         command = undefined :: term(),
         %% Pending gen_server:call From for synchronous GET (never receive in caller).
         reply_to = undefined :: {pid(), term()} | undefined,
         retries = ?COMMAND_RETRIES :: integer(),
         sock = "" :: string()}).

%% ============================================================================
%% API
%% ============================================================================

-spec start_link(string(), pid() | [], term(), string()) -> {ok, pid()}.
start_link(SockPath, Owner, ReqID, Reason) ->
    Args = {Owner, SockPath, ReqID, Reason},
    gen_server:start(?MODULE, Args, []).

-spec get(string(), list(), term()) -> binary().
get(Path, Hdr, HttpProcPid) ->
    case get_status(Path, Hdr, HttpProcPid) of
        {error, _} ->
            <<>>;
        {_, Data} ->
            Data
    end.

%% @doc Synchronous GET. Must not use receive-in-caller: when the caller is
%% wm_container (gen_server), concurrent run calls would steal {'$gen_call',...}
%% from its mailbox and surface as fake "Podman API unreachable" errors.
-spec get_status(string(), list(), term()) -> {term(), binary()} | {error, term()}.
get_status(Path, Hdr, HttpProcPid) ->
    Timeout = wm_conf:g(cont_timeout, {?HTTP_TIMEOUT, integer}),
    try
        gen_server:call(HttpProcPid, {get, Path, Hdr}, Timeout)
    catch
        exit:{timeout, _} ->
            {error, timeout};
        exit:Reason ->
            {error, Reason}
    end.

-spec post(string(), list() | binary(), list(), term(), list()) -> ok.
post(Path, Body, Hdr, HttpProcPid, Steps) ->
    gen_server:call(HttpProcPid, {post_start, Path, Body, Hdr, Steps}).

%% @doc Hijack attach for Porter stdin (libpod has no attach/ws).
-spec attach_stdin(string(), list(), term(), list()) -> ok.
attach_stdin(Path, Hdr, HttpProcPid, Steps) ->
    gen_server:call(HttpProcPid, {attach_stdin_start, Path, Hdr, Steps}).

-spec delete(string(), list(), term(), list()) -> ok.
delete(Path, Hdr, HttpProcPid, Steps) ->
    gen_server:call(HttpProcPid, {delete_start, Path, Hdr, Steps}).

%% @doc Send binary on hijacked attach stream (or no-op notify if stream missing).
-spec send(binary(), term(), list()) -> ok.
send(Data, HttpProcPid, Steps) when is_binary(Data) ->
    gen_server:call(HttpProcPid, {raw_send, Data, Steps}).

-spec stop(pid()) -> atom().
stop(HttpProcPid) ->
    gen_server:call(HttpProcPid, stop).

%% ============================================================================
%% Callbacks
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
init({Owner, SockPath, ReqID, Reason}) ->
    process_flag(trap_exit, true),
    application:ensure_all_started(gun),
    {ConnPid, MRef} = open_conn(SockPath),
    ?LOG_INFO("Podman HTTP client started sock=~s (~s)", [SockPath, Reason]),
    {ok,
     #mstate{owner = Owner,
             conn_pid = ConnPid,
             mref = MRef,
             reqid = ReqID,
             sock = SockPath}}.

handle_call({get, Path, Hdr}, From, #mstate{} = MState) ->
    %% Reply later from notify_requestor when the HTTP response arrives.
    {noreply, do_get(Path, Hdr, MState#mstate{command = {get, Path, Hdr}, reply_to = From})};
handle_call({get_start, Path, Hdr} = Command, _, #mstate{} = MState) ->
    %% Legacy fire-and-forget start; prefer {get, Path, Hdr} for sync callers.
    {reply, ok, do_get(Path, Hdr, MState#mstate{command = Command})};
handle_call({post_start, Path, Body, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_post(Path, Body, Hdr, MState#mstate{steps = Steps, command = Command})};
handle_call({attach_stdin_start, Path, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_post(Path, <<>>, Hdr, MState#mstate{steps = Steps, command = Command})};
handle_call({delete_start, Path, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_delete(Path, Hdr, MState#mstate{steps = Steps, command = Command})};
handle_call({raw_send, Data, Steps},
            _,
            #mstate{conn_pid = ConnPid,
                    stream = Stream,
                    raw_hijack = Raw} =
                MState) ->
    SendRef =
        case Raw of
            true ->
                undefined;
            false ->
                Stream
        end,
    case SendRef =:= undefined andalso not Raw of
        true ->
            ?LOG_ERROR("Podman raw_send with no stream (bytes=~p)", [byte_size(Data)]);
        false ->
            ?LOG_DEBUG("Podman raw_send ~p bytes ref=~p raw_hijack=~p", [byte_size(Data), SendRef, Raw]),
            ok = gun:data(ConnPid, SendRef, nofin, Data)
    end,
    %% Advance scenario once; clear steps so later mux stdout/stderr cannot
    %% re-enter return_sent/create_exec on this attach connection.
    notify_requestor(<<>>, [], ok, MState#mstate{steps = Steps}),
    {reply, ok, MState#mstate{steps = []}};
handle_call(stop, _, #mstate{} = MState) ->
    shutdown(MState),
    {stop, normal, shutdown_ok, MState};
handle_call(_, _, #mstate{} = MState) ->
    {reply, not_implemented, MState}.

handle_cast(_Msg, #mstate{} = MState) ->
    {noreply, MState}.

handle_info({gun_up, ConnPid, http}, #mstate{} = MState) ->
    ?LOG_DEBUG("[Podman HTTP] UP [~p]", [ConnPid]),
    {noreply, MState};
handle_info({gun_response, ConnPid, _, fin, Status, Hdrs}, #mstate{} = MState) ->
    MState2 = notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, Status, MState),
    ok = gun:flush(ConnPid),
    {noreply, MState2#mstate{hdrs = []}};
handle_info({gun_response, _, _, nofin, 404, Hdrs}, #mstate{} = MState) ->
    MState2 = notify_requestor(<<>>, Hdrs, 404, MState),
    shutdown(MState2),
    {stop, normal, MState2};
handle_info({gun_response, _ConnPid, _, nofin, Status, Hdrs}, #mstate{} = MState) when Status =:= 304; Status =:= 101 ->
    %% 101 = hijacked attach ready for stdin / stream.
    MState2 = notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, Status, MState),
    {noreply, MState2#mstate{hdrs = []}};
handle_info({gun_response, _ConnPid, _, nofin, Status, Hdrs}, #mstate{} = MState) ->
    {noreply, MState#mstate{hdrs = MState#mstate.hdrs ++ Hdrs, http_status = Status}};
%% gun 2.x delivers successful HTTP Upgrade (Podman/Docker attach hijack) as gun_upgrade,
%% not gun_response/101. Connection becomes gun_raw with stream_ref=undefined.
handle_info({gun_upgrade, ConnPid, StreamRef, _Protocols, Hdrs}, #mstate{conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("[Podman HTTP] UPGRADE stream=~p -> raw_hijack hdrs=~p", [StreamRef, Hdrs]),
    NewState =
        MState#mstate{hdrs = [],
                      stream = StreamRef,
                      raw_hijack = true},
    MState2 = notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, 101, NewState),
    {noreply, MState2};
handle_info({gun_data, _ConnPid, _, nofin, FrameData}, #mstate{} = MState) ->
    case use_attach_demux(MState) of
        true ->
            {noreply, handle_mux_output(FrameData, MState)};
        false ->
            Old = MState#mstate.data,
            {noreply, MState#mstate{data = <<Old/binary, FrameData/binary>>}}
    end;
handle_info({gun_data, _ConnPid, _, fin, Data}, #mstate{} = MState) ->
    OldData = MState#mstate.data,
    Bin = <<OldData/binary, Data/binary>>,
    case use_attach_demux(MState) of
        true ->
            MState2 = notify_requestor(Bin, [], [], MState),
            {noreply, MState2#mstate{data = Bin}};
        false ->
            Status =
                case MState#mstate.http_status of
                    undefined ->
                        [];
                    S ->
                        S
                end,
            MState2 = notify_requestor(Bin, MState#mstate.hdrs, Status, MState),
            {noreply,
             MState2#mstate{data = Bin,
                            hdrs = [],
                            http_status = undefined}}
    end;
handle_info({gun_error, ConnPid, Msg}, #mstate{} = MState) ->
    ?LOG_DEBUG("[Podman HTTP] ERROR (ignore): ~p [~p]", [Msg, ConnPid]),
    ok = gun:flush(ConnPid),
    MState2 = notify_requestor(<<>>, [], ok, MState),
    {noreply, MState2};
handle_info({gun_down, ConnPid, Proto, Reason, _}, #mstate{} = MState) ->
    ?LOG_DEBUG("Podman connection down: ~p proto=~p [~p]", [Reason, Proto, ConnPid]),
    MState2 = reply_pending_error({connection_down, Reason}, MState),
    shutdown(MState2),
    {stop, normal, MState2};
handle_info({'DOWN', MRef, process, ConnPid, Msg}, #mstate{mref = MRef, conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("Podman gun DOWN: ~p [~p]", [Msg, ConnPid]),
    MState2 = reply_pending_error({gun_down, Msg}, MState),
    shutdown(MState2),
    {stop, shutdown, MState2};
handle_info({gun_inform, _ConnPid, _, Status, Hdrs}, #mstate{} = MState) ->
    MState2 = notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, Status, MState),
    {noreply, MState2};
handle_info(_Other, #mstate{} = MState) ->
    {noreply, MState}.

terminate(Reason, MState) ->
    wm_utils:terminate_msg(?MODULE, Reason),
    shutdown(MState).

code_change(_, MState, _) ->
    {ok, MState}.

%% ============================================================================
%% Implementation
%% ============================================================================

open_conn(SockPath) ->
    Timeout = wm_conf:g(conn_timeout, {?HTTP_TIMEOUT, integer}),
    HttpKeepAlive = wm_conf:g(conn_keep_alive, {?HTTP_KEEP_ALIVE, integer}),
    Retries = wm_conf:g(conn_retries, {?HTTP_RETRIES, integer}),
    Opts =
        #{retry_timeout => Timeout,
          retry => Retries,
          http_opts => #{keepalive => HttpKeepAlive}},
    {ok, ConnPid} = gun:open_unix(SockPath, Opts),
    case gun:await_up(ConnPid, Timeout) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            ?LOG_ERROR("Podman socket await_up failed (~s): ~p", [SockPath, Reason])
    end,
    MRef = monitor(process, ConnPid),
    {ConnPid, MRef}.

shutdown(#mstate{conn_pid = ConnPid, mref = MRef}) ->
    demonitor(MRef),
    try
        gun:flush(ConnPid)
    catch
        _:_ ->
            ok
    end,
    try
        gun:shutdown(ConnPid)
    catch
        _:_ ->
            ok
    end,
    ok.

do_get(Path, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    Stream = gun:get(ConnPid, Path, Hdr),
    MState#mstate{stream = Stream}.

do_post(Path, Body, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    Stream = gun:post(ConnPid, Path, Hdr, Body),
    MState#mstate{stream = Stream}.

do_delete(Path, Hdr, #mstate{conn_pid = ConnPid} = MState) ->
    Stream = gun:delete(ConnPid, Path, Hdr),
    MState#mstate{stream = Stream}.

notify_requestor(Data, Hdrs, Meta, #mstate{reply_to = From} = MState) when From =/= undefined ->
    %% Synchronous GET path: reply to gen_server:call and do not cast the owner
    %% (owner may be wm_container; casting is for async create/attach steps only).
    gen_server:reply(From, {Meta, Data}),
    MState#mstate{reply_to = undefined};
notify_requestor(Data, Hdrs, Meta, MState) ->
    Msg = {MState#mstate.steps, Meta, Data, Hdrs, MState#mstate.reqid},
    gen_server:cast(MState#mstate.owner, Msg),
    MState.

reply_pending_error(Reason, #mstate{reply_to = From} = MState) when From =/= undefined ->
    gen_server:reply(From, {error, Reason}),
    MState#mstate{reply_to = undefined};
reply_pending_error(_Reason, MState) ->
    MState.

use_attach_demux(#mstate{command = {get, _, _}}) ->
    false;
use_attach_demux(#mstate{command = {get_start, _, _}}) ->
    false;
use_attach_demux(#mstate{command = {delete_start, _, _, _}}) ->
    false;
use_attach_demux(#mstate{command = {attach_stdin_start, Path, _, _}}) ->
    %% Hijacked attach may also carry multiplexed stdout/stderr.
    string:str(Path, "/attach") =/= 0;
use_attach_demux(#mstate{command = {post_start, Path, _, _, _}}) ->
    %% Multiplexed stdout/stderr only for attach streams.
    string:str(Path, "/attach") =/= 0;
use_attach_demux(#mstate{}) ->
    false.

handle_full_frame(Type, Frame, MState) ->
    %% Never carry scenario steps on mux frames -- wm_container step clauses
    %% would otherwise match before {stream,N} handlers.
    notify_requestor(Frame, [], {stream, Type}, MState#mstate{steps = []}).

reset_data_state(MState) ->
    MState#mstate{data = <<>>,
                  data_type = -1,
                  data_size = 0}.

handle_mux_output(<<>>, MState) ->
    reset_data_state(MState);
handle_mux_output(<<Type:8/integer, 0, 0, 0, FrameSize:32/integer, Data/binary>>, MState) ->
    case byte_size(Data) of
        FrameSize ->
            handle_full_frame(Type, Data, MState),
            reset_data_state(MState);
        DataSize when DataSize > FrameSize ->
            <<Frame:FrameSize/binary, ExtraData/binary>> = Data,
            handle_full_frame(Type, Frame, MState),
            handle_mux_output(ExtraData, reset_data_state(MState));
        PartSize ->
            Remained = FrameSize - PartSize,
            MState#mstate{data = Data,
                          data_type = Type,
                          data_size = Remained}
    end;
handle_mux_output(Data,
                  MState =
                      #mstate{data_size = ExpectedSize,
                              data = OldData,
                              data_type = Type}) ->
    DataSize = byte_size(Data),
    case DataSize < ExpectedSize of
        true ->
            MState#mstate{data = <<OldData/binary, Data/binary>>, data_size = ExpectedSize - DataSize};
        false ->
            <<Frame:ExpectedSize/binary, ExtraData/binary>> = Data,
            handle_full_frame(Type, Frame, MState),
            handle_mux_output(ExtraData, reset_data_state(MState))
    end.
