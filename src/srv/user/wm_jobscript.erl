-module(wm_jobscript).

-export([parse/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

%% ============================================================================
%% API
%% ============================================================================

-spec parse(string()) -> tuple().
parse(JobScriptContent) ->
    Lines = string:tokens(binary_to_list(JobScriptContent), "\n"),
    Job1 = wm_entity:new(job),
    Job2 = do_parse(Lines, Job1),
    ?LOG_DEBUG("Parsed job: ~p", [Job2]),
    Job2.

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec do_parse([string()], #job{}) -> #job{}.
do_parse([], Job) ->
    Job;
do_parse([Line | T], Job) ->
    Words =
        re:split(
            string:strip(Line), "\\s+", [{return, list}, {parts, 3}]),
    ?LOG_DEBUG("Parse job script line '~s', Words=~p", [Line, Words]),
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

-spec add_requested_resource(string(), string(), #job{}) -> #job{}.
add_requested_resource(Name, PropValue, Job) ->
    ResourcesOld = wm_entity:get_attr(request, Job),
    ResourcesNew = add_resource_with_property(Name, PropValue, ResourcesOld, []),
    wm_entity:set_attr({request, ResourcesNew}, Job).

-spec add_resource_with_property(atom(), string(), [#resource{}], [#resource{}]) -> [#resource{}].
add_resource_with_property(Name, PropValue, [], ResourcesNew) ->
    NewResource = wm_entity:set_attr([{name, Name}, {properties, [{value, PropValue}]}], wm_entity:new(resource)),
    [NewResource | ResourcesNew];
add_resource_with_property(Name, PropValue, [#resource{name = Name} = OldResource | ResourcesOld], ResourcesNew) ->
    Props1 = wm_entity:get_attr(properties, OldResource),
    Props2 = proplists:delete(value, Props1),
    Props3 = [{value, PropValue} | Props2],
    NewResource = wm_entity:set_attr({properties, Props3}, OldResource),
    add_resource_with_property(Name, PropValue, ResourcesOld, [NewResource | ResourcesNew]);
add_resource_with_property(Name, PropValue, [#resource{} = OldResource | ResourcesOld], ResourcesNew) ->
    add_resource_with_property(Name, PropValue, ResourcesOld, [OldResource | ResourcesNew]).

-spec parse_line([string()], #job{}) -> #job{}.
parse_line(Ws, Job) when hd(Ws) == "ports", length(Ws) > 1 ->
    add_requested_resource("ports", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "image", length(Ws) > 1 ->
    add_requested_resource("image", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "flavor", length(Ws) > 1 ->
    add_requested_resource("flavor", lists:flatten(tl(Ws)), Job);
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
