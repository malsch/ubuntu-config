# Hermes — Most Important CLI Commands

The binary is `hermes`.

> The authoritative list is always `hermes --help` and `hermes <command> --help`.
> Plugin- and provider-supplied subcommands only appear once that plugin/provider is active.

## Setup & configuration

```bash
hermes setup              # full interactive setup wizard (provider, tools, gateway, etc.)
hermes setup --portal     # one-step OAuth + Tool Gateway via Nous Portal
hermes model              # choose LLM provider + model (the key setup step)
hermes tools              # configure which tools/toolsets are enabled
hermes config set <k> <v> # set an individual config value
```

## Running the agent

```bash
hermes                    # interactive chat (classic CLI)
hermes --tui              # launch the newer TUI instead
hermes dashboard
hermes gateway            # run/manage the messaging gateway (Telegram, Discord, Slack, …)
hermes gateway setup      # interactive per-platform gateway config
hermes gateway stop       # stop the current profile's gateway
```

## Diagnostics & health

```bash
hermes status             # current status of components, API keys, gateway PID/uptime
hermes status --deep      # verbose: Python env, installed packages, system info
hermes doctor             # diagnose problems
hermes doctor --fix       # attempt automatic fixes
hermes dump               # dump current setup (useful for "something broke" reports)
```

## Messaging (one-shot, no gateway loop)

```bash
hermes send --to <target> "message text"     # send a one-off message via a platform
hermes send --to <target> --file <path>      # send a file
echo "msg" | hermes send --to <target>       # send from stdin
hermes send --list [platform]                # list configured targets
```

`<target>` formats: `platform`, `platform:chat_id`, `platform:chat_id:thread_id`, or
`platform:#channel-name`. For bot-token platforms (Telegram, Discord, Slack, Signal,
SMS, WhatsApp Cloud API) no running gateway is required.

## Sessions, checkpoints & maintenance

```bash
hermes sessions           # browse, export, prune, rename, delete past sessions
hermes checkpoints        # status of the shadow git store (backs in-session /rollback)
hermes checkpoints prune --retention-days 3   # cleanup old checkpoints
hermes update             # update Hermes to the latest version
```

## Discovering everything else

```bash
hermes --help             # full top-level command list
hermes <command> --help   # flags/subcommands for a specific command
hermes completion bash    # (or zsh) install shell completions
```

## In-session slash commands (while chatting)

Once you're in a chat/gateway session, useful slashes include:
`/help`, `/model <name>`, `/new`, `/stop`, `/status`, `/approve`, `/deny`, `/verbose`,
`/rollback`. Run `/help` in-session for the authoritative, up-to-date list.

More at https://hermes-agent.nousresearch.com/docs/user-guide/messaging/
