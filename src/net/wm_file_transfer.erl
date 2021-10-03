-module(wm_file_transfer).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([upload/6, download/6]).
-export([discontinue/3]).
-export([get_transfers/0, get_transfer_status/1]).
%% Internal API
-export([create_symlink/3]).
-export([open_file/2, close_file/2, delete_file/2]).
-export([create_directory/2, list_directory/2, delete_directory/2]).
-export([get_file_info/2, set_file_info/3]).
-export([file_size/2]).
-export([md5sum/2]).

-include("../lib/wm_log.hrl").

-include_lib("kernel/include/file.hrl").

-record(mstate,
        {via = erl :: erl | ssh,
         ssh_daemon_pid = undefined :: pid(),
         priority_queue = new() :: {pos_integer(), [term()]},
         children = #{} :: #{},
         rev_children = #{} :: #{},
         simulation = false :: atom()}).
-record(file,
        {src_md5_sum = <<>> :: binary(),
         dst_md5_sum = <<>> :: binary(),
         src_fd :: file:io_device(),
         dst_fd :: file:io_device()}).
-record(directory, {src_dir_list = [] :: [file:filename()], dst_dir_list = [] :: [file:filename()]}).

-define(SSH_PORT, 31337).
-define(DATA_TRANSFER_PARALLEL, 2).
-define(BUF_SIZE, 65536).

%% ============================================================================
%% Module API
%% ============================================================================

-spec start_link([term()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc Copy files to remote node.
%%
%% In most cases behave like Linux `cp' utility.
%%
%% The `Source' can be:
%% * "/tmp/file"
%% * "/tmp/directory"
%% * "/tmp/regexp*.{txt,log}"
%% * ["/tmp/file", "/tmp/directory", "/tmp/regexp*.{txt,log}"]
%% * "/tmp/directory" — copy all files with directory itself
%% * "/tmp/directory/" — copy all file without directory itself
%%
%% The `Opts' can be:
%% * #{delete => true} — delete extraneous file when copy directory
%%
%% * #{via => ssh} — copy files through SSH SFTP
%% * #{via => erl} — copy files through Erlang distribution
%%
%% * #{operation => upload}   — copy files from local node to remote
%% * #{operation => download} — copy files from remote node to local
%%
%% @end
-spec copy(atom(), string(), pos_integer(), file:filename() | [file:filename()], file:filename(), #{}) -> {ok, list()}.
copy(CallbackModule, Node, Priority, Source, Destination, Opts) ->
    {ok, _Ref} = gen_server:call(?MODULE, {enqueue, CallbackModule, Node, Priority, Source, Destination, Opts}).

-spec upload(atom(), string(), pos_integer(), file:filename() | [file:filename()], file:filename(), #{}) ->
                {ok, list()}.
upload(CallbackModule, Node, Priority, Source, Destination, Opts) ->
    copy(CallbackModule, Node, Priority, Source, Destination, Opts#{operation => upload}).

-spec download(atom(), string(), pos_integer(), file:filename() | [file:filename()], file:filename(), #{}) ->
                  {ok, list()}.
download(CallbackModule, Node, Priority, Source, Destination, Opts) ->
    copy(CallbackModule, Node, Priority, Source, Destination, Opts#{operation => download}).

-spec discontinue(atom(), list(), boolean()) -> {ok, list()}.
discontinue(CallbackModule, Ref, CleanDest) ->
    {ok, _Ref} = gen_server:call(?MODULE, {discontinue, CallbackModule, Ref, CleanDest}, 20000).

-spec get_transfers() -> {ok, [list()]}.
get_transfers() ->
    {ok, _Refs} = gen_server:call(?MODULE, get_transfers).

-spec get_transfer_status(list()) -> {ok, pos_integer(), pos_integer(), [#{}]} | error.
get_transfer_status(Ref) ->
    gen_server:call(?MODULE, {get_transfer_status, Ref}).

%% ============================================================================
%% Module internal API
%% ============================================================================

%% TODO: Fix spec
-spec create_symlink(pid() | atom() | {atom(), node()}, file:filename(), file:filename()) ->
                        ok | {error, {file:filename(), file:filename()}, nonempty_string()}.
create_symlink(_ServerRef = {ConnectionRef, Pid}, Src, Dst) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:make_symlink(Pid, Src, Dst) of
        ok ->
            ok;
        {error, Reason} ->
            {error, {Src, Dst}, wm_posix_utils:errno(Reason)}
    end;
create_symlink(ServerRef, Src, Dst) ->
    case wm_utils:protected_call(ServerRef, {create_symlink, Src, Dst}) of
        ok ->
            ok;
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, {Src, Dst}, wm_posix_utils:errno(Reason)};
        {error, {Src, Dst}, _PosixReason} = Error ->
            Error
    end.

-spec open_file(pid() | atom() | {atom(), node()}, file:filename()) ->
                   {ok, file:io_device()} | {error, file:filename(), nonempty_string()}.
open_file(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:open(Pid, File, [read, write, binary]) of
        {ok, Fd} ->
            {ok, Fd};
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
open_file(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {open_file, File}) of
        {ok, Fd} ->
            {ok, Fd};
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

-spec close_file(pid() | atom() | {atom(), node()}, file:io_device()) -> ok.
close_file(_ServerRef = {ConnectionRef, Pid}, Fd) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    _ = ssh_sftp:close(Pid, Fd),
    ok;
close_file(ServerRef, Fd) ->
    _ = wm_utils:protected_call(ServerRef, {close_file, Fd}),
    ok.

-spec delete_file(pid() | atom() | {atom(), node()}, file:filename()) ->
                     ok | {error, file:filename(), nonempty_string()}.
delete_file(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:delete(Pid, File) of
        ok ->
            ok;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
delete_file(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {delete_file, File}) of
        ok ->
            ok;
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

-spec create_directory(pid() | atom() | {atom(), node()}, file:filename()) ->
                          ok | exist | {error, file:filename(), nonempty_string()}.
create_directory(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:make_dir(Pid, File) of
        ok ->
            ok;
        {error, file_already_exists} ->
            exist;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
create_directory(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {create_directory, File}) of
        ok ->
            ok;
        exist ->
            exist;
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

-spec list_directory(pid() | atom() | {atom(), node()}, file:filename()) ->
                        {ok, [file:filename()]} | {error, file:filename(), nonempty_string()}.
list_directory(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:list_dir(Pid, File) of
        {ok, Xs} ->
            {ok, Xs};
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
list_directory(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {list_directory, File}) of
        {ok, Xs} ->
            {ok, Xs};
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

-spec delete_directory(pid() | atom() | {atom(), node()}, file:filename()) ->
                          ok | {error, file:filename(), nonempty_string()}.
delete_directory(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case wm_ssh_sftp_ext:command(ConnectionRef, {delete_directory, File}) of
        ok ->
            ok;
        {error, Reason} -> %% ssh_connection subsystem error -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end;
delete_directory(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {delete_directory, File}) of
        ok ->
            ok;
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

%% TODO: Due bug in erlang ssh_sftp we have to preventively cast gid/uid into integer
-spec get_file_info(pid() | atom() | {atom(), node()}, file:filename()) ->
                       {ok, #file_info{}} | {error, file:filename(), nonempty_string()}.
get_file_info(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:read_file_info(Pid, File) of
        {ok, Info} ->
            {ok,
             Info#file_info{gid = wm_utils:to_integer(Info#file_info.gid),
                            uid = wm_utils:to_integer(Info#file_info.uid)}};
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
get_file_info(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {get_file_info, File}) of
        {ok, Info} ->
            {ok,
             Info#file_info{gid = wm_utils:to_integer(Info#file_info.gid),
                            uid = wm_utils:to_integer(Info#file_info.uid)}};
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

%% TODO: Due bug in erlang ssh_sftp we have to preventively cast gid/uid into integer
-spec set_file_info(pid() | atom() | {atom(), node()}, file:filename(), #file_info{}) ->
                       ok | {error, file:filename(), nonempty_string()}.
set_file_info(_ServerRef = {ConnectionRef, Pid}, File, Info) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case ssh_sftp:write_file_info(Pid,
                                  File,
                                  Info#file_info{gid = wm_utils:to_integer(Info#file_info.gid),
                                                 uid = wm_utils:to_integer(Info#file_info.uid)})
    of
        ok ->
            ok;
        {error, Reason} ->
            {error, File, wm_posix_utils:errno(Reason)}
    end;
set_file_info(ServerRef, File, Info) ->
    case wm_utils:protected_call(ServerRef, {set_file_info, File, Info}) of
        ok ->
            ok;
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

-spec file_size(pid() | atom() | {atom(), node()}, file:filename() | file:io_device()) ->
                   {ok, binary()} | {error, file:filename(), nonempty_string()}.
file_size(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case wm_ssh_sftp_ext:command(ConnectionRef, {file_size, File}) of
        {ok, Bytes} ->
            {ok, Bytes};
        {error, Reason} -> %% ssh_connection subsystem error -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, Code, _Msg} = Error when is_integer(Code) ->
            %% TODO: investigate why file size can produce {error, 47, "Operation not permitted (POSIX.1-2001)."}
            Error;
        {error, File, _PosixReason} = Error ->
            Error
    end;
file_size(ServerRef, File) ->
    case wm_utils:protected_call(ServerRef, {file_size, File}) of
        {ok, Bytes} ->
            {ok, Bytes};
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

-spec md5sum(pid() | atom() | {atom(), node()}, file:filename() | file:io_device()) ->
                {ok, binary()} | {error, file:filename(), nonempty_string()}.
md5sum(_ServerRef = {ConnectionRef, Pid}, File) when is_pid(ConnectionRef) andalso is_pid(Pid) ->
    case wm_ssh_sftp_ext:command(ConnectionRef, {md5sum, File}) of
        {ok, Hash} ->
            {ok, Hash};
        {error, Reason} -> %% ssh_connection subsystem error -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end;
md5sum(ServerRef, File) ->
    F = fun Receive() ->
                receive
                    yield ->
                        Receive();
                    {ok, Hash} ->
                        {ok, Hash};
                    {error, Reason} -> %% some error occur
                        {error, File, wm_posix_utils:errno(Reason)};
                    {error, File, _PosixReason} = Error ->
                        Error
                after 30000 ->
                    {error, timeout}
                end
        end,
    case wm_utils:protected_call(ServerRef, {md5sum, File}) of
        yield ->
            F();
        {error, Reason} -> %% gen_server exception -> {error, Reason}
            {error, File, wm_posix_utils:errno(Reason)};
        {error, File, _PosixReason} = Error ->
            Error
    end.

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
    case MState#mstate.simulation of
        true ->
            {ok, MState, hibernate}; %% not used on simulation nodes
        false ->
            case ssh_daemon() of
                {ok, Pid} ->
                    {ok, MState#mstate{ssh_daemon_pid = Pid}};
                {error, Reason} ->
                    {stop, Reason}
            end
    end.

handle_call({create_symlink, Src, Dst}, _, MStats) ->
    Result = wm_file_utils:create_symlink(Src, Dst),
    {reply, Result, MStats};
handle_call({open_file, File}, _, MState) ->
    Result = wm_file_utils:open_file(File),
    {reply, Result, MState};
handle_call({close_file, Fd}, _, MState) ->
    Result = wm_file_utils:close_file(Fd),
    {reply, Result, MState};
handle_call({delete_file, File}, _, MState) ->
    Result = wm_file_utils:delete_file(File),
    {reply, Result, MState};
handle_call({create_directory, File}, _, MState) ->
    Result = wm_file_utils:create_directory(File),
    {reply, Result, MState};
handle_call({list_directory, File}, _, MState) ->
    Result = wm_file_utils:list_directory(File),
    {reply, Result, MState};
handle_call({delete_directory, File}, _, MStats) ->
    Result = wm_file_utils:delete_directory(File),
    {reply, Result, MStats};
handle_call({file_size, File}, _, MState) ->
    Result = wm_file_utils:get_size(File),
    {reply, Result, MState};
handle_call({md5sum, File}, From, MState) ->
    gen_server:reply(From, yield),
    {FromPid, _Ref} = From,
    case wm_file_utils:async_md5sum(File) of
        Pid when is_pid(Pid) ->
            F = fun Receive() ->
                        receive
                            yield ->
                                FromPid ! yield,
                                Receive();
                            {ok, Result} ->
                                FromPid ! {ok, Result}
                        after 30000 ->
                            %% silently timeout
                            %% let final receiver decide to do
                            terminate_without_reply
                        end
                end,
            F();
        Otherwise ->
            FromPid ! Otherwise
    end,
    {noreply, MState};
handle_call({get_file_info, File}, _, MState) ->
    Result = wm_file_utils:get_file_info(File),
    {reply, Result, MState};
%% TODO: Due bug in erlang ssh_sftp we have to preventively cast gid/uid into integer
handle_call({set_file_info, File, Info}, _, MState) ->
    Info = Info#file_info{gid = wm_utils:to_integer(Info#file_info.gid), uid = wm_utils:to_integer(Info#file_info.uid)},
    Result = wm_file_utils:set_file_info(File, Info),
    {reply, Result, MState};
handle_call({enqueue, CallbackModule, Node, Priority, Source, Destination, Opts},
            From,
            MState = #mstate{priority_queue = Q}) ->
    ?LOG_INFO("Requested by ~p transfer: ~p:~p of ~p", [CallbackModule, Node, Destination, Source]),
    Ref = wm_utils:uuid(v4),
    gen_server:reply(From, {ok, Ref}),
    TotalBytes =
        with_connection(Node,
                        Opts,
                        fun(DstServerRef) ->
                           case ?MODULE:file_size(DstServerRef, Source) of
                               {ok, Bytes} ->
                                   Bytes;
                               {error, File, Reason} ->
                                   ?LOG_WARN("Can't obtain file size for ~p with reason ~p, continue with 1 byte size",
                                             [File, Reason]),
                                   1
                           end
                        end),
    %% Prepare function for the deferred execution and put into the priority queue
    Fun = fun() ->
             SrcServerRef = ?MODULE,
             with_connection(Node,
                             Opts,
                             case maps:get(operation, Opts) of
                                 upload ->
                                     %% Copy from local node to remote
                                     fun(DstServerRef) ->
                                        do_copy_files(SrcServerRef,
                                                      DstServerRef,
                                                      parse_files(SrcServerRef, Source),
                                                      Destination,
                                                      Opts#{ref => Ref})
                                     end;
                                 download ->
                                     %% Copy from remote node to local
                                     fun(DstServerRef) ->
                                        do_copy_files(DstServerRef,
                                                      SrcServerRef,
                                                      parse_files(DstServerRef, Source),
                                                      Destination,
                                                      Opts#{ref => Ref})
                                     end
                             end)
          end,
    erlang:send(?MODULE, drain),
    {noreply,
     MState#mstate{priority_queue =
                       in(Priority,
                          {Ref, CallbackModule, _Settings = {Node, Opts, Source, Destination}, Fun, TotalBytes},
                          Q)}};
handle_call({discontinue, CallbackModule, Ref, CleanDest},
            _,
            MState =
                #mstate{priority_queue = Q,
                        children = Children,
                        rev_children = RevChildren}) ->
    DiscontinueRef = wm_utils:uuid(v4),
    Fun = case maps:get(Ref, RevChildren, undefined) of
              undefined ->
                  %% there is no work in progress
                  fun() -> ok end;
              Pid ->
                  {Ref,
                   _CallbackModule,
                   _Settings = {Node, Opts, _Source, _Destination},
                   _TotalBytes,
                   _TransferedBytes,
                   History} =
                      maps:get(Pid, Children),
                  %% there is work in progress, just brutally kill job and maybe cleanup
                  exit(Pid, discontinue),
                  case CleanDest of
                      false ->
                          fun() -> ok end;
                      true ->
                          Files =
                              [File
                               || #{state := State, file := File} <- History,
                                  State == just_copied orelse State == just_created],
                          fun() ->
                             SrcServerRef = ?MODULE,
                             with_connection(Node,
                                             Opts,
                                             case maps:get(operation, Opts) of
                                                 upload ->
                                                     %% Copy from local node to remote; delete from remote
                                                     fun(DstServerRef) -> do_delete_files(DstServerRef, Files) end;
                                                 download ->
                                                     %% Copy from remote node to local; delete from local
                                                     fun(_DstServerRef) -> do_delete_files(SrcServerRef, Files) end
                                             end)
                          end
                  end
          end,
    erlang:send(?MODULE, drain),
    %% mandatory delete job from queue
    NewQ = delete(fun({TargetRef, _CallbackModule1, _Settings1, _Fun, _TotalBytes1}) -> TargetRef =/= Ref end, Q),
    {reply,
     {ok, DiscontinueRef},
     MState#mstate{priority_queue =
                       in(_Priority = 10,
                          {DiscontinueRef, CallbackModule, _Settings2 = undefined, Fun, _TotalBytes2 = 0},
                          NewQ)}};
handle_call({get_transfer_status, Ref}, _, MState = #mstate{children = Children, rev_children = RevChildren}) ->
    case maps:get(Ref, RevChildren, undefined) of
        undefined ->
            {reply, error, MState};
        Pid ->
            {Ref, _CallbackModule, _Settings, TotalBytes, TransferedBytes, History} = maps:get(Pid, Children),
            {reply, {ok, TransferedBytes, TotalBytes - TransferedBytes, lists:reverse(History)}, MState}
    end;
handle_call(get_transfers, _, MState = #mstate{children = Children}) ->
    Refs =
        lists:map(fun({Ref, _CallbackModule, _Settings, _TotalBytes, _TransferedBytes, _History}) -> Ref end,
                  maps:values(Children)),
    {reply, {ok, Refs}, MState};
handle_call(Msg, From, MState) ->
    ?LOG_INFO("Got not handled call message ~p from ~p", [Msg, From]),
    {reply, {error, not_handled}, MState}.

handle_cast({just_processed, Ref, Item}, MState = #mstate{children = Children, rev_children = RevChildren}) ->
    case maps:get(Ref, RevChildren, undefined) of
        undefined ->
            {noreply, MState};
        Pid ->
            {Ref, CallbackModule, Settings, TotalBytes, TransferedBytes, History} = maps:get(Pid, Children),
            {noreply,
             MState#mstate{children =
                               Children#{Pid =>
                                             {Ref,
                                              CallbackModule,
                                              Settings,
                                              TotalBytes,
                                              TransferedBytes,
                                              [Item | History]}}}}
    end;
handle_cast({just_transfered, Ref, JustTransferedBytes},
            MState = #mstate{children = Children, rev_children = RevChildren}) ->
    case maps:get(Ref, RevChildren, undefined) of
        undefined ->
            {noreply, MState};
        Pid ->
            {Ref, CallbackModule, Settings, TotalBytes, TransferedBytes, History} = maps:get(Pid, Children),
            {noreply,
             MState#mstate{children =
                               Children#{Pid =>
                                             {Ref,
                                              CallbackModule,
                                              Settings,
                                              TotalBytes,
                                              TransferedBytes + JustTransferedBytes,
                                              History}}}}
    end;
handle_cast(Msg, MState) ->
    ?LOG_INFO("Got not handled cast message ~p", [Msg]),
    {noreply, MState}.

handle_info(drain,
            MState =
                #mstate{priority_queue = Q,
                        children = Children,
                        rev_children = RevChildren}) ->
    case length(maps:keys(Children)) < wm_conf:g(data_transfer_parallel_works, {?DATA_TRANSFER_PARALLEL, integer}) of
        true ->
            case out(Q) of
                {{Ref, CallbackModule, Settings, Fun, TotalBytes}, {_, _} = NewQ} ->
                    Pid = proc_lib:spawn_link(fun() -> ok = wm_utils:cast(CallbackModule, {Ref, Fun()}) end),
                    {noreply,
                     MState#mstate{priority_queue = NewQ,
                                   children =
                                       Children#{Pid =>
                                                     {Ref,
                                                      CallbackModule,
                                                      Settings,
                                                      TotalBytes,
                                                      _TransferedBytes = 0,
                                                      _History = []}},
                                   rev_children = RevChildren#{Ref => Pid}}};
                NewQ ->
                    {noreply, MState#mstate{priority_queue = NewQ}}
            end;
        false ->
            {noreply, MState}
    end;
handle_info({'EXIT', From, Reason}, MState = #mstate{children = Children, rev_children = RevChildren})
    when Reason == normal orelse Reason == discontinue ->
    erlang:send(?MODULE, drain),
    case maps:get(From, Children, undefined) of
        undefined ->
            {noreply, MState};
        {Ref, _CallbackModule, _Settings, _TotalBytes, _TransferedBytes, _History} ->
            {noreply,
             MState#mstate{children = maps:remove(From, Children), rev_children = maps:remove(Ref, RevChildren)}}
    end;
handle_info({'EXIT', From, Reason}, MState = #mstate{children = Children, rev_children = RevChildren}) ->
    erlang:send(?MODULE, drain),
    case maps:get(From, Children, undefined) of
        undefined ->
            ?LOG_INFO("Got orphaned EXIT message from ~p with "
                      "reason ~p",
                      [From, Reason]),
            {noreply, MState};
        {Ref, CallbackModule, _Settings, _TotalBytes, _TransferedBytes, _History} ->
            ?LOG_INFO("Got EXIT message from ~p with reason "
                      "~p, propagate notification to ~p with "
                      "ref ~p",
                      [From, Reason, CallbackModule, Ref]),
            ok = wm_utils:cast(CallbackModule, {Ref, 'EXIT', Reason}),
            {noreply,
             MState#mstate{children = maps:remove(From, Children), rev_children = maps:remove(Ref, RevChildren)}}
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
parse_args([], MState) ->
    MState;
parse_args([{simulation, true} | T], MState) ->
    parse_args(T, MState#mstate{simulation = true});
parse_args([{_, _} | T], MState) ->
    parse_args(T, MState).

%% TODO: Fix options
%% After work is done, use spool from start_link arg
%% for system_dir
-spec ssh_daemon() -> {ok, pid()} | {error, term()}.
ssh_daemon() ->
    Port = wm_conf:g(data_transfer_ssh_port, {?SSH_PORT, integer}),
    ssh:daemon(Port,
               [{id_string, "SWM/" ++ wm_utils:get_env("SWM_VERSION")},
                {system_dir, filename:join([wm_utils:get_env("SWM_SPOOL"), "secure/host"])},
                {subsystems, [wm_ssh_sftp_ext:subsystem_spec(), ssh_sftpd:subsystem_spec([{cwd, _CWD = "/"}])]},
                {preferred_algorithms, ssh:default_algorithms()},
                {user_passwords, [{"swm", "swm"}]}]).

%% TODO: Fix spec
-spec parse_files(any(), file:filename() | [file:filename()]) -> [file:filename()].
parse_files(ServerRef, []) ->
    parse_files(ServerRef, [], []);
parse_files(ServerRef, <<>>) ->
    parse_files(ServerRef, [], []);
parse_files(ServerRef, [X | _] = File) when is_integer(X) ->
    parse_files(ServerRef, [File], []);
parse_files(ServerRef, [X | _] = Files) when is_list(X) ->
    parse_files(ServerRef, Files, []).

-spec parse_files(any(), file:filename() | [file:filename()], [file:filename()]) -> [file:filename()].
parse_files(_, [], Acc) ->
    Acc;
parse_files(ServerRef, [File | Files], Acc) ->
    case lists:suffix("/", File) of
        true ->
            %% Behave like Linux "cp -R": copy all files in directory w/o directory
            case ?MODULE:list_directory(ServerRef, File) of
                {ok, Xs} ->
                    Ys = lists:map(fun(X) -> filename:join(File, X) end, Xs),
                    parse_files(ServerRef, Files, Ys ++ Acc);
                _Otherwise ->
                    %% Preserve as is, process error later
                    parse_files(ServerRef, Files, [File | Acc])
            end;
        false ->
            case lists:member($*, File) of
                true ->
                    Ys = filelib:wildcard(File),
                    parse_files(ServerRef, Files, Ys ++ Acc);
                false ->
                    %% It must be just a regular file
                    parse_files(ServerRef, Files, [File | Acc])
            end
    end.

%% TODO: fix spec
-spec do_copy_files(any(), any(), [file:filename()], file:filename(), #{}) ->
                       ok | {error, file:filename(), nonempty_string()}.
do_copy_files(_, _, [], _, _) ->
    ok;
do_copy_files(SrcServerRef, DstServerRef, [File | Files], Destination, Opts) ->
    ?LOG_DEBUG("Transfer ~p to ~p [~p -> ~p]", [File, Destination, SrcServerRef, DstServerRef]),
    case ?MODULE:get_file_info(SrcServerRef, File) of
        {ok, Info = #file_info{type = symlink}} ->
            case filelib:is_regular(File) of
                true ->
                    case process_file(SrcServerRef, DstServerRef, File, Destination, Info, Opts) of
                        ok ->
                            do_copy_files(SrcServerRef, DstServerRef, Files, Destination, Opts);
                        Otherwise ->
                            Otherwise
                    end;
                false ->
                    case process_directory(SrcServerRef, DstServerRef, File, Destination, Info, Opts) of
                        {ok, Xs} ->
                            SubDestination = filename:join(Destination, filename:basename(File)),
                            SubFiles = lists:map(fun(X) -> filename:join(File, X) end, Xs),
                            case do_copy_files(SrcServerRef, DstServerRef, SubFiles, SubDestination, Opts) of
                                ok ->
                                    do_copy_files(SrcServerRef, DstServerRef, Files, Destination, Opts);
                                Otherwise ->
                                    Otherwise
                            end;
                        Otherwise ->
                            Otherwise
                    end
            end;
        {ok, Info = #file_info{type = regular}} ->
            case process_file(SrcServerRef, DstServerRef, File, Destination, Info, Opts) of
                ok ->
                    do_copy_files(SrcServerRef, DstServerRef, Files, Destination, Opts);
                Otherwise ->
                    Otherwise
            end;
        {ok, Info = #file_info{type = directory}} ->
            case process_directory(SrcServerRef, DstServerRef, File, Destination, Info, Opts) of
                {ok, Xs} ->
                    SubDestination = filename:join(Destination, filename:basename(File)),
                    SubFiles = lists:map(fun(X) -> filename:join(File, X) end, Xs),
                    case do_copy_files(SrcServerRef, DstServerRef, SubFiles, SubDestination, Opts) of
                        ok ->
                            do_copy_files(SrcServerRef, DstServerRef, Files, Destination, Opts);
                        Otherwise ->
                            Otherwise
                    end;
                Otherwise ->
                    Otherwise
            end;
        Error ->
            Error
    end.

-spec do_delete_files(any(), [file:filename()]) -> ok.
do_delete_files(_, []) ->
    ok;
do_delete_files(ServerRef, [File | Files]) ->
    case ?MODULE:get_file_info(ServerRef, File) of
        {ok, #file_info{type = symlink}} ->
            case filelib:is_regular(File) of
                true ->
                    _ = ?MODULE:delete_file(ServerRef, File),
                    do_delete_files(ServerRef, Files);
                false ->
                    _ = ?MODULE:delete_directory(ServerRef, File),
                    do_delete_files(ServerRef, Files)
            end;
        {ok, #file_info{type = regular}} ->
            _ = ?MODULE:delete_file(ServerRef, File),
            do_delete_files(ServerRef, Files);
        {ok, #file_info{type = directory}} ->
            _ = ?MODULE:delete_directory(ServerRef, File),
            do_delete_files(ServerRef, Files)
    end.

%% ============================================================================
%% Files and directories operations
%% ============================================================================

%% TODO: fix spec
-spec process_file(any(), any(), file:filename(), file:filename(), #file_info{}, #{}) ->
                      ok | {error, file:filename(), nonempty_string()}.
process_file(SrcServerRef, DstServerRef, File, Destination, Info, Opts) ->
    ?LOG_DEBUG("Process transferring of ~p | file info: ~p", [File, Info]),
    SrcFile = File,
    DstFile = filename:join(Destination, filename:basename(File)),
    {St, Result} =
        wm_utils:do(#file{},
                    [fun(St) ->
                        case ?MODULE:md5sum(SrcServerRef, SrcFile) of
                            {ok, Hash} ->
                                St#file{src_md5_sum = Hash};
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:md5sum(DstServerRef, DstFile) of
                            {ok, Hash} ->
                                St#file{dst_md5_sum = Hash};
                            _ ->
                                St
                        end
                     end,
                     fun (St = #file{src_md5_sum = Hash, dst_md5_sum = Hash}) ->
                             Bytes = Info#file_info.size,
                             gen_server:cast(?MODULE, {just_transfered, maps:get(ref, Opts), Bytes}),
                             {break, {St, ok}};
                         (St) ->
                             St
                     end,
                     fun(St) ->
                        case ?MODULE:open_file(SrcServerRef, SrcFile) of
                            {ok, Fd} ->
                                St#file{src_fd = Fd};
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:open_file(DstServerRef, DstFile) of
                            {ok, Fd} ->
                                St#file{dst_fd = Fd};
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:set_file_info(DstServerRef, DstFile, Info) of
                            ok ->
                                St;
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St = #file{src_fd = SrcFd, dst_fd = DstFd}) ->
                        Size = Info#file_info.size,
                        case copy_file(SrcServerRef, DstServerRef, SrcFd, DstFd, Size, Opts) of
                            ok ->
                                St;
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:md5sum(DstServerRef, DstFile) of
                            {ok, Hash} ->
                                St#file{dst_md5_sum = Hash};
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun (St = #file{src_md5_sum = Hash, dst_md5_sum = Hash}) ->
                             {St, ok};
                         (St = #file{src_md5_sum = SrcHash, dst_md5_sum = DstHash}) ->
                             {St,
                              {error,
                               File,
                               io_lib:format("Checksum mismatch, source file ~p (~p) "
                                             "and destination file ~p (~p)",
                                             [SrcFile, SrcHash, DstFile, DstHash])}}
                     end]),
    %% Add opration to history
    gen_server:cast(?MODULE,
                    {just_processed,
                     maps:get(ref, Opts),
                     #{entity => file,
                       state => just_copied,
                       file => DstFile}}),
    wm_utils:do(St,
                [fun (X = #file{src_fd = undefined}) ->
                         X;
                     (X = #file{src_fd = Fd}) ->
                         ok = ?MODULE:close_file(SrcServerRef, Fd),
                         X
                 end,
                 fun (X = #file{dst_fd = undefined}) ->
                         X;
                     (X = #file{dst_fd = Fd}) ->
                         ok = ?MODULE:close_file(DstServerRef, Fd),
                         X
                 end]),
    Result.

%% TODO: fix spec
-spec process_directory(any(), any(), file:filename(), file:filename(), #file_info{}, #{}) ->
                           {ok, [file:filename()]} | {error, file:filename(), nonempty_string()}.
process_directory(SrcServerRef, DstServerRef, File, Destination, Info, Opts) ->
    SrcFile = File,
    DstFile = filename:join(Destination, filename:basename(File)),
    {St, Result} =
        wm_utils:do(#directory{},
                    [fun(St) ->
                        case ?MODULE:create_directory(DstServerRef, DstFile) of
                            ok ->
                                %% Add opration to history
                                gen_server:cast(?MODULE,
                                                {just_processed,
                                                 maps:get(ref, Opts),
                                                 #{entity => dir,
                                                   state => just_created,
                                                   file => DstFile}}),
                                St;
                            exist ->
                                %% Add opration to history
                                gen_server:cast(?MODULE,
                                                {just_processed,
                                                 maps:get(ref, Opts),
                                                 #{entity => dir,
                                                   state => alredy_exist,
                                                   file => DstFile}}),
                                St;
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:set_file_info(SrcServerRef, DstFile, Info) of
                            ok ->
                                St;
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:list_directory(SrcServerRef, SrcFile) of
                            {ok, Files} ->
                                St#directory{src_dir_list = Files};
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case ?MODULE:list_directory(DstServerRef, DstFile) of
                            {ok, Files} ->
                                St#directory{dst_dir_list = Files};
                            Otherwise ->
                                {break, {St, Otherwise}}
                        end
                     end,
                     fun(St) ->
                        case maps:get(delete, Opts, false) of
                            true ->
                                St;
                            false ->
                                {break, {St, ok}}
                        end
                     end,
                     fun(St = #directory{src_dir_list = SrcFiles, dst_dir_list = DstFiles}) ->
                        Diff =
                            sets:to_list(
                                sets:subtract(
                                    sets:from_list(DstFiles), sets:from_list(SrcFiles))),
                        lists:map(fun(Filename) ->
                                     File4Delete = filename:join(DstFile, filename:basename(Filename)),
                                     case ?MODULE:get_file_info(DstServerRef, File4Delete) of
                                         {ok, #file_info{type = symlink}} ->
                                             case ?MODULE:delete_file(DstServerRef, File4Delete) of
                                                 ok ->
                                                     ok;
                                                 Otherwise ->
                                                     Otherwise
                                             end;
                                         {ok, #file_info{type = regular}} ->
                                             case ?MODULE:delete_file(DstServerRef, File4Delete) of
                                                 ok ->
                                                     ok;
                                                 Otherwise ->
                                                     Otherwise
                                             end;
                                         {ok, #file_info{type = directory}} ->
                                             case ?MODULE:delete_directory(DstServerRef, File4Delete) of
                                                 ok ->
                                                     ok;
                                                 Otherwise ->
                                                     Otherwise
                                             end;
                                         {ok, #file_info{type = Type}} ->
                                             {error, File4Delete, io_lib:format("File type ~p not supported", [Type])};
                                         Otherwise ->
                                             Otherwise
                                     end
                                  end,
                                  Diff),
                        {St, ok}
                     end]),
    case Result of
        ok ->
            {ok, St#directory.src_dir_list};
        Otherwise ->
            Otherwise
    end.

-spec copy_file(pid() | atom() | {atom(), node()},
                pid() | atom() | {atom(), node()},
                binary() | file:io_device(),
                binary() | file:io_device(),
                pos_integer(),
                #{}) ->
                   ok | {error, term()}.
copy_file(SrcServerRef, DstServerRef, SrcFd, DstFd, Size, Opts) ->
    DefaultTransport = list_to_atom(wm_conf:g(data_transfer_default_via, {"erl", string})),
    case maps:get(via, Opts, DefaultTransport) of
        ssh ->
            case maps:get(operation, Opts) of
                upload ->
                    %% Copy from local node to remote
                    {_ConnectionRef, Pid} = DstServerRef,
                    upload_file(Pid, SrcFd, DstFd, Size, Opts);
                download ->
                    %% Copy from remote node to local
                    {_ConnectionRef, Pid} = SrcServerRef,
                    download_file(Pid, SrcFd, DstFd, Size, Opts)
            end;
        erl ->
            copy_file(SrcFd, DstFd, Opts)
    end.

-spec upload_file(pid() | atom() | {atom(), node()},
                  binary() | file:io_device(),
                  binary() | file:io_device(),
                  pos_integer(),
                  #{}) ->
                     ok | {error, term()}.
upload_file(ServerRef, SrcFd, DstFd, _Size, Opts) ->
    send_async_write(ServerRef, SrcFd, DstFd, Opts, 0).

-spec send_async_write(pid() | atom() | {atom(), node()},
                       binary() | file:io_device(),
                       binary() | file:io_device(),
                       #{},
                       pos_integer()) ->
                          ok | {error, term()}.
send_async_write(ServerRef, SrcFd, DstFd, Opts, Pos) ->
    case file:read(SrcFd, ?BUF_SIZE) of
        eof ->
            ok;
        {ok, Data} ->
            case ssh_sftp:apwrite(ServerRef, DstFd, Pos, Data) of
                {async, Ref} ->
                    Bytes = byte_size(Data),
                    case receive_async_write(Ref, Opts, Bytes) of
                        ok ->
                            NextPos = Pos + Bytes,
                            send_async_write(ServerRef, SrcFd, DstFd, Opts, NextPos);
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

-spec receive_async_write(term(), #{}, pos_integer()) -> ok | {error, term()}.
receive_async_write(Ref, Opts, Bytes) ->
    receive
        {async_reply, Ref, ok} ->
            gen_server:cast(?MODULE, {just_transfered, maps:get(ref, Opts), Bytes}),
            ok;
        {async_reply, Ref, {error, _} = Error} ->
            Error
    after 5000 ->
        {error, receive_write_timeout}
    end.

-spec download_file(pid() | atom() | {atom(), node()},
                    binary() | file:io_device(),
                    binary() | file:io_device(),
                    pos_integer(),
                    #{}) ->
                       ok | {error, term()}.
download_file(ServerRef, SrcFd, DstFd, Size, Opts) ->
    send_async_read(ServerRef, SrcFd, DstFd, Size, Opts, 0).

-spec send_async_read(pid() | atom() | {atom(), node()},
                      binary() | file:io_device(),
                      binary() | file:io_device(),
                      pos_integer(),
                      #{},
                      pos_integer()) ->
                         ok | {error, term()}.
send_async_read(_, _, _, Size, _, Pos) when Size =< 0 orelse Size < Pos - ?BUF_SIZE ->
    ok;
send_async_read(ServerRef, SrcFd, DstFd, Size, Opts, Pos) ->
    case ssh_sftp:apread(ServerRef, SrcFd, Pos, ?BUF_SIZE) of
        {async, Ref} ->
            case receive_async_read(DstFd, Opts, Ref) of
                eof ->
                    ok;
                ok ->
                    send_async_read(ServerRef, SrcFd, DstFd, Size, Opts, Pos + ?BUF_SIZE);
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

-spec receive_async_read(pid() | atom() | {atom(), node()}, #{}, term()) -> ok | eof | {error, term()}.
receive_async_read(DstFd, Opts, Ref) ->
    receive
        {async_reply, Ref, eof} ->
            eof;
        {async_reply, Ref, {ok, Data}} ->
            case file:write(DstFd, Data) of
                ok ->
                    Bytes = byte_size(Data),
                    ok = gen_server:cast(?MODULE, {just_transfered, maps:get(ref, Opts), Bytes}),
                    ok;
                Error ->
                    Error
            end;
        {async_reply, Ref, {error, _} = Error} ->
            Error
    after 5000 ->
        {error, receive_read_timeout}
    end.

-spec copy_file(file:io_device(), file:io_device(), #{}) -> ok | {error, term()}.
copy_file(SrcFd, DstFd, Opts) ->
    case file:copy(SrcFd, DstFd, ?BUF_SIZE) of
        {ok, 0} ->
            ok;
        {ok, Bytes} ->
            ok = gen_server:cast(?MODULE, {just_transfered, maps:get(ref, Opts), Bytes}),
            copy_file(SrcFd, DstFd, Opts);
        Otherwise ->
            Otherwise
    end.

%% ============================================================================
%% Auxiliary
%% ============================================================================

-spec with_connection(string(), #{}, fun((...) -> term())) -> {error, any(), nonempty_string()} | term().
with_connection(Node, Opts, Fun) ->
    DefaultTransport = list_to_atom(wm_conf:g(data_transfer_default_via, {"erl", string})),
    case maps:get(via, Opts, DefaultTransport) of
        ssh ->
            with_ssh_connection(Node, Fun);
        erl ->
            NodeName = wm_utils:node_to_fullname(Node),
            preserve_connectivity_state(NodeName, Fun)
    end.

-spec with_ssh_connection(string(), fun((...) -> term())) -> {error, any(), nonempty_string()} | term().
with_ssh_connection(Node, Fun) ->
    Port = wm_conf:g(data_transfer_ssh_port, {?SSH_PORT, integer}),
    Opts =
        [{user, "swm"},
         {password, "swm"},
         {silently_accept_hosts, true},
         {preferred_algorithms, ssh:default_algorithms()}],
    case ssh:connect(Node, Port, Opts, _Timeout = 5000) of
        {ok, ConnectionRef} ->
            case ssh_sftp:start_channel(ConnectionRef) of
                {ok, Pid} ->
                    Result = Fun(_ServerRef = {ConnectionRef, Pid}),
                    ok = ssh_sftp:stop_channel(Pid),
                    ok = ssh:close(ConnectionRef),
                    Result;
                {error, Reason} ->
                    ok = ssh:close(ConnectionRef),
                    {error,
                     Node,
                     io_lib:format("Connection via SSH to remote node ~p "
                                   "failed due ~p",
                                   [Node, Reason])}
            end;
        {error, Reason} ->
            {error,
             Node,
             io_lib:format("Connection via SSH to remote node ~p "
                           "failed due ~p",
                           [Node, Reason])}
    end.

-spec preserve_connectivity_state(node(), fun((...) -> term())) -> {error, node(), nonempty_string()} | term().
preserve_connectivity_state(Node, Fun) ->
    IsConnected = lists:member(Node, nodes(connected)),
    case net_kernel:connect(Node) of
        true ->
            Result = Fun(_ServerRef = {?MODULE, Node}),
            IsConnected andalso net_kernel:disconnect(Node),
            Result;
        false ->
            {error, Node, io_lib:format("Connection to remote node ~p failed", [Node])}
    end.

-spec new() -> {pos_integer(), [term()]}.
new() ->
    {0, wm_priority_queue:new()}.

-spec in(pos_integer(), term(), {pos_integer(), [term()]}) -> {pos_integer(), [term()]}.
in(Priority, Value, {Len, Q}) ->
    {Len + 1, wm_priority_queue:insert({-1 * Priority, wm_utils:timestamp(), Value}, Q)}.

-spec out({pos_integer(), [term()]}) -> {term(), {pos_integer(), [term()]}} | {pos_integer(), [term()]}.
out({Len, Q}) ->
    case wm_priority_queue:find_min(Q) of
        empty ->
            new();
        {_, _, Value} ->
            {Value, {Len - 1, wm_priority_queue:delete_min(Q)}}
    end.

-spec delete(fun((term()) -> boolean()), {pos_integer(), [term()]}) -> {pos_integer(), [term()]}.
delete(Fun, {_Len, Q}) ->
    WrapperFun = fun({_, _, X}) -> Fun(X) end,
    {length(Q), wm_priority_queue:filter(WrapperFun, Q)}.
