-module(wm_sched_utils).

-export([add_input/3]).

-include("../../../include/wm_scheduler.hrl").
-include("../../lib/wm_log.hrl").

%% ============================================================================
%% API
%% ============================================================================

%% @doc Add new binary part to a binary that will be sent to scheduler
-spec add_input(term(), binary(), binary()) -> binary().
add_input(NumberOfTypes, <<>>, <<>>) ->
    <<?COMMAND_SCHEDULE/integer, NumberOfTypes/integer>>;
add_input(Type, BinPart, BinTotal) ->
    Size = byte_size(BinPart),
    <<BinTotal/binary, Type/integer, Size:4/big-integer-unit:8, BinPart/binary>>.
