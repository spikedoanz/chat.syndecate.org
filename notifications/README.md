# Zulip → Signal notification bridge

Erlang/OTP service that polls Zulip for messages and forwards them to a Signal group chat via signal-cli. Solves the mobile Zulip encryption/notification trade-off by routing through Signal.

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- A Zulip bot account with read permissions
- A phone number for signal-cli registration

## Build

```bash
cd notifications
nix develop
rebar3 compile
```

## Setup

### 1. Zulip bot

1. Go to Settings → Bots → Add a new bot
2. Type: **Generic bot**
3. Note the bot email and API key

### 2. Signal account

```bash
nix develop

# Register (use --voice if SMS doesn't arrive)
signal-cli -u +1NUMBER register
signal-cli -u +1NUMBER verify CODE

# Set a profile name (required for group messaging)
signal-cli -u +1NUMBER updateProfile --given-name 'Syndecate' --family-name 'Bot'

# Create group and add members
signal-cli -u +1NUMBER updateGroup -n 'Syndecate Chat Notifications' -m +1MEMBER

# Get group ID
signal-cli -u +1NUMBER listGroups -d

# Enable join link
signal-cli -u +1NUMBER updateGroup -g 'GROUP_ID' --set-permission-add-member every-member --link enabled

# Test
signal-cli -u +1NUMBER send -g 'GROUP_ID' -m 'test'
```

### 3. Configuration

```bash
cp config/sys.config.example config/sys.config
```

Fill in `config/sys.config`:
- `zulip_email` — bot email (e.g. `notification-bot@chat.syndecate.org`)
- `zulip_api_key` — bot API key
- `signal_account` — phone number registered with signal-cli
- `signal_group_id` — base64 group ID
- `channel_filter` — list of stream IDs to forward, or `[]` for all

## Run

```bash
erl -pa _build/default/lib/*/ebin -config config/sys -eval 'zulip_signal_cli:main().'
```

This prints formatted messages to stdout and sends them to Signal. JSONL status logs go to stderr.

Stdout:
```
#99-infra / general chat
spike: hello world

https://chat.syndecate.org/#narrow/channel/11/topic/general.20chat/with/3760
```

Stderr:
```json
{"ts":1776103429,"event":"startup","zulip":"https://chat.syndecate.org","email":"notification-bot@chat.syndecate.org"}
{"ts":1776103431,"event":"queue_registered","queue_id":"..."}
{"ts":1776103438,"event":"signal_sent","status":"ok"}
```

## Deploy

On the target server:

```bash
nix develop
rebar3 compile
# Transfer sys.config and signal-cli data (see below)
erl -pa _build/default/lib/*/ebin -config config/sys -eval 'zulip_signal_cli:main().'
```

### Transferring secrets

The `config/sys.config` and `~/.local/share/signal-cli/` directory contain secrets (API keys, Signal identity keys). Transfer them securely using [magic-wormhole](https://github.com/magic-wormhole/magic-wormhole):

```bash
# On your local machine — tar up the secrets
tar czf /tmp/zulip-signal-secrets.tar.gz \
  -C ~/R/chat.syndecate.org/notifications config/sys.config \
  -C ~ .local/share/signal-cli

# Send
wormhole send /tmp/zulip-signal-secrets.tar.gz

# On the target server — receive and extract
wormhole receive
tar xzf zulip-signal-secrets.tar.gz -C ~/notifications config/sys.config
tar xzf zulip-signal-secrets.tar.gz -C ~ .local/share/signal-cli

# Clean up
rm /tmp/zulip-signal-secrets.tar.gz
```
