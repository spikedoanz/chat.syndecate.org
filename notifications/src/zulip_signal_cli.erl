-module(zulip_signal_cli).
-export([main/0]).

%% Single process: polls Zulip, prints formatted messages to stdout,
%% sends to Signal, and logs status as JSONL.

main() ->
    application:ensure_all_started(hackney),
    application:ensure_all_started(jiffy),
    application:load(zulip_signal),
    {ok, BaseUrl} = application:get_env(zulip_signal, zulip_url),
    {ok, Email} = application:get_env(zulip_signal, zulip_email),
    {ok, ApiKey} = application:get_env(zulip_signal, zulip_api_key),
    {ok, Filter} = application:get_env(zulip_signal, channel_filter),
    {ok, CliPath} = application:get_env(zulip_signal, signal_cli_path),
    {ok, Account} = application:get_env(zulip_signal, signal_account),
    {ok, GroupId} = application:get_env(zulip_signal, signal_group_id),
    State = #{
        base_url => BaseUrl,
        email => Email,
        api_key => ApiKey,
        channel_filter => Filter,
        cli_path => CliPath,
        signal_account => Account,
        signal_group_id => GroupId
    },
    log_event(<<"startup">>, [{<<"zulip">>, list_to_binary(BaseUrl)},
                               {<<"email">>, list_to_binary(Email)}]),
    io:format("Connecting to ~s as ~s...~n", [BaseUrl, Email]),
    print_group_link(CliPath, Account, GroupId),
    loop_register(State).

print_group_link(CliPath, Account, GroupId) ->
    Cmd = lists:flatten(io_lib:format("~s -u ~s listGroups -d 2>/dev/null", [CliPath, Account])),
    Output = os:cmd(Cmd),
    case re:run(Output, "Id: " ++ re:replace(GroupId, "[+/=]", "\\\\&", [global, {return, list}]) ++ ".*?Link: (https://signal\\.group/[^ \\n]+)", [{capture, [1], list}, dotall]) of
        {match, [Link]} ->
            io:format("\e[1;36mJoin Signal group: ~s\e[0m~n~n", [Link]);
        nomatch ->
            io:format("\e[33mWarning: No group link found. Enable it with:\e[0m~n"
                      "  signal-cli -u ~s updateGroup -g '~s' --set-permission-add-member every-member --link enabled~n~n",
                      [Account, GroupId])
    end.

loop_register(State) ->
    case register_queue(State) of
        {ok, QueueId, LastEventId} ->
            log_event(<<"queue_registered">>, [{<<"queue_id">>, QueueId}]),
            io:format("Listening for messages (queue ~s)~n~n", [QueueId]),
            loop_poll(State, QueueId, LastEventId);
        {error, Reason} ->
            log_event(<<"queue_register_failed">>, [{<<"error">>, iolist_to_binary(io_lib:format("~p", [Reason]))}]),
            io:format("Registration failed: ~p, retrying in 5s~n", [Reason]),
            timer:sleep(5000),
            loop_register(State)
    end.

loop_poll(State, QueueId, LastEventId) ->
    case poll_events(State, QueueId, LastEventId) of
        {ok, Events, NewLastId} ->
            handle_events(Events, State),
            loop_poll(State, QueueId, NewLastId);
        {error, queue_not_found} ->
            log_event(<<"queue_expired">>, []),
            io:format("~nQueue expired, re-registering...~n", []),
            loop_register(State);
        {error, Reason} ->
            log_event(<<"poll_error">>, [{<<"error">>, iolist_to_binary(io_lib:format("~p", [Reason]))}]),
            io:format("Poll error: ~p, retrying in 5s~n", [Reason]),
            timer:sleep(5000),
            loop_poll(State, QueueId, LastEventId)
    end.

handle_events(Events, State) ->
    lists:foreach(fun(E) -> handle_event(E, State) end, Events).

handle_event(#{<<"type">> := <<"message">>, <<"message">> := Msg}, State) ->
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
                    Resolved = resolve_uploads(iolist_to_binary(BaseUrl), Content),
                    Stripped = strip_html(Resolved),
                    Text = iolist_to_binary([
                        <<"#">>, Channel, <<" / ">>, Topic, <<"\n">>,
                        Sender, <<": ">>, Stripped, <<"\n\n">>,
                        Url
                    ]),
                    %% Print to stdout
                    io:format("~ts~n~n", [Text]),
                    %% Send to Signal
                    send_signal(Text, State);
                false ->
                    ok
            end;
        _ ->
            ok
    end;
handle_event(_, _) ->
    ok.

send_signal(Text, #{cli_path := CliPath, signal_account := Account, signal_group_id := GroupId}) ->
    Cmd = lists:flatten(io_lib:format("~s -u ~s send -g '~s' --message-from-stdin 2>&1",
        [CliPath, Account, GroupId])),
    Port = open_port({spawn, Cmd}, [exit_status, use_stdio, binary, stream]),
    port_command(Port, Text),
    port_close(Port),
    %% Collect exit status
    receive
        {Port, {exit_status, 0}} ->
            log_event(<<"signal_sent">>, [{<<"status">>, <<"ok">>}]);
        {Port, {exit_status, Code}} ->
            log_event(<<"signal_error">>, [{<<"exit_code">>, Code}])
    after 30000 ->
            log_event(<<"signal_error">>, [{<<"error">>, <<"timeout">>}])
    end.

%% JSONL logging to stderr
log_event(Event, Fields) ->
    Ts = erlang:system_time(second),
    Base = [{<<"ts">>, Ts}, {<<"event">>, Event} | Fields],
    Line = jiffy:encode({Base}),
    io:format(standard_error, "~s~n", [Line]).

should_forward(_StreamId, []) -> true;
should_forward(StreamId, Filter) -> lists:member(StreamId, Filter).

strip_html(Html) ->
    re:replace(Html, <<"<[^>]*>">>, <<>>, [global, {return, binary}]).

resolve_uploads(BaseUrl, Text) ->
    re:replace(Text, <<"/user_uploads/">>,
        <<BaseUrl/binary, "/user_uploads/">>,
        [global, {return, binary}]).

%% HTTP helpers

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
