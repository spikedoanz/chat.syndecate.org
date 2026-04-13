-module(filter_tests).
-include_lib("eunit/include/eunit.hrl").

empty_filter_forwards_all_test() ->
    ?assert(zulip_signal_cli:should_forward(11, [])).

matching_id_forwards_test() ->
    ?assert(zulip_signal_cli:should_forward(11, [11, 22])).

non_matching_id_blocked_test() ->
    ?assertNot(zulip_signal_cli:should_forward(99, [11, 22])).

single_filter_match_test() ->
    ?assert(zulip_signal_cli:should_forward(5, [5])).

single_filter_no_match_test() ->
    ?assertNot(zulip_signal_cli:should_forward(6, [5])).
