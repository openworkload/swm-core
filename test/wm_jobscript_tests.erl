-module(wm_jobscript_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_jobscript_tests

-spec parse_nodes_directive_test() -> ok.
parse_nodes_directive_test() ->
    JobScript = "#!/bin/bash\n#SWM nodes 3\necho hello",
    Job = wm_jobscript:parse(JobScript),
    Resources = wm_entity:get(request, Job),
    NodeResource = lists:keyfind("node", 2, Resources),
    ?assertMatch(#resource{name = "node", count = 3}, NodeResource).

-spec parse_single_node_default_test() -> ok.
parse_single_node_default_test() ->
    JobScript = "#!/bin/bash\necho hello",
    Job = wm_jobscript:parse(JobScript),
    Resources = wm_entity:get(request, Job),
    % When no nodes directive is present, default should be added elsewhere
    % This test just ensures parsing doesn't crash
    ?assertEqual([], Resources).
