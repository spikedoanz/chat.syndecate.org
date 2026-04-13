# Zulip → Signal notification bridge

Erlang/OTP service that polls Zulip for messages and forwards them to a Signal group chat via signal-cli.

## Setup

```bash
cd notifications
cp config/sys.config.example config/sys.config
# Edit sys.config with your credentials
nix develop
rebar3 compile
```

### Zulip bot

1. Go to Settings → Bots → Add a new bot
2. Type: **Generic bot**
3. Note the bot email and API key

### Signal

1. Register signal-cli with a phone number: `signal-cli -u +1NUMBER register`
2. Get your group ID: `signal-cli -u +1NUMBER listGroups`
3. The group ID is a base64 string like `rZdHNSA+69L58knk9HGewWn9QgR1p+xkJOijwuoZL6I=`

### sys.config

Fill in `config/sys.config`:
- `zulip_email` — bot email (e.g. `cookie-bot@chat.syndecate.org`)
- `zulip_api_key` — bot API key
- `signal_account` — phone number registered with signal-cli
- `signal_group_id` — base64 group ID
- `channel_filter` — list of stream IDs to forward, or `[]` for all

## Usage

### Live mode (stream to terminal)

```bash
erl -pa _build/default/lib/*/ebin -config config/sys -eval 'zulip_signal_cli:main().'
```

Output:

```
infra/server-updates
Alice: rebooted the node

https://chat.syndecate.org/#narrow/channel/11-infra/topic/server-updates/with/3705
```

### Production (forward to Signal)

```bash
rebar3 release
_build/default/rel/zulip_signal/bin/zulip_signal foreground
```

Or with nix:

```bash
nix build
result/bin/zulip_signal foreground
```
