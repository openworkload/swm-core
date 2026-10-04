-module(wm_checkpoint).

%% Cancel-only DMTCP/MANA checkpoint helpers.

-export([enabled/1, env/1, display_last/1, checkpoint_before_cancel/1, run_local_checkpoint/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

-define(MANA_BIN_DIR, "/opt/mana/bin").

-spec enabled(#job{}) -> boolean().
enabled(#job{checkpoint = Engine}) when is_list(Engine), Engine =/= "" ->
    true;
enabled(_) ->
    false.

%% @doc Porter env exports for checkpoint-enabled jobs.
-spec env(#job{}) -> [{string(), string()}].
env(#job{} = Job) ->
    case enabled(Job) of
        false ->
            [{"SWM_CKPT", ""}, {"SWM_CKPT_DIR", ""}, {"SWM_CKPT_INTERVAL", "0"}];
        true ->
            Dir = wm_entity:get(checkpoint_dir, Job),
            Interval = wm_entity:get(checkpoint_interval, Job),
            [{"SWM_CKPT", wm_entity:get(checkpoint, Job)},
             {"SWM_CKPT_DIR", Dir},
             {"SWM_CKPT_INTERVAL", integer_to_list(Interval)}]
    end.

%% @doc Console/API display: last time or "disabled".
-spec display_last(#job{}) -> string().
display_last(#job{} = Job) ->
    case enabled(Job) of
        false ->
            "disabled";
        true ->
            case wm_entity:get(last_checkpoint_time, Job) of
                "" ->
                    "";
                Time when is_list(Time) ->
                    Time;
                _ ->
                    ""
            end
    end.

%% @doc Run final checkpoint on the job main node, then return updated job.
%% On failure or timeout, cancel still proceeds (job unchanged except logs).
-spec checkpoint_before_cancel(#job{}) -> #job{}.
checkpoint_before_cancel(#job{} = Job) ->
    case enabled(Job) of
        false ->
            Job;
        true ->
            JobId = wm_entity:get(id, Job),
            ?LOG_INFO("Checkpoint-before-cancel for job ~p (engine=~p dir=~p)",
                      [JobId, wm_entity:get(checkpoint, Job), wm_entity:get(checkpoint_dir, Job)]),
            case request_checkpoint(Job) of
                {ok, Time} when is_list(Time), Time =/= "" ->
                    Job2 = wm_entity:set({last_checkpoint_time, Time}, Job),
                    case wm_conf:update([Job2]) of
                        1 ->
                            Job2;
                        _ ->
                            Job2
                    end;
                {error, Reason} ->
                    ?LOG_WARN("Checkpoint-before-cancel failed for job ~p: ~p", [JobId, Reason]),
                    Job;
                Other ->
                    ?LOG_WARN("Checkpoint-before-cancel unexpected result for job ~p: ~p", [JobId, Other]),
                    Job
            end
    end.

%% @doc Local MANA/DMTCP checkpoint (runs on the job main / compute node).
-spec run_local_checkpoint(#job{}) -> {ok, string()} | {error, term()}.
run_local_checkpoint(#job{} = Job) ->
    case enabled(Job) of
        false ->
            {error, checkpoint_disabled};
        true ->
            Dir = case wm_entity:get(checkpoint_dir, Job) of
                      "" ->
                          "/mnt/blob/ckpt";
                      D when is_list(D) ->
                          D
                  end,
            ok =
                filelib:ensure_dir(
                    filename:join(Dir, "dummy")),
            Cmd = lists:flatten(
                      io_lib:format("export PATH=~s:$PATH; "
                                    "export DMTCP_CHECKPOINT_DIR=~s; "
                                    "mkdir -p ~s; "
                                    "if command -v mana_status >/dev/null 2>&1; then "
                                    "  mana_status --checkpoint; "
                                    "elif command -v dmtcp_command >/dev/null 2>&1; then "
                                    "  dmtcp_command --checkpoint; "
                                    "else "
                                    "  echo 'mana_status/dmtcp_command not found' >&2; exit 127; "
                                    "fi",
                                    [sh_quote(?MANA_BIN_DIR), sh_quote(Dir), sh_quote(Dir)])),
            ?LOG_INFO("Running local checkpoint: ~s", [Cmd]),
            case run_shell(Cmd) of
                {0, _} ->
                    {ok, wm_utils:now_iso8601(without_ms)};
                {Code, Out} ->
                    ?LOG_WARN("Local checkpoint exit ~p: ~s", [Code, Out]),
                    {error, {exit, Code, Out}}
            end
    end.

%% ============================================================================
%% Internal
%% ============================================================================

-spec request_checkpoint(#job{}) -> {ok, string()} | {error, term()}.
request_checkpoint(#job{} = Job) ->
    JobId = wm_entity:get(id, Job),
    case main_node_addr(Job) of
        local ->
            run_local_checkpoint(Job);
        {ok, Addr} ->
            ?LOG_DEBUG("Request checkpoint on main node ~p for job ~p", [Addr, JobId]),
            %% Route through wm_api:recv -> gen_server:call(wm_compute, ...).
            try wm_rpc:call(wm_api, recv, {wm_compute, {checkpoint_now, JobId}}, Addr) of
                {ok, Time} when is_list(Time) ->
                    {ok, Time};
                {error, _} = Err ->
                    Err;
                Other ->
                    {error, Other}
            catch
                Class:ErrReason ->
                    {error, {Class, ErrReason}}
            end;
        {error, Why} ->
            %% Fall back to local attempt (on-prem / same node).
            ?LOG_DEBUG("No remote main for job ~p (~p) => local checkpoint", [JobId, Why]),
            run_local_checkpoint(Job)
    end.

-spec main_node_addr(#job{}) -> local | {ok, node_address()} | {error, term()}.
main_node_addr(#job{} = Job) ->
    NodeIds = wm_entity:get(nodes, Job),
    case NodeIds of
        [] ->
            local;
        _ ->
            Nodes = wm_conf:select_many(node, id, NodeIds),
            case wm_utils:select_main_node(Nodes) of
                not_found ->
                    {error, no_main_node};
                MainNode ->
                    case wm_self:get_node() of
                        {ok, Self} ->
                            case wm_entity:get(id, MainNode) =:= wm_entity:get(id, Self) of
                                true ->
                                    local;
                                false ->
                                    case wm_conf:get_relative_address(MainNode, Self) of
                                        not_found ->
                                            {error, no_address};
                                        Addr ->
                                            {ok, Addr}
                                    end
                            end;
                        _ ->
                            {error, no_self}
                    end
            end
    end.

-spec sh_quote(string()) -> string().
sh_quote(S) ->
    lists:flatten("'" ++ string:replace(S, "'", "'\"'\"'", all) ++ "'").

-spec run_shell(string()) -> {integer(), string()}.
run_shell(Cmd) ->
    %% Append a marker so we can recover the exit status from os:cmd/1.
    Wrapped = "(" ++ Cmd ++ "); printf 'SWM_CKPT_EXIT:%s\\n' \"$?\"",
    Out = os:cmd(Wrapped),
    case re:run(Out, "SWM_CKPT_EXIT:([0-9]+)", [{capture, all_but_first, list}]) of
        {match, [CodeStr]} ->
            {list_to_integer(CodeStr), Out};
        _ ->
            {-1, Out}
    end.
