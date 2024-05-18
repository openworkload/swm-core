-module(wm_resource_utils).

-export([get_ingres_ports_map/2, get_ingres_ports_str/1, get_port_tuples/1]).

-include("wm_entity.hrl").
-include("wm_log.hrl").

-spec get_ingres_port_with_proto(string()) -> {ok, string()} | {error, not_found}.
get_ingres_port_with_proto(Port) ->
    case string:substr(Port, string:len(Port) - 1) of
        "in" ->
            {ok, string:substr(Port, 1, string:len(Port) - 3)};
        _ ->
            {error, not_found}
    end.

-spec get_ingres_ports_map([#resource{}], atom()) -> map().
get_ingres_ports_map([], _) ->
    #{};
get_ingres_ports_map([#resource{name = "ports", properties = Properties} | T], KeyType) ->
    case proplists:get_value(value, Properties) of
        Value when is_list(Value) ->
            Ports = string:split(Value, ",", all),
            lists:foldl(fun(Port, Map) ->
                           case get_ingres_port_with_proto(Port) of
                               {ok, PortAndProto} ->
                                   PortNumberStr = hd(string:split(PortAndProto, "/")),
                                   case KeyType of
                                       binaries ->
                                           maps:put(list_to_binary(PortNumberStr), #{}, Map);
                                       strings ->
                                           maps:put(PortNumberStr, #{}, Map)
                                   end;
                               {error, not_found} ->
                                   Map
                           end
                        end,
                        #{},
                        Ports);
        _ ->
            get_ingres_ports_map(T, KeyType)
    end;
get_ingres_ports_map([_ | T], KeyType) ->
    get_ingres_ports_map(T, KeyType).

-spec get_ingres_ports_str([#resource{}]) -> [string()].
get_ingres_ports_str(Resources) ->
    Ports = maps:keys(get_ingres_ports_map(Resources, strings)),
    lists:flatten(
        string:join(Ports, ",")).

-spec get_port_tuples([#resource{}]) -> {[{string(), integer(), integer()}], []}.
get_port_tuples([]) ->
    [];
get_port_tuples([#resource{name = "ports", properties = Properties} | _]) ->
    Value = proplists:get_value(value, Properties), % example of the Value: "8888/tcp,6001/udp"
    lists:foldl(fun(PortStr,
                    List) ->  % Example: "8081/tcp/in" or "8888/tcp/out"
                   Parts = string:split(PortStr, "/", all),
                   case length(Parts) of
                       3 ->
                           PortDirection = lists:nth(3, Parts),
                           case lists:nth(2, Parts) of
                               "tcp" ->
                                   PortNumber = list_to_integer(lists:nth(1, Parts)),
                                   [{PortDirection, PortNumber, PortNumber} | List];
                               OtherType ->
                                   ?LOG_DEBUG("Requested port protocol is not supported: ~p", [OtherType]),
                                   List
                           end;
                       WrongFormat ->
                           ?LOG_DEBUG("Requested job port format is incorrect: ~p", [WrongFormat]),
                           List
                   end
                end,
                [],
                string:split(Value, ",", all));
get_port_tuples([_ | T]) ->
    get_port_tuples(T).
