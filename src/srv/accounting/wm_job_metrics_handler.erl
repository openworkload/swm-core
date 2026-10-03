-module(wm_job_metrics_handler).

%% Cowboy handler for Prometheus text scrape at /metrics (cleartext).

-export([init/2]).

-include("../../lib/wm_log.hrl").

-spec init(cowboy_req:req(), term()) -> {ok, cowboy_req:req(), term()}.
init(Req0, State) ->
    Body = wm_job_metrics:scrape_reply(),
    Req = cowboy_req:reply(200, #{<<"content-type">> => prometheus_text_format:content_type()}, Body, Req0),
    {ok, Req, State}.
