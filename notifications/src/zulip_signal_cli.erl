-module(zulip_signal_cli).
-export([main/0]).

%% Standalone CLI mode: connects to Zulip and prints formatted messages to stdout.
main() ->
    application:ensure_all_started(hackney),
    application:ensure_all_started(jiffy),
    application:load(zulip_signal),
    {ok, BaseUrl} = application:get_env(zulip_signal, zulip_url),
    {ok, Email} = application:get_env(zulip_signal, zulip_email),
    {ok, ApiKey} = application:get_env(zulip_signal, zulip_api_key),
    {ok, Filter} = application:get_env(zulip_signal, channel_filter),
    State = #{
        base_url => BaseUrl,
        email => Email,
        api_key => ApiKey,
        channel_filter => Filter
    },
    io:format("Connecting to ~s as ~s...~n", [BaseUrl, Email]),
    loop_register(State).

loop_register(State) ->
    case register_queue(State) of
        {ok, QueueId, LastEventId} ->
            io:format("Listening for messages (queue ~s)~n~n", [QueueId]),
            loop_poll(State, QueueId, LastEventId);
        {error, Reason} ->
            io:format("Registration failed: ~p, retrying in 5s~n", [Reason]),
            timer:sleep(5000),
            loop_register(State)
    end.

loop_poll(State, QueueId, LastEventId) ->
    case poll_events(State, QueueId, LastEventId) of
        {ok, Events, NewLastId} ->
            print_events(Events, State),
            loop_poll(State, QueueId, NewLastId);
        {error, queue_not_found} ->
            io:format("~nQueue expired, re-registering...~n", []),
            loop_register(State);
        {error, Reason} ->
            io:format("Poll error: ~p, retrying in 5s~n", [Reason]),
            timer:sleep(5000),
            loop_poll(State, QueueId, LastEventId)
    end.

print_events(Events, State) ->
    lists:foreach(fun(E) -> print_event(E, State) end, Events).

print_event(#{<<"type">> := <<"message">>, <<"message">> := Msg}, State) ->
    #{base_url := BaseUrl, channel_filter := Filter} = State,
    case maps:get(<<"type">>, Msg, <<>>) of
        <<"stream">> ->
            StreamId = maps:get(<<"stream_id">>, Msg),
            case should_forward(StreamId, Filter) of
                true ->
                    Channel = maps:get(<<"display_recipient">>, Msg, <<>>),
                    Topic = maps:get(<<"subject">>, Msg, <<>>),
                    Sender = maps:get(<<"sender_full_name">>, Msg, <<>>),
                    Content = maps:get(<<"content">>, Msg, <<>>),
                    MsgId = maps:get(<<"id">>, Msg),
                    Url = zulip_url:narrow_url(
                        iolist_to_binary(BaseUrl), StreamId, Topic, MsgId),
                    Stripped = strip_html(Content),
                    Resolved = resolve_uploads(iolist_to_binary(BaseUrl), Stripped),
                    io:format("~ts/~ts~n~ts: ~ts~n~n~ts~n~n",
                        [Channel, Topic, Sender, Resolved, Url]);
                false ->
                    ok
            end;
        _ ->
            ok
    end;
print_event(_, _) ->
    ok.

should_forward(_StreamId, []) -> true;
should_forward(StreamId, Filter) -> lists:member(StreamId, Filter).

strip_html(Html) ->
    re:replace(Html, <<"<[^>]*>">>, <<>>, [global, {return, binary}]).

resolve_uploads(BaseUrl, Text) ->
    re:replace(Text, <<"/user_uploads/">>,
        <<BaseUrl/binary, "/user_uploads/">>,
        [global, {return, binary}]).

%% HTTP helpers (same as zulip_poller)

auth_headers(#{email := Email, api_key := ApiKey}) ->
    Creds = base64:encode(iolist_to_binary([Email, ":", ApiKey])),
    [{<<"Authorization">>, iolist_to_binary([<<"Basic ">>, Creds])}].

register_queue(#{base_url := BaseUrl} = State) ->
    Url = iolist_to_binary([BaseUrl, "/api/v1/register"]),
    Body = <<"event_types=[\"message\"]&all_public_streams=true">>,
    Headers = [{<<"Content-Type">>, <<"application/x-www-form-urlencoded">>} | auth_headers(State)],
    case hackney:request(post, Url, Headers, Body, [with_body]) of
        {ok, 200, _, RespBody} ->
            Json = jiffy:decode(RespBody, [return_maps]),
            {ok, maps:get(<<"queue_id">>, Json), maps:get(<<"last_event_id">>, Json)};
        {ok, Status, _, RespBody} ->
            {error, {http, Status, RespBody}};
        {error, Reason} ->
            {error, Reason}
    end.

poll_events(State, QueueId, LastEventId) ->
    #{base_url := BaseUrl} = State,
    Url = iolist_to_binary([
        BaseUrl, "/api/v1/events",
        <<"?queue_id=">>, hackney_url:urlencode(QueueId),
        <<"&last_event_id=">>, integer_to_binary(LastEventId)
    ]),
    case hackney:request(get, Url, auth_headers(State), <<>>, [with_body, {recv_timeout, 90000}]) of
        {ok, 200, _, RespBody} ->
            Json = jiffy:decode(RespBody, [return_maps]),
            Events = maps:get(<<"events">>, Json, []),
            NewLastId = lists:foldl(fun(E, Acc) ->
                max(maps:get(<<"id">>, E, Acc), Acc)
            end, LastEventId, Events),
            {ok, Events, NewLastId};
        {ok, 400, _, RespBody} ->
            case jiffy:decode(RespBody, [return_maps]) of
                #{<<"code">> := <<"BAD_EVENT_QUEUE_ID">>} -> {error, queue_not_found};
                _ -> {error, {http, 400, RespBody}}
            end;
        {ok, Status, _, RespBody} ->
            {error, {http, Status, RespBody}};
        {error, Reason} ->
            {error, Reason}
    end.
