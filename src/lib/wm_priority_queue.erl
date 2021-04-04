-module(wm_priority_queue).

-export([new/0, insert/2, find_min/1, delete_min/1, filter/2]).

%% ============================================================================
%% Module API
%% ============================================================================

-spec new() -> [].
new() ->
    [].

-spec insert(term(), [term()]) -> [term()].
insert(Term, []) ->
    [Term];
insert(Term, [SmallestTerm | Terms]) when SmallestTerm < Term ->
    [SmallestTerm, [Term] | Terms];
insert(Term, Terms) ->
    [Term, Terms].

-spec find_min([term()]) -> empty | term().
find_min([]) ->
    empty;
find_min([Term | _]) ->
    Term.

-spec delete_min([term()]) -> [].
delete_min([]) ->
    [];
delete_min([_Term | Terms]) ->
    merge(Terms).

-spec filter(fun((term()) -> boolean()), [term()]) -> [term()].
filter(Fun, Terms) ->
    lists:filter(Fun, Terms).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec merge([term()]) -> [].
merge([]) ->
    [];
merge([X]) ->
    X;
merge([A, B | T]) ->
    merge(merge(A, B), merge(T)).

-spec merge([term()], [term()]) -> [term()].
merge([Term | _] = T, [SmallestTerm | Terms]) when SmallestTerm < Term ->
    [SmallestTerm, T | Terms];
merge([SmallestTerm | Terms], [_ | _] = T) ->
    [SmallestTerm, T | Terms];
merge([], T) ->
    T;
merge(T, []) ->
    T.
