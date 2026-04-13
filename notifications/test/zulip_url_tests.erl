-module(zulip_url_tests).
-include_lib("eunit/include/eunit.hrl").

space_test() ->
    Url = zulip_url:narrow_url(<<"https://chat.example.com">>, 11, <<"general chat">>, 100),
    ?assertEqual(<<"https://chat.example.com/#narrow/channel/11/topic/general.20chat/with/100">>, Url).

period_test() ->
    Url = zulip_url:narrow_url(<<"https://x.com">>, 1, <<"v2.0 release">>, 1),
    ?assertMatch(<<"https://x.com/#narrow/channel/1/topic/v2.2E0.20release/with/1">>, Url).

percent_test() ->
    Url = zulip_url:narrow_url(<<"https://x.com">>, 1, <<"100% done">>, 1),
    ?assertEqual(<<"https://x.com/#narrow/channel/1/topic/100.25.20done/with/1">>, Url).

parens_test() ->
    Url = zulip_url:narrow_url(<<"https://x.com">>, 1, <<"foo (bar)">>, 1),
    ?assertEqual(<<"https://x.com/#narrow/channel/1/topic/foo.20.28bar.29/with/1">>, Url).

mixed_punctuation_test() ->
    Url = zulip_url:narrow_url(<<"https://x.com">>, 42, <<"v1.0 (beta) 50%">>, 99),
    ?assertEqual(<<"https://x.com/#narrow/channel/42/topic/v1.2E0.20.28beta.29.2050.25/with/99">>, Url).

plain_alphanumeric_test() ->
    Url = zulip_url:narrow_url(<<"https://x.com">>, 5, <<"hello-world_123">>, 7),
    ?assertEqual(<<"https://x.com/#narrow/channel/5/topic/hello-world_123/with/7">>, Url).
