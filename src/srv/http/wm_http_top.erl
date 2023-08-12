-module(wm_http_top).

-export([init/2]).

-spec init(map(), map()) -> {ok, map(), map()}.
init(Req, Opts) ->
    S = "~s v~s~nModules: ~p~nErlang v~s~nApplications:~n~p~n",
    {ok, MyVer} = application:get_key(vsn),
    {ok, MyName} = application:get_key(description),
    {ok, MyMods} = application:get_key(modules),
    Apps = application:which_applications(),
    Body = io_lib:format(S, [MyName, MyVer, MyMods, erlang:system_info(otp_release), Apps]),
    Req2 = cowboy_req:reply(200, [{<<"content-type">>, <<"text/plain">>}], list_to_binary(Body), Req),
    {ok, Req2, Opts}.
