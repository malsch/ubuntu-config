# init-vps

Root-level setup for a fresh Hetzner server running Ubuntu 26.04 LTS, plus an
optional git-push deployment mechanism.

| File | Run as | What it does |
|---|---|---|
| [`setup-hetzner-vps/`](setup-hetzner-vps) | `root` (Ansible, runs on the server) | The main setup playbook. Idempotent. |
| [`setup-agent-user.sh`](setup-agent-user.sh) | `root` (via `sudo`) | Creates the unprivileged `aiagent` account. Run after the main script. Idempotent. |
| [`git-based-docker-compose-deployment.sh`](git-based-docker-compose-deployment.sh) | `aiagent` | Bare repos + `post-receive` hooks, so `git push` deploys. Untested, and independent of the rest of this repo. |

## `setup-hetzner-vps/`

An Ansible playbook that runs on the server itself and sets it up
(`hosts: localhost`): UFW, SSH hardening, fail2ban, unattended upgrades, an admin account,
swap, journald size cap, Docker, NetBird, and mise. Usage is in its
[README](setup-hetzner-vps/README.md):

```bash
cd init-vps/setup-hetzner-vps && ./run.sh
```

## `setup-agent-user.sh`

Run after the `setup-hetzner-vps` playbook, from the admin account (root login is off by
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
