# Security Architecture

How the playbooks protect the server, layer by layer, and which trade-offs are
left on purpose. Setup steps are in the [README](README.md).

## Network

### NetBird: a private network for your devices

[NetBird](https://netbird.io) connects the server and your own devices
(laptop, phone, other servers) in a private network over WireGuard. It is an alternative to [Tailscale](https://tailscale.com/blog/how-tailscale-works).

- **Encrypted end to end.** Traffic between peers is encrypted by WireGuard.
  NetBird's servers only help peers find each other, and relay the traffic
  when no direct connection is possible. They cannot read it, nobody can.
- **Private services stay private.** Through the tunnel, your devices can reach
  everything on the server: SSH, admin interfaces, web apps in Docker, and
  anything else not meant for the public. None of it needs an open port on
  the internet.
- **Only one port open, and it is safe.** NetBird only needs one UDP port
  (WireGuard, 51820 by default) for direct P2P connections; without it,
  traffic goes through a relay. WireGuard silently drops every packet that
  is not authenticated with a known key, so to a scanner the port looks
  closed and there is nothing to attack or guess. All other ports, including
  port 22, can be closed in the firewall.
- **Joining the private network needs a setup key** from your NetBird account.
- **Access rules.** NetBird's access policies (in its dashboard) decide which
  peers may reach the server. The server's firewall trusts everything that
  arrives through the tunnel (see [Known trade-offs](#known-trade-offs)).

### Firewalls: two layers

- The firewall settings we implement can certainly be improved. We just provide some intitial configuration. Dependening on what the server is used for, you may need to 
  revisit the firewall settings.
- **Cloud firewall** (Hetzner Cloud Firewall, Oracle Security List or Network
  Security Group), set it up in the provider's console. It filters traffic before it reaches the server.
  Once NetBird works, ports 22, 80 and 443
  should probably be closed there, unless you need them public. They stay
  reachable through the tunnel.
- **Host firewall** on the server, set up by the playbook:
  - UFW blocks every incoming connection by default and allows outgoing ones.
  - It opens only 22/tcp (SSH), 80/443/tcp (web) and NetBird's WireGuard
    port (UDP, for direct connections between peers).
  - On Oracle this is implemented using Oracle's own iptables rules instead
    of UFW.
  - The NetBird network is fully trusted: everything arriving through the
    tunnel is allowed, on every port, including web traffic (80/443)
    forwarded to Docker containers. Which peers may reach the server is
    decided only by NetBird's access policies (see
    [Known trade-offs](#known-trade-offs)).
- **If one layer is misconfigured, the other still protects.** A port must
  be open in both firewalls to be reachable from the internet. One exception
  is in [Known trade-offs](#known-trade-offs): Docker bypasses UFW.

### SSH

Port 22 is open to the internet at least until NetBird works and you close
it. Bots scan it day and night with common usernames and passwords. One
example from a single day in October 2026: About 2,000 SSH connections from 196
IP addresses: 1,250 tried root, 571 made-up usernames (admin, test, user,
ubuntu, deploy …). fail2ban banned 48 IPs.

To secure SSH (in case port 22/tcp is left open):

- Only key logins. Passwords and keyboard-interactive login are switched off,
  so password guessing over SSH does not work.
- No root login. You log in as your admin and use sudo, which is logged.
- fail2ban bans an IP for 12 hours after 3 failed SSH logins.

## Isolation: accounts and containers

The main principle: every person, agent and app runs separately. If one of them
goes wrong (a bug, a compromised dependency, an agent doing something
unexpected), it should not be able to damage the others.

### Accounts

We can think of three kinds of accounts:

**1. Admin accounts, with sudo.** They administer the server: install software,
change settings, run these playbooks. Each admin is a person with their own
account, instead of a shared root login. Passwords never work over SSH: they are
only for `sudo`, `su` and the provider's web console, your way back in if SSH
breaks.

**2. User accounts, without sudo.** They use the programs already installed and
add their own in their home folder (with mise, uv, npm, …), but cannot change
the system. Home folders are private (Ubuntu's default, mode 0750), and files
are shared only through `/srv/shared` (group `shared`, mode 2770). An AI agent
is such a user (`create-agent-user.sh`). It is in the `adm` group only to read
the system logs, because this agent monitors the server; `adm` gives no other
rights. Agents are more effective if they can try things out in an isolated
environment with Docker (see [Known trade-offs](#known-trade-offs)).

**3. Accounts for programs reachable from the internet.** A web app or bot that
anyone can talk to is the most likely to be attacked. Running it as its own
user, without sudo, without docker, not in group `shared` and without SSH keys,
means a successful attack only gets that account and cannot read other users’
files or change the system. With lingering, the program's systemd services start
at boot and keep running after logout, so it runs around the clock without
anyone logged in.

### Containers

- **Apps may run in Docker containers**, each with its own files, processes and
  network. Compromised code inside a container only sees the container and the
  network. If a container is broken, you delete it and start a fresh one from
  its image, and nothing of the attack remains.
- **This holds as long as the container gets nothing more.** It does not hold
  for folders mounted from the server (writable from inside), for
  `--privileged`, or for a mounted Docker socket (`/var/run/docker.sock`), which
  gives root on the server.

## Software and updates

The main concern: how do we keep malicious code from entering the system?

### Only known, trusted sources

System software comes only from Ubuntu's archive and from the official apt
repositories of Docker, NetBird and mise (if installed). Nothing is
installed with `curl … | bash`. Apt makes sure these sources stay what they
claim to be:

- **Every repository is signed.** So apt only installs a package if it was
  published by whoever holds that repository's signing key. Nobody in
  between, such as a mirror, a proxy or an attacker on the network, can
  change it or slip in another one. Each repository is tied to its own key
  (`signed-by`), so Docker's key, for example, cannot vouch for Ubuntu
  packages.
- **Pinning.** Each vendor repository may only supply its own packages
  (Docker, NetBird, mise), and these packages may only come from there.
  So a vendor cannot replace Ubuntu packages (say, with a newer openssl),
  and no other repository can slip in a fake docker-ce.
- **Ansible itself** and its modules come from Ubuntu's ansible package,
  not from Ansible Galaxy. The playbooks provided here should come from a trusted source, run as root, and live in `/opt/ubuntu-config`, which only root can change.

Quarto (if installed) is the one exception: it has no apt repository, so it
comes from Quarto's GitHub releases. The playbook installs only the exact
version it was written for. A changed file on GitHub is refused, not
installed. It gets no automatic updates.

### Automatic updates

`unattended-upgrades` installs security updates every day, for Ubuntu and for
Docker, and reboots at 4am when needed. Known holes are closed quickly.
NetBird and mise are updated with `sudo apt upgrade`.

## Known trade-offs

These are deliberate; know them before relying on the setup.

- **Sudo without a password is the default for the admin.** The admin is in
  the `docker` group, which is root without a password anyway, so a sudo
  password would add little. Whoever has the admin's SSH key is root.
  Protect that key (passphrase, or a hardware key).
- **The `docker` group breaks account isolation.** Members can start a
  container that mounts the whole server, which makes them root. The admin
  is a member, and so is the agent account created by
  `create-agent-user.sh`. Code running as the agent can therefore reach
  every other account. [Rootless Docker](https://docs.docker.com/engine/security/rootless/)
  or [Podman](https://podman.io) (rootless by default, mostly compatible with
  Docker's commands) would keep the agent's containers inside its own account.
- **Docker bypasses UFW.** Ports published with `-p` are reachable from the
  internet even if UFW blocks them. Bind them to `127.0.0.1` or to the
  NetBird IP when they should not be public. The cloud firewall still
  applies.
- **The NetBird tunnel is trusted completely.** Every NetBird peer that may
  reach this server can reach all its ports. Restrict this with NetBird's
  access policies.
- **Port 22 is open to the internet** until you close it in the cloud
  firewall.
- **Ports 80 and 443 are open** in the host firewall, so a web server can be
  reached from the internet. Nothing answers until one runs there. If the
  server hosts no public websites, keep them closed in the cloud firewall.
- **Copied SSH keys.** With the answer `me`, the admin gets the same keys as
  the account that ran the setup (often root). Remove keys you don't need
  from `~/.ssh/authorized_keys`.
- **X11 forwarding stays on** (Ubuntu's default), so graphical programs on the
  server can open windows on your computer with `ssh -X`. Only use it with a
  server you trust: if it were taken over, the forwarded connection could be
  abused to read your keystrokes or screen. `ssh -X` (not `-Y`) limits what
  the server can do with your display; a remote desktop (VNC, xrdp) over
  NetBird avoids the risk entirely.

## Further notes to increase security

- [An essay on paying for open source](https://seldo.com/posts/nobody-pays-for-open-source-we-can-force-them-to/) describes the big business around open-source supply chain security, where JFrog and Snyk seem to be the largest providers.
- [Ubuntu Pro (ESM)](https://ubuntu.com/security/esm) extends security updates beyond the five years of standard support of an LTS release.
- [GitHub's supply chain security](https://github.com/security/advanced-security/software-supply-chain) (dependency graph, Dependabot) warns about vulnerable open-source dependencies in your repositories; most of it is free.
- [Snyk](https://snyk.io/de/plans/) is another provider of such scans, priced for software companies.
- The BSI's [IT-Grundschutz-Kompendium](https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/IT-Grundschutz-Kompendium/it-grundschutz-kompendium_node.html) (German) describes in detail how to set up and run a secure server.
- [Grundschutz++](https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/Grundschutz-in-der-Informationssicherheit/Grundschutz-Plus-Plus/grundschutz-plus-plus_node.html) is the BSI's successor to IT-Grundschutz, currently being updated.
- [InSpec](https://github.com/inspec/inspec) runs automated compliance checks, e.g. to verify that a server's settings match a security baseline.

## Checking code for security issues

- [pip-audit](https://github.com/pypa/pip-audit) lists known vulnerabilities (CVEs) in a Python project's dependencies: `uvx pip-audit`.
- [Bandit](https://github.com/PyCQA/bandit) finds risky patterns in Python code, such as injection, weak crypto, hardcoded secrets or unsafe subprocess calls: `uvx bandit -r src/`.
- [SonarQube Cloud](https://github.com/marketplace/sonarcloud) Automated code quality and security reviews, free for OSS maintainers and small private projects.
