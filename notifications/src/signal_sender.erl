-module(signal_sender).
-behaviour(gen_server).
-export([start_link/0, send/1]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

send(Message) ->
    gen_server:cast(?MODULE, {send, Message}).

init([]) ->
    {ok, CliPath} = application:get_env(zulip_signal, signal_cli_path),
    {ok, Account} = application:get_env(zulip_signal, signal_account),
    {ok, GroupId} = application:get_env(zulip_signal, signal_group_id),
    {ok, #{cli_path => CliPath, account => Account, group_id => GroupId}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send, Message}, #{cli_path := CliPath, account := Account, group_id := GroupId} = State) ->
    %% Escape single quotes in message for shell safety
    Escaped = re:replace(Message, "'", "'\\''", [global, {return, list}]),
    Cmd = lists:flatten(io_lib:format("~s -u ~s send -g '~s' -m '~s' 2>&1",
        [CliPath, Account, GroupId, Escaped])),
    logger:info("Running: ~s", [Cmd]),
    Output = os:cmd(Cmd),
    logger:info("signal-cli output: ~s", [Output]),
    {noreply, State}.
