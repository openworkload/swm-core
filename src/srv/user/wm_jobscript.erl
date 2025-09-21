-module(wm_jobscript).

-export([parse/1]).

-include("../../lib/wm_entity.hrl").
-include("../../lib/wm_log.hrl").

%% ============================================================================
%% API
%% ============================================================================

-spec parse(string()) -> tuple().
parse(JobScriptContent) when is_binary(JobScriptContent) ->
    parse(binary_to_list(JobScriptContent));
parse(JobScriptContent) when is_list(JobScriptContent) ->
    Lines = string:tokens(JobScriptContent, "\n"),
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
    ?LOG_DEBUG("Parse job script line '~s': ~1000p", [Line, Words]),
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

-spec add_requested_resource(string(), integer(), string() | integer(), #job{}) -> #job{}.
add_requested_resource(Name, Count, PropValue, Job) ->
    ResourcesOld = wm_entity:get(request, Job),
    ResourcesNew = add_resource_with_property(Name, Count, PropValue, ResourcesOld, []),
    wm_entity:set({request, ResourcesNew}, Job).

-spec add_requested_resource(string(), string() | integer(), #job{}) -> #job{}.
add_requested_resource(Name, PropValue, Job) ->
    add_requested_resource(Name, 1, PropValue, Job).

-spec add_resource_with_property(atom(), integer(), string() | integer(), [#resource{}], [#resource{}]) ->
                                    [#resource{}].
add_resource_with_property(Name, Count, [], [], ResourcesNew) ->
    NewResource = wm_entity:set([{name, Name}, {count, Count}], wm_entity:new(resource)),
    [NewResource | ResourcesNew];
add_resource_with_property(Name, Count, PropValue, [], ResourcesNew) ->
    NewResource =
        wm_entity:set([{name, Name}, {count, Count}, {properties, [{value, PropValue}]}], wm_entity:new(resource)),
    [NewResource | ResourcesNew];
add_resource_with_property(Name, Count, [], [#resource{name = Name} = OldResource | ResourcesOld], ResourcesNew) ->
    NewResource = wm_entity:set({count, Count}, OldResource),
    add_resource_with_property(Name, Count, [], ResourcesOld, [NewResource | ResourcesNew]);
add_resource_with_property(Name,
                           Count,
                           PropValue,
                           [#resource{name = Name} = OldResource | ResourcesOld],
                           ResourcesNew) ->
    Props1 = wm_entity:get(properties, OldResource),
    Props2 = proplists:delete(value, Props1),
    Props3 = [{value, PropValue} | Props2],
    NewResource = wm_entity:set({count, Count}, {properties, Props3}, OldResource),
    add_resource_with_property(Name, Count, PropValue, ResourcesOld, [NewResource | ResourcesNew]);
add_resource_with_property(Name, Count, PropValue, [#resource{} = OldResource | ResourcesOld], ResourcesNew) ->
    add_resource_with_property(Name, Count, PropValue, ResourcesOld, [OldResource | ResourcesNew]).

-spec parse_line([string()], #job{}) -> #job{}.
parse_line(Ws, Job) when hd(Ws) == "ports", length(Ws) > 1 ->
    add_requested_resource("ports", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "cloud-image", length(Ws) > 1 ->
    add_requested_resource("cloud-image", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "submission-address", length(Ws) > 1 ->
    add_requested_resource("submission-address", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "container-image", length(Ws) > 1 ->
    add_requested_resource("container-image", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "flavor", length(Ws) > 1 ->
    add_requested_resource("flavor", lists:flatten(tl(Ws)), Job);
parse_line(Ws, Job) when hd(Ws) == "gpus", length(Ws) > 1 ->
    add_requested_resource("gpus", list_to_integer(lists:flatten(tl(Ws))), [], Job);
parse_line(Ws, Job) when hd(Ws) == "account", length(Ws) > 1 ->
    wm_entity:set({account_id, get_account_id(lists:flatten(tl(Ws)))}, Job);
parse_line(Ws, Job) when hd(Ws) == "name", length(Ws) > 1 ->
    wm_entity:set({name, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "comment", length(Ws) > 1 ->
    wm_entity:set({comment, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "stdin", length(Ws) > 1 ->
    wm_entity:set({stdin, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "stdout", length(Ws) > 1 ->
    wm_entity:set({stdout, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "stderr", length(Ws) > 1 ->
    wm_entity:set({stderr, lists:flatten(tl(Ws))}, Job);
parse_line(Ws, Job) when hd(Ws) == "workdir", length(Ws) > 1 ->
    wm_entity:set({workdir,
                   lists:flatten(
                       filename:absname(tl(Ws)))},
                  Job);
parse_line(Ws, Job) when hd(Ws) == "relocatable" ->
    wm_entity:set({relocatable, true}, Job);
parse_line(Ws, Job) when hd(Ws) == "input-files" ->
    Old = wm_entity:get(input_files, Job),
    wm_entity:set({input_files, Old ++ tl(Ws)}, Job);
parse_line(Ws, Job) when hd(Ws) == "output-files" ->
    Old = wm_entity:get(output_files, Job),
    wm_entity:set({output_files, Old ++ tl(Ws)}, Job);
parse_line(Ws, Job) ->
    ?LOG_DEBUG("Unknown jobscript statement: ~p (~p)", [Ws, wm_entity:get(id, Job)]),
    Job.

-spec get_account_id(string()) -> account_id().
get_account_id(AccountName) ->
    {ok, Account} = wm_conf:select(account, {name, AccountName}),
    wm_entity:get(id, Account).
