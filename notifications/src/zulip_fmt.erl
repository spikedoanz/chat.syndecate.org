-module(zulip_fmt).
-export([html_to_text/2, should_forward/2, format_message/2]).

%% Format a Zulip stream message into plaintext with a narrow URL.
-spec format_message(binary(), map()) -> {ok, binary()} | skip.
format_message(BaseUrl, Msg) ->
    case maps:get(<<"type">>, Msg, <<>>) of
        <<"stream">> ->
            StreamId = maps:get(<<"stream_id">>, Msg),
            Channel = maps:get(<<"display_recipient">>, Msg, <<>>),
            Topic = maps:get(<<"subject">>, Msg, <<>>),
            Sender = maps:get(<<"sender_full_name">>, Msg, <<>>),
            Content = maps:get(<<"content">>, Msg, <<>>),
            MsgId = maps:get(<<"id">>, Msg),
            Url = zulip_url:narrow_url(iolist_to_binary(BaseUrl), StreamId, Topic, MsgId),
            Plaintext = html_to_text(iolist_to_binary(BaseUrl), Content),
            Text = iolist_to_binary([
                <<"#">>, Channel, <<" / ">>, Topic, <<"\n">>,
                Sender, <<": ">>, Plaintext, <<"\n\n">>,
                Url
            ]),
            {ok, Text};
        _ ->
            skip
    end.

%% Check if a stream ID should be forwarded given a filter list.
-spec should_forward(integer(), [integer()]) -> boolean().
should_forward(_StreamId, []) -> true;
should_forward(StreamId, Filter) -> lists:member(StreamId, Filter).

%% Convert HTML to plaintext, preserving link targets.
%% Turns <a href="/user_uploads/...">file.png</a> into "file.png (https://...)"
-spec html_to_text(binary(), binary()) -> binary().
html_to_text(BaseUrl, Html) ->
    WithLinks = re:replace(Html,
        <<"<a[^>]*href=\"([^\"]*)\"[^>]*>([^<]*)</a>">>,
        fun(Match, _) -> expand_link(BaseUrl, Match) end,
        [global, {return, binary}]),
    re:replace(WithLinks, <<"<[^>]*>">>, <<>>, [global, {return, binary}]).

expand_link(BaseUrl, Match) ->
    case re:run(Match, <<"<a[^>]*href=\"([^\"]*)\"[^>]*>([^<]*)</a>">>,
                [{capture, [1, 2], binary}]) of
        {match, [Href, Text]} ->
            FullUrl = resolve_url(BaseUrl, Href),
            case FullUrl =:= Text of
                true -> FullUrl;
                false -> <<Text/binary, " (", FullUrl/binary, ")">>
            end;
        nomatch ->
            Match
    end.

resolve_url(BaseUrl, <<"/", _/binary>> = Path) ->
    <<BaseUrl/binary, Path/binary>>;
resolve_url(_BaseUrl, Url) ->
    Url.
