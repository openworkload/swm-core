-module(wm_crash_report).

-export([crash_report/0]).

crash_report() ->
    Date = erlang:list_to_binary(rfc1123_local_date()),
    Header = binary:list_to_bin([<<"=erl_crash_dump:0.2\n">>, Date, <<"\nSystem version: ">>]),
    Ets = ets_info(),
    Report =
        binary:list_to_bin([Header,
                            erlang:list_to_binary(
                                erlang:system_info(system_version)),
                            erlang:system_info(info),
                            erlang:system_info(procs),
                            Ets,
                            erlang:system_info(dist),
                            <<"=loaded_modules\n">>,
                            binary:replace(
                                erlang:system_info(loaded), <<"\n">>, <<"\n=mod:">>, [global])]),
    file:write_file("/tmp/erl_crash.dump", Report).

ets_info() ->
    binary:list_to_bin([ets_table_info(T) || T <- ets:all()]).

ets_table_info(Table) ->
    Info = ets:info(Table),
    Owner =
        erlang:list_to_binary(
            erlang:pid_to_list(
                proplists:get_value(owner, Info))),
    TableN =
        erlang:list_to_binary(
            erlang:atom_to_list(
                proplists:get_value(name, Info))),
    Name =
        erlang:list_to_binary(
            erlang:atom_to_list(
                proplists:get_value(name, Info))),
    Objects =
        erlang:list_to_binary(
            erlang:integer_to_list(
                proplists:get_value(size, Info))),
    binary:list_to_bin([<<"=ets:">>,
                        Owner,
                        <<"\nTable: ">>,
                        TableN,
                        <<"\nName: ">>,
                        Name,
                        <<"\nObjects: ">>,
                        Objects,
                        <<"\n">>]).

rfc1123_local_date() ->
    rfc1123_local_date(os:timestamp()).

rfc1123_local_date({A, B, C}) ->
    rfc1123_local_date(calendar:now_to_local_time({A, B, C}));
rfc1123_local_date({{YYYY, MM, DD}, {Hour, Min, Sec}}) ->
    DayNumber = calendar:day_of_the_week({YYYY, MM, DD}),
    lists:flatten(
        io_lib:format("~s, ~2.2.0w ~3.s ~4.4.0w ~2.2.0w:~2.2.0w:~2.2"
                      ".0w GMT",
                      [httpd_util:day(DayNumber), DD, httpd_util:month(MM), YYYY, Hour, Min, Sec]));
rfc1123_local_date(Epoch) when erlang:is_integer(Epoch) ->
    rfc1123_local_date(calendar:gregorian_seconds_to_datetime(Epoch + 62167219200)).
