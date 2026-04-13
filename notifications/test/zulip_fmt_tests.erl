-module(zulip_fmt_tests).
-include_lib("eunit/include/eunit.hrl").

-define(BASE, <<"https://chat.syndecate.org">>).

stream_message_format_test() ->
    Msg = #{<<"type">> => <<"stream">>,
            <<"stream_id">> => 11,
            <<"display_recipient">> => <<"99-infra">>,
            <<"subject">> => <<"general chat">>,
            <<"sender_full_name">> => <<"Alice">>,
            <<"content">> => <<"<p>hello world</p>">>,
            <<"id">> => 100},
    {ok, Text} = zulip_fmt:format_message(?BASE, Msg),
    ?assertMatch({match, _}, re:run(Text, <<"#99-infra / general chat">>)),
    ?assertMatch({match, _}, re:run(Text, <<"Alice: hello world">>)),
    ?assertMatch({match, _}, re:run(Text, <<"https://chat.syndecate.org/#narrow/channel/11/topic/general.20chat/with/100">>)).

non_stream_message_skipped_test() ->
    Msg = #{<<"type">> => <<"private">>,
            <<"id">> => 1},
    ?assertEqual(skip, zulip_fmt:format_message(?BASE, Msg)).

upload_in_format_test() ->
    Msg = #{<<"type">> => <<"stream">>,
            <<"stream_id">> => 5,
            <<"display_recipient">> => <<"general">>,
            <<"subject">> => <<"files">>,
            <<"sender_full_name">> => <<"Bob">>,
            <<"content">> => <<"<a href=\"/user_uploads/2/f/test.pdf\">test.pdf</a>">>,
            <<"id">> => 50},
    {ok, Text} = zulip_fmt:format_message(?BASE, Msg),
    ?assertMatch({match, _}, re:run(Text, <<"https://chat.syndecate.org/user_uploads/2/f/test.pdf">>)).
