# init-vps

Root-level setup for a fresh Hetzner server running Ubuntu 26.04 LTS, plus an
optional git-push deployment mechanism.

| File | Run as | What it does |
|---|---|---|
| [`setup-hetzner-vps.sh`](setup-hetzner-vps.sh) | `root` | The main build script. Idempotent. |
| [`setup-agent-user.sh`](setup-agent-user.sh) | `root` (via `sudo`) | Creates the unprivileged `aiagent` account. Run after the main script. Idempotent. |
| [`git-based-docker-compose-deployment.sh`](git-based-docker-compose-deployment.sh) | `aiagent` | Bare repos + `post-receive` hooks, so `git push` deploys. Untested, and independent of the rest of this repo. |

## `setup-hetzner-vps.sh`

Run once as root on a freshly provisioned server. Re-running is safe.

```bash
scp init-vps/setup-hetzner-vps.sh root@<server-ip>:/root/
```

```bash
ssh root@<server-ip> 'bash /root/setup-hetzner-vps.sh'
```

Edit the configuration block at the top first — at minimum `NETBIRD_SETUP_KEY`,
`ADMIN_USERNAME`, and `ADMIN_PASSWORD`.

It covers, in 14 sections:

- **Security** — UFW (default deny inbound, tunnel traffic trusted), SSH
  hardening (key-only, no root login), fail2ban, unattended security upgrades
  with 4am reboots.
- **Users** — an admin account with passwordless sudo, seeded with root's SSH
  key and given a git commit identity.
- **System** — timezone, swap file, journald size cap.
- **Packages** — Docker Engine + Compose (with log rotation and `live-restore`),
  NetBird, mise, git, syncthing, htop, rsync.

**Before you close the root session**, open a new terminal and confirm you can
SSH in as the admin user — root login is disabled by the time the script
finishes. The script's closing message lists the remaining manual steps
(Hetzner Cloud Firewall rules, `netbird status -d`).

## `setup-agent-user.sh`

Run after `setup-hetzner-vps.sh`, from the admin account (root login is off by
then):

```bash
scp init-vps/setup-agent-user.sh <admin>@<server-ip>:~/
```

```bash
ssh <admin>@<server-ip> 'sudo bash ~/setup-agent-user.sh'
```

Creates `aiagent` without sudo, seeded with root's SSH key, and gives it a git
commit identity, `/opt/stacks` and `/opt/repos`, mise activation, and
membership in the `docker` and `adm` groups. Its closing message covers the
optional syncthing setup.

## `git-based-docker-compose-deployment.sh`

Run as `aiagent`, not root. For each project listed in `GIT_DEPLOY_PROJECTS` it
creates a bare repo under `/opt/repos/<name>.git`, a working clone under
`/opt/stacks/<name>`, and a `post-receive` hook. Pushing to the bare repo
fast-forwards the clone and runs `docker compose down; docker compose up -d`
inside it — a push is the deploy.

```bash
git remote add prod aiagent@<server-ip>:/opt/repos/hermes.git
```

The hook is fast-forward-only: if the server clone has diverged or has
uncommitted changes, the deploy fails loudly instead of discarding work. It runs
the deploy command through `mise exec`, so a project's `mise.toml` applies even
though hooks are non-interactive.
