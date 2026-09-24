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
         stream = undefined :: reference(),
         data = <<>> :: binary(),
         data_type = -1 :: integer(),
         data_size = 0 :: integer(),
         hdrs = [] :: list(),
         http_status = undefined :: term(),
         reqid = "" :: list(),
         steps = [] :: list(),
         command = undefined :: term(),
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
    {_, Data} = get_status(Path, Hdr, HttpProcPid),
    Data.

-spec get_status(string(), list(), term()) -> {term(), binary()} | {error, term()}.
get_status(Path, Hdr, HttpProcPid) ->
    wm_utils:protected_call(HttpProcPid, {get_start, Path, Hdr}, []),
    Timeout = wm_conf:g(cont_timeout, {?HTTP_TIMEOUT, integer}),
    wait_get_reply(Timeout).

-spec wait_get_reply(non_neg_integer()) -> {term(), binary()} | {error, term()}.
wait_get_reply(Timeout) ->
    receive
        {'$gen_cast', {_, Status, Data, _, _}} ->
            {Status, Data};
        {'EXIT', _Pid, _Reason} ->
            wait_get_reply(Timeout);
        Other ->
            ?LOG_ERROR("Podman GET unhandled reply: ~p", [Other]),
            {error, Other}
    after Timeout ->
        {error, timeout}
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

handle_call({get_start, Path, Hdr} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_get(Path, Hdr, MState#mstate{command = Command})};
handle_call({post_start, Path, Body, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_post(Path, Body, Hdr, MState#mstate{steps = Steps, command = Command})};
handle_call({attach_stdin_start, Path, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_post(Path, <<>>, Hdr, MState#mstate{steps = Steps, command = Command})};
handle_call({delete_start, Path, Hdr, Steps} = Command, _, #mstate{} = MState) ->
    {reply, ok, do_delete(Path, Hdr, MState#mstate{steps = Steps, command = Command})};
handle_call({raw_send, Data, Steps}, _, #mstate{conn_pid = ConnPid, stream = Stream} = MState) ->
    case Stream of
        undefined ->
            ?LOG_ERROR("Podman raw_send with no stream");
        _ ->
            %% Hijacked attach: write Porter EI binary to container stdin.
            ok = gun:data(ConnPid, Stream, nofin, Data)
    end,
    notify_requestor(<<>>, [], ok, MState#mstate{steps = Steps}),
    {reply, ok, MState#mstate{steps = Steps}};
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
    notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, Status, MState),
    ok = gun:flush(ConnPid),
    {noreply, MState#mstate{hdrs = []}};
handle_info({gun_response, _, _, nofin, 404, Hdrs}, #mstate{} = MState) ->
    notify_requestor(<<>>, Hdrs, 404, MState),
    shutdown(MState),
    {stop, normal, MState};
handle_info({gun_response, ConnPid, _, nofin, Status, Hdrs}, #mstate{} = MState) when Status =:= 304; Status =:= 101 ->
    %% 101 = hijacked attach ready for stdin / stream.
    notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, Status, MState),
    {noreply, MState#mstate{hdrs = []}};
handle_info({gun_response, ConnPid, _, nofin, Status, Hdrs}, #mstate{} = MState) ->
    {noreply, MState#mstate{hdrs = MState#mstate.hdrs ++ Hdrs, http_status = Status}};
handle_info({gun_data, ConnPid, _, nofin, FrameData}, #mstate{} = MState) ->
    case use_attach_demux(MState) of
        true ->
            {noreply, handle_mux_output(FrameData, MState)};
        false ->
            Old = MState#mstate.data,
            {noreply, MState#mstate{data = <<Old/binary, FrameData/binary>>}}
    end;
handle_info({gun_data, ConnPid, _, fin, Data}, #mstate{} = MState) ->
    OldData = MState#mstate.data,
    Bin = <<OldData/binary, Data/binary>>,
    case use_attach_demux(MState) of
        true ->
            notify_requestor(Bin, [], [], MState),
            {noreply, MState#mstate{data = Bin}};
        false ->
            Status =
                case MState#mstate.http_status of
                    undefined ->
                        [];
                    S ->
                        S
                end,
            notify_requestor(Bin, MState#mstate.hdrs, Status, MState),
            {noreply,
             MState#mstate{data = Bin,
                           hdrs = [],
                           http_status = undefined}}
    end;
handle_info({gun_error, ConnPid, Msg}, #mstate{} = MState) ->
    ?LOG_DEBUG("[Podman HTTP] ERROR (ignore): ~p [~p]", [Msg, ConnPid]),
    ok = gun:flush(ConnPid),
    notify_requestor(<<>>, [], ok, MState),
    {noreply, MState};
handle_info({gun_down, ConnPid, Proto, Reason, _}, #mstate{} = MState) ->
    ?LOG_DEBUG("Podman connection down: ~p proto=~p [~p]", [Reason, Proto, ConnPid]),
    shutdown(MState),
    {stop, normal, MState};
handle_info({'DOWN', MRef, process, ConnPid, Msg}, #mstate{mref = MRef, conn_pid = ConnPid} = MState) ->
    ?LOG_DEBUG("Podman gun DOWN: ~p [~p]", [Msg, ConnPid]),
    shutdown(MState),
    {stop, shutdown, MState};
handle_info({gun_inform, ConnPid, _, Status, Hdrs}, #mstate{} = MState) ->
    notify_requestor(<<>>, MState#mstate.hdrs ++ Hdrs, Status, MState),
    {noreply, MState};
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
    catch gun:flush(ConnPid),
    catch gun:shutdown(ConnPid),
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

notify_requestor(Data, Hdrs, Meta, MState) ->
    Msg = {MState#mstate.steps, Meta, Data, Hdrs, MState#mstate.reqid},
    gen_server:cast(MState#mstate.owner, Msg).

use_attach_demux(#mstate{command = {get_start, _, _}}) ->
    false;
use_attach_demux(#mstate{command = {delete_start, _, _, _}}) ->
    false;
use_attach_demux(#mstate{command = {attach_stdin_start, _, _, _}}) ->
    false;
use_attach_demux(#mstate{command = {post_start, Path, _, _, _}}) ->
    %% Multiplexed stdout/stderr only for attach streams.
    string:str(Path, "/attach") =/= 0;
use_attach_demux(#mstate{}) ->
    false.

handle_full_frame(Type, Frame, MState) ->
    notify_requestor(Frame, [], {stream, Type}, MState).

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
