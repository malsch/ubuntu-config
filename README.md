# ubuntu-config

Initialization scripts and configuration for a small single-box Ubuntu 26.04 VPS
(Hetzner Cloud), set up to run an AI agent behind a mesh VPN (or maybe independently).

| File | Run as | What it does |
|---|---|---|
| **📁 [`init-vps/`](init-vps)** | | **Server setup: hardening, users, Docker, mise, NetBird.** → [README](init-vps/README.md) |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`setup-hetzner-vps/`](init-vps/setup-hetzner-vps) | `root` (on the server) | Ansible playbook, the main setup. UFW, SSH hardening, fail2ban, admin account, swap, unattended upgrades, Docker, NetBird, mise. Idempotent. |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`setup-agent-user.sh`](init-vps/setup-agent-user.sh) | `root` | Creates the unprivileged `aiagent` account (groups, `/opt` dirs, mise). Run after the main script. Idempotent. |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ [`git-based-docker-compose-deployment.sh`](init-vps/git-based-docker-compose-deployment.sh) | `aiagent` | Sets up bare repos + `post-receive` hooks so that `git push` deploys a compose stack. Not tested and not related to other parts here. |
| **📁 [`init-hermes-agent/`](init-hermes-agent)** | | **[Hermes](https://hermes-agent.nousresearch.com/) + the [hermes-webui](https://github.com/nesquena/hermes-webui) frontend.** → [README](init-hermes-agent/README.md) |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`setup-hermes.sh`](init-hermes-agent/setup-hermes.sh) | `aiagent` | Installation walkthrough — dependencies, the Hermes installer, Playwright's Chromium libraries, gateway and webui as systemd user services. Read and adapt; do not pipe to bash. |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`config.yaml.template`](init-hermes-agent/config.yaml.template) | — | A full worked `~/.hermes/config.yaml`: model provider, trimmed toolsets and skills, memory, guardrails, Docker-backed terminal. |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`Dockerfile`](init-hermes-agent/Dockerfile) | — | Sandbox image (`mise-dev`) for the agent's terminal tool. |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ [`.dockerignore`](init-hermes-agent/.dockerignore) | — | Keeps `.git` and secrets out of build contexts. |
| **📁 [`init-caddy/`](init-caddy)** | | **Reverse proxy in front of the web UI, bound to the VPN address only.** → [README](init-caddy/README.md) |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`Caddyfile`](init-caddy/Caddyfile) | — | Two sites, both proxying to `127.0.0.1:8787`. Contains placeholders. |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ [`docker-compose.yml`](init-caddy/docker-compose.yml) | `aiagent` | Runs Caddy with `network_mode: host` and persistent TLS volumes. |
| **📁 [`cheatsheets/`](cheatsheets)** | | **CLI references** |
| &nbsp;&nbsp;&nbsp;&nbsp;├─ [`docker-compose.md`](cheatsheets/docker-compose.md) | — | Generic Compose reference — lifecycle, logs, shelling in, volume and port gotchas. |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ [`hermes-cli.md`](cheatsheets/hermes-cli.md) | — | `hermes` subcommands and in-session slash commands. |
| **📁 [`dotfiles/`](dotfiles)** | | **Per-user shell, git identity and mise settings.** → [README](dotfiles/README.md) |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ [`install.sh`](dotfiles/install.sh) | each user | Links the dotfiles into your home directory. Idempotent. |

These are working notes as much as they are scripts. The `init-vps/setup-hetzner-vps`
playbook runs end to end unattended; the other files are a mix of runnable scripts,
templates, and copy-paste command sequences. Read before running — several of
them contain placeholders (`<PASSWORD>`, `<private-vpn-ip>`, `<your-domain.example>`)
that must be filled in first.

## Design in one paragraph

Nothing is exposed to the public internet except SSH. The box joins a
[NetBird](https://netbird.io/) WireGuard mesh, Caddy binds only to the tunnel
address, and the agent's web UI listens on `127.0.0.1:8787`.

Two non-root accounts exist: an admin (sudo) and `aiagent` (no sudo, but in the `docker`
group — which is root-equivalent in practice, so treat it as a guard against
accidents rather than a sandbox). Inbound traffic is filtered twice, by the
Hetzner Cloud Firewall and by UFW.

## Related

- [`dotfiles/`](dotfiles) — shell, git and mise configuration for these machines
