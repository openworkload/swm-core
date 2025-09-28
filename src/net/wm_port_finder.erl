-module(wm_port_finder).

-export([find_open_ephemeral_port/0]).

-include("../lib/wm_log.hrl").

-define(DEFAULT_LINUX_EPHEMERAL_PORTS_RANGE, {32768, 60999}).
-define(LINUX_PORT_RANGE_FILE, "/proc/sys/net/ipv4/ip_local_port_range").

%% ============================================================================
%% Module API
%% ============================================================================

-spec find_open_ephemeral_port() -> {ok, pos_integer()} | {error, no_available_port}.
find_open_ephemeral_port() ->
    {MinPort, MaxPort} = get_ephemeral_port_range(),
    find_open_ephemeral_port(MinPort, MaxPort).

-spec find_open_ephemeral_port(pos_integer(), pos_integer()) -> {ok, pos_integer()} | {error, no_available_port}.
find_open_ephemeral_port(Port, MaxPort) when Port > MaxPort ->
    {error, no_available_port};
find_open_ephemeral_port(Port, MaxPort) ->
    case is_port_available(Port) of
        true ->
            {ok, Port};
        false ->
            find_open_ephemeral_port(Port + 1, MaxPort)
    end.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec get_ephemeral_port_range() -> {pos_integer(), pos_integer()}.
get_ephemeral_port_range() ->
    case file:read_file(?LINUX_PORT_RANGE_FILE) of
        {ok, Binary} ->
            Line = binary_to_list(Binary),
            case string:tokens(
                     string:strip(Line, right, $\n), " \t")
            of
                [MinStr, MaxStr] ->
                    {list_to_integer(MinStr), list_to_integer(MaxStr)};
                _ ->
                    ?LOG_WARN("Cannot parse local ip port range file line: ~p", [Line]),
                    ?DEFAULT_LINUX_EPHEMERAL_PORTS_RANGE
            end;
        {error, _} ->
            ?LOG_WARN("Cannot read local ip port rage file: ~p", [?LINUX_PORT_RANGE_FILE]),
            ?DEFAULT_LINUX_EPHEMERAL_PORTS_RANGE
    end.

-spec is_port_available(pos_integer()) -> boolean().
is_port_available(Port) ->
    case gen_tcp:listen(Port, [{active, false}, {reuseaddr, true}]) of
        {ok, Socket} ->
            gen_tcp:close(Socket),
            true;
        {error, eaddrinuse} ->
            false;
        {error, _Other} ->
            false
    end.
