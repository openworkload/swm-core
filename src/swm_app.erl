-module(swm_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% Application callbacks
%%====================================================================

-spec start(any(), any()) -> no_return().
start(_StartType, _StartArgs) ->
    Root = os:getenv("SWM_ROOT", "/opt/swm"),
    Spool = os:getenv("SWM_SPOOL", "/opt/swm/spool"),
    Port = os:getenv("SWM_API_PORT", 10001),
    MyShortName = os:getenv("SWM_SNAME", "node"),
    ParentHost = os:getenv("SWM_PARENT_HOST", none),
    ParentPort = list_to_integer(os:getenv("SWM_PARENT_PORT", 0)),
    Args =
        [{spool, Spool},
         {parent_host, ParentHost},
         {parent_port, ParentPort},
         {sname, MyShortName},
         {default_api_port, Port},
         {root, Root},
         {printer, file}],
    wm_root_sup:start_link(Args).

-spec stop(any()) -> ok.
stop(_State) ->
    ok.
