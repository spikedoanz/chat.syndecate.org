-module(html_to_text_tests).
-include_lib("eunit/include/eunit.hrl").

-define(BASE, <<"https://chat.syndecate.org">>).

upload_link_test() ->
    Html = <<"<p><a href=\"/user_uploads/2/44/abc.png\">image.png</a></p>">>,
    Result = zulip_signal_cli:html_to_text(?BASE, Html),
    ?assertMatch({match, _}, re:run(Result, <<"https://chat.syndecate.org/user_uploads/2/44/abc.png">>)).

absolute_link_stays_test() ->
    Html = <<"<a href=\"https://example.com/foo\">click here</a>">>,
    Result = zulip_signal_cli:html_to_text(?BASE, Html),
    ?assertMatch({match, _}, re:run(Result, <<"https://example.com/foo">>)).

link_text_equals_url_no_duplicate_test() ->
    Html = <<"<a href=\"https://example.com\">https://example.com</a>">>,
    Result = zulip_signal_cli:html_to_text(?BASE, Html),
    %% Should not contain "https://example.com (https://example.com)"
    ?assertEqual(nomatch, re:run(Result, <<"\\(https://example.com\\)">>)).

tags_stripped_test() ->
    Html = <<"<p>Hello <strong>world</strong></p>">>,
    Result = zulip_signal_cli:html_to_text(?BASE, Html),
    ?assertEqual(nomatch, re:run(Result, <<"<">>)),
    ?assertMatch({match, _}, re:run(Result, <<"Hello world">>)).

plain_text_unchanged_test() ->
    Html = <<"just plain text">>,
    Result = zulip_signal_cli:html_to_text(?BASE, Html),
    ?assertEqual(<<"just plain text">>, Result).

multiple_links_test() ->
    Html = <<"<a href=\"/user_uploads/a\">file1</a> and <a href=\"/user_uploads/b\">file2</a>">>,
    Result = zulip_signal_cli:html_to_text(?BASE, Html),
    ?assertMatch({match, _}, re:run(Result, <<"https://chat.syndecate.org/user_uploads/a">>)),
    ?assertMatch({match, _}, re:run(Result, <<"https://chat.syndecate.org/user_uploads/b">>)).
