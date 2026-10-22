# ubuntu-config

Agentic AI makes it much, much easier to run any type of software. If an agent
runs amok, or just installs malware and poisoned packages, this is a huge
security risk. This repository sets up a linux server configuration that guards against such
risks, meant for personal (private) use. This implies, of course, some
[security trade-offs](security-architecture.md#known-trade-offs) any admin who uses this should be aware of.

The Ansible playbooks in this repo set up a fresh Ubuntu 26.04 LTS server on Hetzner or
Oracle Cloud ([Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)),
64-bit x86 (`x86_64`/`amd64`) or ARM (`aarch64`/`arm64`). They run on the server
itself, or [from your computer over SSH](#running-from-your-computer), and can
safely be run more than once.

The result is a ready-to-use linux server configuration (not only) for AI agents. You get:

- a configuration that is highly secure on multiple layers (networking via
  NetBird, isolated environments, trusted programs), see
  [security-architecture.md](security-architecture.md)
- a personal admin account (bash or zsh), and further users can be added with a single
  playbook
- a shared folder, `/srv/shared`, for files several users work on
- a very opinionated (and certainly incomplete) set of tools: Docker and
  everyday [command-line tools](roles/install_essential_packages/tasks/main.yml)
  with the server setup, plus mise,
  Syncthing, ffmpeg and more installed with an
  [optional playbook](MAINTENANCE.md#install-apps-playbookyml-apps)
- settings for a swap file, the timezone and limits on log sizes

Unrelated material, also in this repository (keep it or delete it?):

- [`cheatsheets/`](cheatsheets): CLI references for Docker Compose and Hermes.

## Requirements

- Server: Ubuntu 26.04 cloud image, root login via SSH key
  - Optional: [`cloud-init`](cloud-init) is an example cloud config to paste
    when creating the server. It sets the admin user name and the host name
    (console: `<admin-user-name>@<hostname>`) before the server starts, and
    the timezone. Replace its placeholders first.
- Cloud firewall (Hetzner Cloud Firewall, or Oracle's Security List / Network
  Security Group): inbound 22/tcp, plus 80/443/tcp and 51820/udp as needed.
  Later, you can login via NetBird and close 22/tcp via the provider's cloud firewall (or just keep your home IP open) to turn off SSH connection attempts.
- NetBird account with a [setup key](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys) (free, get it first)

## Installation

The most intuitive way is to run the playbooks on the server itself, our default configuration. Log in on a fresh server with the account your provider gives you (Hetzner: `root`, Oracle:
`ubuntu`). Install `ansible`, and clone this repo to `/opt/ubuntu-config`:

```bash
sudo apt update && sudo apt install -y ansible git
git config --global --add safe.directory /opt/ubuntu-config
sudo git clone --depth 1 https://github.com/malsch/ubuntu-config.git /opt/ubuntu-config
```

Alternatively, run the playbooks ***from your own computer over SSH***: install Ansible and clone this repository on your machine (any folder), then add `-i <server-ip>, -u <user>` to the commands to connect remotely (see
[Running from your computer](#running-from-your-computer)).

## Running Playbooks

| Playbook | What it does | When |
|---|---|---|
| [`vps-init-playbook.yml`](#vps-init-playbookyml-server-setup) | Server setup: firewall, NetBird, updates, admin account, Docker, … | First; again after changes to this repository |
| [`vps-init-ssh-setup-playbook.yml`](#vps-init-ssh-setup-playbookyml-ssh-hardening-with-role-linux_ssh_setup) | SSH hardening: key-only logins, no root login | Once, after logging in as the admin |
| [`install-apps-playbook.yml`](MAINTENANCE.md#install-apps-playbookyml-apps) | Apps for your work: build tools, ffmpeg, mise, … | After the setup; again when its list changes |
| [`create-user-playbook.yml`](MAINTENANCE.md#create-user-playbookyml-add-more-users) | One more user account, e.g. for the AI agent | Any time |

Run them from the repository folder, with `sudo`, through
`run-ansible-logged.sh` (for logging in folder `logs/`), followed by the playbook:

```bash
cd /opt/ubuntu-config
sudo ./run-ansible-logged.sh vps-init-playbook.yml
```

`vps-init-playbook.yml` will create a new admin user.

***Log out and log in again as the new admin***, who must run the
[SSH hardening](#vps-init-ssh-setup-playbookyml-ssh-hardening-with-role-linux_ssh_setup). Then

```bash
cd /opt/ubuntu-config
sudo ./run-ansible-logged.sh vps-init-ssh-setup-playbook.yml
sudo ./run-ansible-logged.sh install-apps-playbook.yml              # optional
```

The apps playbook is optional; see [MAINTENANCE.md](MAINTENANCE.md#install-apps-playbookyml-apps).

It is safe to run a playbook more than once. Re-runs only change what differs from the playbook; users and data are never deleted. For example, answering `no` to sudo removes a user's sudo rights again, the role's firewall rules are applied again (rules you added by hand stay), and packages are upgraded.

To update the repo before re-runs:

```bash
cd /opt/ubuntu-config && sudo git pull
```

**Options.** Anything after the playbook name is passed to `ansible-playbook`:

| Option | What it does | Example |
|---|---|---|
| `--tags` | Runs only the roles with these tags (see the role tables below) | `--tags "docker,security"` |
| `-e name=value` | Answers a question without asking, or overrides a role setting from its `defaults/main.yml` | `-e timezone=UTC` |
| `--check --diff` | Dry run: shows what would change, with the changed lines of each file, but changes nothing. Tasks that depend on an earlier change (e.g. a package not yet installed) can fail or be skipped in a dry run | `--check --diff` |
| `-v` | More output, for troubleshooting (`-vvv` for even more) | `-v` |

### Running from your computer

After installing `ansible` locally and cloning this repo on your own computer, you can connect to your server (or all your servers) and execute local playbooks remotely. Your computer needs SSH access to the remote servers. The steps are the same (no local sudo needed), with a few additional parameters:

- `-i` names the server (its IP or `~/.ssh/config` name, with
a trailing comma)
- `-u` names the account to login with.
- Add `-K`, which asks for the remote sudo password (not needed with passwordless sudo)

```bash
./run-ansible-logged.sh vps-init-playbook.yml -i <ip-address>, -u root # or ubuntu
```
At this point you can use a private connection via NetBird (if your computer
is a NetBird peer too), and potentially disallow port 22 (SSH) in your provider's firewall. Login again as the new user (with option `-K`) to finish the setup.

```bash
./run-ansible-logged.sh vps-init-ssh-setup-playbook.yml -i <private-address>, -u <new-admin-account> -K
```

```bash
./run-ansible-logged.sh install-apps-playbook.yml -i <private-address>, -u <new-admin-account> -K               # optional
```

#### Several servers

List them in `servers.ini`: copy [`servers.example.ini`](servers.example.ini)
(`servers.ini` is git-ignored). One line per server: its (private) IP or `~/.ssh/config`
name, and the account to log in with:

```ini
server-abc1  ansible_user=root
server-abc2  ansible_user=ubuntu
```

Then use `-i servers.ini` instead of `-i <ip-address>, -u <account>`:

```bash
./run-ansible-logged.sh install-apps-playbook.yml -i servers.ini
```

- **All listed servers at once.** The questions are asked once, and the answers
  apply to every server, so the NetBird setup key must be a reusable one. `-K`
  asks for the sudo password once, for all servers.
- **One server only:** add `--limit server-abc1`.

## The Playbooks in Detail

### `vps-init-playbook.yml`: server setup

It first asks a few questions; nothing is stored:

- admin username and password (required; on later runs, empty keeps the current one);
- whose SSH keys the admin gets: `me` (default) = the public SSH keys from the account running this;
- login shell: `bash` (default, Ubuntu's standard) or `zsh`;
- how sudo behaves: by default without a password. The admin is also in
  the `docker` group, which gives root without a password, so the sudo password
  guards against mistakes, not against someone holding your SSH key. Other options:
  - ask for the admin password, then not again for 24 hours per login session;
  - ask every time (answer `0` hours);
- timezone (default Europe/Berlin);
- NetBird [setup key](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys)
  (needed on the first run; later, empty keeps the existing connection).

Then it runs these roles, in this order (tags in the second column):

| Role | Tags | What it does |
|---|---|---|
| `linux_time_configuration` | `time` | Timezone |
| `netbird` | `netbird` | Installs NetBird from its apt repository (apt-pinned to it), joins the mesh, and reads its WireGuard port and tunnel interface for the firewall roles |
| `firewall_ufw` | `security`, `firewall`, `ufw` | Host firewall: default deny, SSH/HTTP(S)/NetBird open, NetBird tunnel trusted. Skipped on Oracle as [Oracle advises against UFW](https://docs.oracle.com/en-us/iaas/Content/Compute/References/bestpracticescompute.htm). |
| `firewall_oracle_iptables` | `security`, `firewall`, `oracle` | Oracle only: opens the same ports (NetBird/HTTP(S)) in Oracle's own iptables rules. |
| `linux_fail2ban` | `security`, `fail2ban` | Bans IPs after repeated failed SSH logins |
| `install_essential_packages` | `packages`, `updates`, `system` | `apt update` + `upgrade`, then install tools to run the server: zsh, curl, git, jq, htop, mtr, rsync, … |
| `install_unattended_upgrades` | `updates`, `automatic` | Unattended upgrades (Ubuntu security updates), **reboots at 4am when required** |
| `linux_swap` | `system`, `swap` | 4G `/swapfile`: disk space used as extra memory, so a memory peak slows the server down instead of crashing programs. Swappiness 10: use it only when memory is nearly full |
| `linux_shared_directory` | `system`, `shared` | Create new group `shared` and [`/srv/shared`](#shared-folder-srvshared): mode 2770 (group-owned, no access for others) plus a default ACL so new files stay group-writable |
| `user_account` | `users` | New admin account, based on user input. With sudo, `adm` and `shared` group membership |
| `docker` | `docker` | Docker Engine + Compose from Docker's repository (apt-pinned to it, updated automatically), log rotation, `live-restore`; admin in `docker` group |
| `linux_logging_setup` | `logging` | System logs (journald, read with `journalctl`) capped at 1 GB, in files of at most 100 MB; Docker's container logs are capped separately by the `docker` role |

Oracle Cloud is detected by the file `/etc/iptables/rules.v4` (override with
`-e oracle_cloud=true` or `false`); there, the `ubuntu` user keeps its sudo rights
alongside the new admin.

#### Shared folder: `/srv/shared`

For files the admin, the agent and other members of group `shared` work on
together; each member has a symlink `~/shared` to it. Others have no access.
Create shared files there, or copy them in with plain `cp`: they then belong to group
`shared` and every member can change them. Files brought in with `mv`, `cp -a`
or `rsync -a` keep their old group; fix them with:

```bash
chgrp -R shared ~/shared/<name>
```

### `vps-init-ssh-setup-playbook.yml`: SSH hardening with role `linux_ssh_setup`

What it changes, in `/etc/ssh/sshd_config.d/99-hardening.conf`: SSH accepts
only keys, no passwords; root cannot log in; at most 3 attempts per connection.
This stops password guessing completely.

It must be the admin who runs it: it refuses to run as root, or if the admin
has no SSH keys. So a working admin login is proven before it switches to
key-only logins and disables root login.

## Afterwards

1. Check the firewall: `sudo ufw status verbose` (Oracle: `sudo iptables -L INPUT -n`).
   Ports Docker publishes with `-p` bypass UFW: bind them to `127.0.0.1` unless
   they should be public. If you only use the server through NetBird, all inbound
   ports can be closed in the cloud firewall, including 22/tcp, which keeps out SSH
   noise. Keep 51820/udp open for direct (P2P) connections, and 80/443/tcp only if
   the server hosts public websites.
2. Check NetBird: `netbird status -d`. Do your peers show up as P2P or as Relay?
3. Check Docker: `docker run --rm hello-world`
4. Set up the agent account with [`create-agent-user.sh`](create-agent-user.sh)
   (see [MAINTENANCE.md](MAINTENANCE.md#create-user-playbookyml-add-more-users)).

If you ever lock yourself out of SSH, the provider's web console (Hetzner: VNC
console; Oracle: serial console) is the only way back in, and it needs the admin password.

Git identity, mise activation and shell settings are not part of this setup:
each user installs them from the [dotfiles repository](https://github.com/malsch/dotfiles).

## Inspired by

This setup was inspired by:

- [Introduction to Ansible](https://phelipetls.github.io/posts/introduction-to-ansible/) is a short, practical introduction to Ansible.
- [basic-server-configuration](https://github.com/mist941/basic-server-configuration/tree/main) is an Ansible repository describing security features we include as well.
