-module(zulip_poller).
-behaviour(gen_server).
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(REGISTER_URL, "/api/v1/register").
-define(EVENTS_URL, "/api/v1/events").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, BaseUrl} = application:get_env(zulip_signal, zulip_url),
    {ok, Email} = application:get_env(zulip_signal, zulip_email),
    {ok, ApiKey} = application:get_env(zulip_signal, zulip_api_key),
    {ok, Filter} = application:get_env(zulip_signal, channel_filter),
    State = #{
        base_url => BaseUrl,
        email => Email,
        api_key => ApiKey,
        channel_filter => Filter,
        queue_id => undefined,
        last_event_id => -1
    },
    self() ! register_queue,
    {ok, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(register_queue, State) ->
    case register_queue(State) of
        {ok, QueueId, LastEventId} ->
            logger:info("Registered event queue: ~s", [QueueId]),
            self() ! poll,
            {noreply, State#{queue_id => QueueId, last_event_id => LastEventId}};
        {error, Reason} ->
            logger:error("Failed to register queue: ~p, retrying in 5s", [Reason]),
            erlang:send_after(5000, self(), register_queue),
            {noreply, State}
    end;

handle_info(poll, #{queue_id := QueueId, last_event_id := LastEventId} = State) ->
    case poll_events(State, QueueId, LastEventId) of
        {ok, Events, NewLastId} ->
            process_events(Events, State),
            self() ! poll,
            {noreply, State#{last_event_id => NewLastId}};
        {error, queue_not_found} ->
            logger:warning("Event queue expired, re-registering"),
            self() ! register_queue,
            {noreply, State#{queue_id => undefined, last_event_id => -1}};
        {error, Reason} ->
            logger:error("Poll error: ~p, retrying in 5s", [Reason]),
            erlang:send_after(5000, self(), poll),
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%% Internal

auth_headers(#{email := Email, api_key := ApiKey}) ->
    Creds = base64:encode(iolist_to_binary([Email, ":", ApiKey])),
    [{<<"Authorization">>, iolist_to_binary([<<"Basic ">>, Creds])}].

register_queue(#{base_url := BaseUrl} = State) ->
    Url = iolist_to_binary([BaseUrl, ?REGISTER_URL]),
    Body = <<"event_types=[\"message\"]&all_public_streams=true">>,
    Headers = [{<<"Content-Type">>, <<"application/x-www-form-urlencoded">>} | auth_headers(State)],
    case hackney:request(post, Url, Headers, Body, [with_body]) of
        {ok, 200, _RespHeaders, RespBody} ->
            Json = jiffy:decode(RespBody, [return_maps]),
            QueueId = maps:get(<<"queue_id">>, Json),
            LastEventId = maps:get(<<"last_event_id">>, Json),
            {ok, QueueId, LastEventId};
        {ok, Status, _RespHeaders, RespBody} ->
            {error, {http, Status, RespBody}};
        {error, Reason} ->
            {error, Reason}
    end.

poll_events(State, QueueId, LastEventId) ->
    #{base_url := BaseUrl} = State,
    Url = iolist_to_binary([
        BaseUrl, ?EVENTS_URL,
        <<"?queue_id=">>, hackney_url:urlencode(QueueId),
        <<"&last_event_id=">>, integer_to_binary(LastEventId)
    ]),
    Headers = auth_headers(State),
    %% Long poll — 90s timeout
    case hackney:request(get, Url, Headers, <<>>, [with_body, {recv_timeout, 90000}]) of
        {ok, 200, _RespHeaders, RespBody} ->
            Json = jiffy:decode(RespBody, [return_maps]),
            Events = maps:get(<<"events">>, Json, []),
            NewLastId = lists:foldl(fun(E, Acc) ->
                max(maps:get(<<"id">>, E, Acc), Acc)
            end, LastEventId, Events),
            {ok, Events, NewLastId};
        {ok, 400, _RespHeaders, RespBody} ->
            case jiffy:decode(RespBody, [return_maps]) of
                #{<<"code">> := <<"BAD_EVENT_QUEUE_ID">>} ->
                    {error, queue_not_found};
                _ ->
                    {error, {http, 400, RespBody}}
            end;
        {ok, Status, _RespHeaders, RespBody} ->
            {error, {http, Status, RespBody}};
        {error, Reason} ->
            {error, Reason}
    end.

process_events(Events, State) ->
    lists:foreach(fun(Event) -> process_event(Event, State) end, Events).

process_event(#{<<"type">> := <<"message">>, <<"message">> := Msg}, State) ->
    process_message(Msg, State);
process_event(#{<<"type">> := <<"heartbeat">>}, _State) ->
    ok;
process_event(_Event, _State) ->
    ok.

process_message(Msg, #{base_url := BaseUrl, channel_filter := Filter}) ->
    Type = maps:get(<<"type">>, Msg, <<>>),
    case Type of
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
                    Plaintext = html_to_text(iolist_to_binary(BaseUrl), Content),
                    Text = iolist_to_binary([
                        <<"#">>, Channel, <<" / ">>, Topic, <<"\n">>,
                        Sender, <<": ">>, Plaintext, <<"\n\n">>,
                        Url
                    ]),
                    signal_sender:send(binary_to_list(Text));
                false ->
                    ok
            end;
        _ ->
            ok
    end.

should_forward(_StreamId, []) ->
    true;
should_forward(StreamId, Filter) ->
    lists:member(StreamId, Filter).

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
