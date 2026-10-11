-module(wm_workdir_tests).

-include_lib("eunit/include/eunit.hrl").

%% ./rebar3 eunit --module=wm_workdir_tests

-spec validate_workdir_allows_safe_paths_test() -> ok.
validate_workdir_allows_safe_paths_test() ->
    ?assertEqual(ok, wm_workdir:validate_workdir("/home/u/job")),
    ?assertEqual(ok, wm_workdir:validate_workdir("/home/u")),
    ?assertEqual(ok, wm_workdir:validate_workdir("/tmp")),
    ?assertEqual(ok, wm_workdir:validate_workdir("/var/lib/swm/job-data")),
    ok.

-spec validate_workdir_rejects_injection_test() -> ok.
validate_workdir_rejects_injection_test() ->
    ?assertEqual({error, unsafe_chars}, wm_workdir:validate_workdir("/tmp/x;id")),
    ?assertEqual({error, unsafe_chars}, wm_workdir:validate_workdir("/tmp/$(id)")),
    ?assertEqual({error, unsafe_chars}, wm_workdir:validate_workdir("/tmp/`id`")),
    ?assertEqual({error, unsafe_chars}, wm_workdir:validate_workdir("/tmp/a b")),
    ?assertEqual({error, unsafe_chars}, wm_workdir:validate_workdir("/tmp/x|y")),
    ?assertEqual({error, unsafe_chars}, wm_workdir:validate_workdir("/tmp/x&y")),
    ?assertEqual({error, parent_segment}, wm_workdir:validate_workdir("/home/u/../etc")),
    ?assertEqual({error, not_absolute}, wm_workdir:validate_workdir("relative/path")),
    ?assertEqual({error, empty}, wm_workdir:validate_workdir("")),
    ok.

-spec validate_workdir_under_home_test() -> ok.
validate_workdir_under_home_test() ->
    ?assertEqual(ok, wm_workdir:validate_workdir_under_home("/home/u", "/home/u")),
    ?assertEqual(ok, wm_workdir:validate_workdir_under_home("/home/u/job", "/home/u")),
    ?assertEqual({error, outside_home}, wm_workdir:validate_workdir_under_home("/tmp/x", "/home/u")),
    ?assertEqual({error, outside_home},
                 wm_workdir:validate_workdir_under_home("/home/u2/job", "/home/u")),
    ?assertEqual({error, unsafe_chars},
                 wm_workdir:validate_workdir_under_home("/home/u/x;id", "/home/u")),
    ok.

-spec finalize_cmd_args_is_argv_not_shell_test() -> ok.
finalize_cmd_args_is_argv_not_shell_test() ->
    {ok, Cmd} =
        wm_podman:finalize_cmd_args("/opt/swm/current/scripts/swm-container-finalize.sh",
                                    "alice",
                                    "1000",
                                    "1000",
                                    "host1",
                                    "/home/alice/work",
                                    "/var/lib/swm/job/jid"),
    ?assertEqual(<<"/opt/swm/current/scripts/swm-container-finalize.sh">>, hd(Cmd)),
    ?assertNotEqual(<<"/bin/sh">>, hd(Cmd)),
    ?assertEqual(false, lists:member(<<"-c">>, Cmd)),
    ?assertEqual(<<"/home/alice/work">>, lists:nth(6, Cmd)),
    ?assertEqual(<<"/var/lib/swm/job/jid">>, lists:nth(7, Cmd)),
    ok.

-spec finalize_cmd_args_rejects_injection_workdir_test() -> ok.
finalize_cmd_args_rejects_injection_workdir_test() ->
    ?assertEqual({error, unsafe_chars},
                 wm_podman:finalize_cmd_args("/opt/finalize.sh",
                                             "alice",
                                             "1000",
                                             "1000",
                                             "host1",
                                             "/tmp/x;id")),
    ok.

-spec jobscript_rejects_unsafe_workdir_test() -> ok.
jobscript_rejects_unsafe_workdir_test() ->
    Job = wm_jobscript:parse("#!/bin/sh\n#SWM workdir /tmp/x;id\necho hi\n"),
    ?assertEqual("", wm_entity:get(workdir, Job)),
    JobOk = wm_jobscript:parse("#!/bin/sh\n#SWM workdir /home/alice/job\necho hi\n"),
    ?assertEqual("/home/alice/job", wm_entity:get(workdir, JobOk)),
    ok.
