-module(wm_jobscript).

-export([parse/1]).

-include("../../lib/wm_log.hrl").

%% ============================================================================
%% API
%% ============================================================================

-spec parse(string()) -> tuple().
parse(JobScriptContent) ->
    Lines = string:tokens(binary_to_list(JobScriptContent), "\n"),
    Job1 = wm_entity:new(<<"job">>),
    Job2 = do_parse(Lines, Job1),
    ?LOG_DEBUG("Job: ~p", [Job2]),
    Job2.

%% ============================================================================
%% Implementation functions
%% ============================================================================

do_parse([], Job) ->
    Job;
do_parse([Line | T], Job) ->
    Words =
        re:split(
            string:strip(Line), "\\s+", [{return, list}, {parts, 3}]),
    ?LOG_DEBUG("Parse job script line '~p', Words=~p", [Line, Words]),
    case length(Words) > 1 of
        true ->
            case hd(Words) of
                "#SWM" ->
                    do_parse(T, parse_line(tl(Words), Job));
                _ ->
                    do_parse(T, Job)
            end;
        false ->
            do_parse(T, Job)
    end.

parse_line(Ws, Job) when hd(Ws) == "account_id", length(Ws) > 1 ->
    wm_entity:set_attr({account_id, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "name", length(Ws) > 1 ->
    wm_entity:set_attr({name, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "comment", length(Ws) > 1 ->
    wm_entity:set_attr({comment, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "stdin", length(Ws) > 1 ->
    wm_entity:set_attr({stdin, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "stdout", length(Ws) > 1 ->
    wm_entity:set_attr({stdout, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "stderr", length(Ws) > 1 ->
    wm_entity:set_attr({stderr, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "workdir", length(Ws) > 1 ->
    wm_entity:set_attr({workdir,
                        lists:flatten(
                            filename:absname(tl(Ws)))},
                       Job);
parse_line(Ws, Job) when hd(Ws) == "relocatable" ->
    wm_entity:set_attr({relocatable, true}, Job);
parse_line(Ws, Job) when hd(Ws) == "input" ->
    Old = wm_entity:get_attr(input_files, Job),
    wm_entity:set_attr({input_files, Old ++ tl(Ws)}, Job);
parse_line(Ws, Job) when hd(Ws) == "output" ->
    Old = wm_entity:get_attr(output_files, Job),
    wm_entity:set_attr({output_files, Old ++ tl(Ws)}, Job);
parse_line(Ws, Job) ->
    ?LOG_DEBUG("Unknown jobscript statement: ~p (~p)", [Ws, wm_entity:get_attr(id, Job)]),
    Job.
