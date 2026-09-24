%%% @doc Behaviour for the job-container runtime backend (Podman / libpod).
%%%
%%% wm_container orchestrates a backend-provided step list. The Podman backend
%%% may collapse or reorder steps (e.g. create+start) as long as
%%% wm_container has matching handle_cast clauses for those step atoms.
-module(wm_container_runtime).

-include("../../lib/wm_entity.hrl").

-export([]).

-type steps() :: [atom() | {atom(), term()}].
-type cont_id() :: string().

-callback run_steps() -> steps().
-callback communicate_steps(binary()) -> steps().

-callback ensure_create_ready(#job{}) -> ok | {error, string()}.
-callback create(#job{}, string(), map(), pid(), steps()) -> {cont_id(), pid()}.
-callback start(#job{}, steps()) -> term().
-callback attach(#job{}, pid(), steps()) -> {cont_id(), pid()}.
-callback attach_ws(#job{}, pid(), steps()) -> {cont_id(), pid()}.
-callback send(pid(), binary(), steps()) -> term().
-callback create_exec(#job{}, steps()) -> pid().
-callback start_exec(#job{}, string(), pid(), steps()) -> term().
-callback delete(#job{}, pid()) -> ok.
-callback stop_client(pid() | undefined) -> ok.

-callback get_unregistered_images() -> list().
-callback get_unregistered_image(string()) -> term().
