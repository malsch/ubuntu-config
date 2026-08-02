# Hermes — Docker Compose Cheat Sheet

Run all commands from the directory containing your `docker-compose.yml`.
The service is named `hermes`.

## Starting & stopping

```bash
docker compose pull           # Updating: fetch the latest image
docker compose up -d          # start in the background (detached)
docker compose up -d --pull always # updating and starting in a single step
docker compose down           # stop and remove the container
docker compose stop           # stop without removing
docker compose start          # start an existing stopped container
docker compose restart        # restart (e.g. after editing .env)
```

## Debugging

```bash
docker compose exec hermes sh     # shell in (try bash if sh isn't present)
```

## Watching it

```bash
docker compose logs -f                # follow live logs
docker compose logs -f --tail 100     # last 100 lines, then follow
docker compose ps                     # running? which ports?
docker stats hermes                    # live CPU / memory / network usage
```

## Get a shell inside

```bash
docker compose exec hermes sh          # interactive shell (try bash if sh fails)
docker compose exec hermes ls /opt/data    # peek at the mounted data dir
docker compose exec hermes env             # inspect the env it's actually running with
```

## Notes for this setup

- **`restart: unless-stopped`** — the container comes back automatically after a reboot or crash, *unless* you explicitly ran `stop` or `down`. After `down`, you must `up -d` again.
- **Config** lives at `~/.hermes/.env`. Editing it requires `restart` (or `up -d`) to take effect — changes aren't picked up live.
- **Data** lives at `~/.hermes`. It persists outside the container, so `down` won't wipe it; it survives recreation.

# Hermes — Most Important CLI Commands

The in-image binary is `hermes`. Since your container runs `gateway run`, invoke any of
these from the host as:

```bash
docker compose exec hermes hermes <command>
```

(Or drop into a shell first with `docker compose exec hermes sh` and run `hermes …` directly.)

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
