-define(DISABLE_LOGGING_IN_TESTS, true).
-define(DEBUG, true).

-ifdef(DEBUG).

-define(FN, element(2, element(2, process_info(self(), current_function)))).

-ifndef(TEST).

-define(LOG_DEBUG(X), wm_log:debug("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_INFO(X), wm_log:info("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_NOTE(X), wm_log:note("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_WARN(X), wm_log:warn("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_ERROR(X), wm_log:err("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_FATAL(X), wm_log:fatal("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_DEBUG(X, Y), wm_log:debug("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_INFO(X, Y), wm_log:info("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_NOTE(X, Y), wm_log:note("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_WARN(X, Y), wm_log:warn("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_ERROR(X, Y), wm_log:err("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_FATAL(X, Y), wm_log:fatal("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).

-else. %TEST

-ifndef(DISABLE_LOGGING_IN_TESTS).

-include_lib("eunit/include/eunit.hrl").

-define(LOG_DEBUG(X), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_INFO(X), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_NOTE(X), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_WARN(X), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_ERROR(X), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_FATAL(X), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, X])).
-define(LOG_DEBUG(X, Y), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_INFO(X, Y), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_NOTE(X, Y), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_WARN(X, Y), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_ERROR(X, Y), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).
-define(LOG_FATAL(X, Y), ?debugFmt("~p:~p| ~s", [?MODULE, ?FN, wm_utils:format(X, Y)])).

-else. %!DISABLE_LOGGING_IN_TESTS

-define(LOG_DEBUG(X), ok).
-define(LOG_INFO(X), ok).
-define(LOG_NOTE(X), ok).
-define(LOG_WARN(X), ok).
-define(LOG_ERROR(X), ok).
-define(LOG_FATAL(X), ok).
-define(LOG_DEBUG(X, Y), ok).
-define(LOG_INFO(X, Y), ok).
-define(LOG_NOTE(X, Y), ok).
-define(LOG_WARN(X, Y), ok).
-define(LOG_ERROR(X, Y), ok).
-define(LOG_FATAL(X, Y), ok).

-endif. %DISABLE_LOGGING_IN_TESTS
-endif. %TEST

-else. %!DEBUG

-ifndef(TEST).

-define(LOG_DEBUG(X), true).
-define(LOG_INFO(X), wm_log:info(X)).
-define(LOG_NOTE(X), wm_log:note(X)).
-define(LOG_WARN(X), wm_log:warn(X)).
-define(LOG_ERROR(X), wm_log:err(X)).
-define(LOG_FATAL(X), wm_log:fatal(X)).
-define(LOG_INFO(X, Y), wm_log:info(X, Y)).
-define(LOG_NOTE(X, Y), wm_log:note(X, Y)).
-define(LOG_WARN(X, Y), wm_log:warn(X, Y)).
-define(LOG_ERROR(X, Y), wm_log:err(X, Y)).
-define(LOG_FATAL(X, Y), wm_log:fatal(X, Y)).

-else. %TEST

-ifndef(DISABLE_LOGGING_IN_TESTS).

-include_lib("eunit/include/eunit.hrl").

-define(LOG_DEBUG(X), ?debugMsg(X)).
-define(LOG_INFO(X), ?debugMsg(X)).
-define(LOG_NOTE(X), ?debugMsg(X)).
-define(LOG_WARN(X), ?debugMsg(X)).
-define(LOG_ERROR(X), ?debugMsg(X)).
-define(LOG_FATAL(X), ?debugMsg(X)).
-define(LOG_INFO(X, Y), ?debugFmt(X, Y)).
-define(LOG_NOTE(X, Y), ?debugFmt(X, Y)).
-define(LOG_WARN(X, Y), ?debugFmt(X, Y)).
-define(LOG_ERROR(X, Y), ?debugFmt(X, Y)).
-define(LOG_FATAL(X, Y), ?debugFmt(X, Y)).

-else. %DISABLE_LOGGING_IN_TESTS

-define(LOG_DEBUG(X), ok).
-define(LOG_INFO(X), ok).
-define(LOG_NOTE(X), ok).
-define(LOG_WARN(X), ok).
-define(LOG_ERROR(X), ok).
-define(LOG_FATAL(X), ok).
-define(LOG_DEBUG(X, Y), ok).
-define(LOG_INFO(X, Y), ok).
-define(LOG_NOTE(X, Y), ok).
-define(LOG_WARN(X, Y), ok).
-define(LOG_ERROR(X, Y), ok).
-define(LOG_FATAL(X, Y), ok).

-endif. %DISABLE_LOGGING_IN_TESTS
-endif. %TEST
-endif. %DEBUG
