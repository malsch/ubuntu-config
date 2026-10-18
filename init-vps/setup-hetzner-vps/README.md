# setup-hetzner-vps

Ansible playbook that sets up a fresh Ubuntu server (written for Ubuntu 26.04
LTS on Hetzner; also handles Oracle Cloud, x86 and ARM). It runs on the server itself (`hosts: localhost`, no SSH) and can safely be
run more than once.

## Requirements

- Server: Ubuntu 26.04 cloud image, root login via SSH key
- Cloud firewall (Hetzner Cloud Firewall, or Oracle's Security List / Network
  Security Group): inbound 22/tcp, plus 80/443/tcp and 51820/udp as needed
- NetBird account with a [setup key](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys)

## Usage

On the fresh server, as root:

```bash
apt update && apt install -y ansible git
```

Ubuntu's `ansible` package includes the `community.general` and
`ansible.posix` collections that the playbook uses. Then copy or clone this
directory onto the server, to a folder your admin account can read later, e.g.
`/opt/setup-hetzner-vps` (not `/root`), and:

```bash
cd /opt/setup-hetzner-vps && ./run.sh
```

It first asks a few questions; nothing is stored:

- admin username and password (required; on later runs, empty keeps the current one);
- how sudo behaves: by default it asks for the admin password, then not again
  for 24 hours within the same login session; you can turn the password off
  completely;
- timezone (default `Europe/Berlin`);
- NetBird [setup key](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys)
  (needed on the first run; later, empty keeps the existing connection).

Each run writes a log and an HTML report to `logs/` (git-ignored).

### Then: SSH hardening (`ssh-setup.yml`)

`playbook.yml` leaves root login on. Its last message tells you the next step:

1. **Keep the root session open.** In a new terminal, log in as the admin:
   `ssh <admin>@<server-ip>`.
2. From that admin session:

   ```bash
   cd /opt/setup-hetzner-vps && sudo ansible-playbook ssh-setup.yml
   ```

   It refuses to run from root directly or if the admin has no SSH keys, then
   switches to key-only logins and disables root login (role `linux_ssh_setup`).

Doing this as a separate step means a working non-root login is proven before
root login is switched off. Later runs of either playbook: as the admin, with
`sudo`, e.g. `sudo ./run.sh`.

Arguments are passed through to `ansible-playbook`. For example, to run only
some roles:

```bash
./run.sh --tags "docker,security"
```

## More users: `create-user.yml`

Creates (or updates) one account and asks for the important decisions, using
the same `user_account` role as the admin:

```bash
sudo ansible-playbook create-user.yml
```

| Question | Default |
|---|---|
| Give sudo rights? | no |
| Password (`su`, sudo, console; never SSH). Required; empty only keeps an existing one | — |
| With sudo: hours before sudo asks for the password again (per login session) | 24 |
| With sudo: turn the sudo password off completely | no |
| SSH keys: copy from a user, paste a public key, or `none` | the user who ran `sudo` |
| `docker` group (effectively root) / `adm` group (read logs) | no / no |
| Lingering (systemd user services start at boot) | yes |

At the end it prints a summary of the choices and what they mean. Answers can
also be given on the command line, e.g. `-e username=alice -e sudo=no`.

For the AI agent's account, [`create-agent-user.sh`](create-agent-user.sh) runs
`create-user.yml` with fixed answers: `aiagent`, no sudo, `docker` and `adm`
groups, lingering on, SSH keys copied from you. Only the password is asked:

```bash
sudo ./create-agent-user.sh
```

### Changing a user

Run `create-user.yml` again with the same username. It changes what the
answers say, but only ever **adds** groups and keys:

| What | Re-running `create-user.yml` | By hand |
|---|---|---|
| sudo on / off, password timeout, passwordless | changed as answered (no = removed from `sudo`) | — |
| Password | replaced if you enter one; empty keeps it | `sudo passwd <user>` |
| `docker` / `adm` groups | only added, never removed | `sudo gpasswd -d <user> docker` |
| SSH keys | a pasted key is added; copying from another user only seeds a missing `authorized_keys` | edit `~<user>/.ssh/authorized_keys` |
| Lingering | only turned on | `sudo loginctl disable-linger <user>` |

### Deleting a user

The playbooks never delete users. By hand, as the admin:

```bash
sudo loginctl disable-linger <user>
```

```bash
sudo pkill -u <user>
```

```bash
sudo deluser --remove-home <user>
```

```bash
sudo rm -f /etc/sudoers.d/90-<user>
```

This stops the user's services, ends its processes, and removes the account,
its home folder and its sudo settings. Files it owns elsewhere (e.g.
`/opt/stacks`) stay; `deluser --remove-all-files` removes those too. Docker
containers it started keep running, since Docker runs them, not the user: stop
them with `docker compose down` first.

## Oracle Cloud

Oracle's Ubuntu images differ in two ways, and the playbook detects them by
the file `/etc/iptables/rules.v4` (override with `./run.sh -e oracle_cloud=true`
or `false`):

- **Firewall:** the images ship iptables rules that reject everything but SSH,
  and Oracle advises against UFW. The `firewall_ufw` role is skipped; `firewall_oracle_iptables`
  adds the NetBird/HTTP(S) openings to Oracle's rules instead.
- **SSH keys:** root login is blocked, so you log in as `ubuntu`. Run the
  playbook with `sudo -i`, and the admin account gets the `ubuntu` user's keys.
  The `ubuntu` user keeps its sudo rights.

## What it configures

Roles run in this order (see [`playbook.yml`](playbook.yml)). Tags are in brackets.

| Role | Tags | What it does |
|---|---|---|
| `linux_time_configuration` | `time` | Timezone |
| `netbird` | `netbird` | Installs NetBird from its apt repository (apt-pinned to it), joins the mesh, and reads its WireGuard port and tunnel interface for the firewall roles |
| `firewall_ufw` | `security`, `firewall`, `ufw` | Host firewall: default deny, SSH/HTTP(S)/NetBird open, NetBird tunnel trusted. Skipped on Oracle. |
| `firewall_oracle_iptables` | `security`, `firewall`, `oracle` | Oracle only: opens the same ports in Oracle's own iptables rules |
| `linux_fail2ban` | `security`, `fail2ban` | Bans IPs after repeated failed SSH logins |
| `install_essential_packages` | `packages`, `updates`, `system` | `apt update` + `upgrade`, then curl, git, jq, ripgrep, Python build tools, ffmpeg, htop, mtr, rsync, syncthing, … |
| `install_unattended-upgrades` | `updates`, `automatic` | Unattended upgrades (Ubuntu security updates), reboots at 4am when required |
| `linux_swap` | `system`, `swap` | 4G `/swapfile`, swappiness 10 |
| `mise` | `packages`, `mise` | mise from mise's own apt repository (x86 and ARM) |
| `user_account` | `users` | Admin account: sudo (asks for the password, then not for 24h; or passwordless), `adm`, SSH keys copied from root (`ubuntu` on Oracle) |
| `install_chromium_dependencies` | `packages`, `chromium` | Libraries, fonts and xvfb that Chromium (Playwright) needs |
| `docker` | `docker` | Docker Engine + Compose from Docker's repository (apt-pinned to it, updated automatically), log rotation, `live-restore`; admin in `docker` group |
| `linux_logging_setup` | `logging` | journald capped at 1 GB |
| `linux_ssh_setup` | — | Key-only SSH, no root login. **Not in `playbook.yml`:** run separately via `ssh-setup.yml`, see above. |

Adjustable settings live in each role's `defaults/main.yml` (e.g. `linux_swap_size`,
`docker_codename`). Override one per run with `./run.sh -e name=value`.

## Afterwards

1. Check that you can log in as the admin user: `ssh <admin>@<server-ip>`
2. Check the firewall: `sudo ufw status verbose` (Oracle: `sudo iptables -L INPUT -n`). Ports that Docker publishes
   with `-p` bypass UFW, so bind them to `127.0.0.1` if they should not be public.
3. Check NetBird: `netbird status -d`. Do your peers show up as P2P or as Relay?
4. Check Docker: `docker run --rm hello-world`
5. Set up the agent account with [`../setup-agent-user.sh`](../setup-agent-user.sh).
6. Optional, Quarto (then R, Python, TeX, …): download the `.deb` from
   <https://quarto.org/docs/get-started/>, `sudo apt install ./quarto-*.deb`, `quarto check`.

If you ever lock yourself out of SSH, the provider's web console (Hetzner: VNC
console; Oracle: serial console) is the only way back in, and it needs the admin password.

Git identity, mise activation and shell settings are not part of this setup:
each user installs them from [`../../dotfiles`](../../dotfiles).

## Further inspiration

- https://github.com/mist941/basic-server-configuration/tree/main/roles/automatic_updates/tasks
