-module(zulip_signal_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => signal_sender,
          start => {signal_sender, start_link, []},
          restart => permanent,
          type => worker},
        #{id => zulip_poller,
          start => {zulip_poller, start_link, []},
          restart => permanent,
          type => worker}
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 60}, Children}}.
