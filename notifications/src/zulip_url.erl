-module(zulip_url).
-export([narrow_url/4]).

%% Construct a Zulip narrow URL for a message in a channel/topic.
%% https://zulip.com/api/zulip-urls
-spec narrow_url(binary(), integer(), binary(), integer()) -> binary().
narrow_url(BaseUrl, StreamId, Topic, MessageId) ->
    EncodedTopic = encode_topic(Topic),
    iolist_to_binary([
        BaseUrl,
        <<"/#narrow/channel/">>,
        integer_to_binary(StreamId),
        <<"/topic/">>,
        EncodedTopic,
        <<"/with/">>,
        integer_to_binary(MessageId)
    ]).

%% Zulip's topic encoding: like percent-encoding but with '.' instead of '%'.
encode_topic(Topic) ->
    encode_topic(Topic, <<>>).

encode_topic(<<>>, Acc) ->
    Acc;
encode_topic(<<C, Rest/binary>>, Acc) when
    (C >= $a andalso C =< $z) orelse
    (C >= $A andalso C =< $Z) orelse
    (C >= $0 andalso C =< $9) orelse
    C =:= $- orelse C =:= $_ ->
    encode_topic(Rest, <<Acc/binary, C>>);
encode_topic(<<$., Rest/binary>>, Acc) ->
    encode_topic(Rest, <<Acc/binary, ".2E">>);
encode_topic(<<$%, Rest/binary>>, Acc) ->
    encode_topic(Rest, <<Acc/binary, ".25">>);
encode_topic(<<$ , Rest/binary>>, Acc) ->
    encode_topic(Rest, <<Acc/binary, ".20">>);
encode_topic(<<$(, Rest/binary>>, Acc) ->
    encode_topic(Rest, <<Acc/binary, ".28">>);
encode_topic(<<$), Rest/binary>>, Acc) ->
    encode_topic(Rest, <<Acc/binary, ".29">>);
encode_topic(<<C, Rest/binary>>, Acc) ->
    Hi = hex(C bsr 4),
    Lo = hex(C band 16#0F),
    encode_topic(Rest, <<Acc/binary, $., Hi, Lo>>).

hex(N) when N < 10 -> $0 + N;
hex(N) -> $A + N - 10.
