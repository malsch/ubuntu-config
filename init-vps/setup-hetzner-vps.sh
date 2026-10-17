#!/usr/bin/env bash
#
# Server setup: everything that needs root on a
# fresh Hetzner server running Ubuntu 26.04 LTS (Resolute Raccoon):
# 1. Security hardening: UFW, fail2ban, SSH, VPN connection, unattended-upgrades (sections 1–3, 8)
# 2. System configuration and User management: Timezone, swap, create admin and regular user accounts (sections 4–6, 11)
# 3. Frequently required packages: Docker, Netbird, git, mise, syncthing, htop, rsync (sections 7, 9, 10, 12)
#
# SSH connection via port 22, all other ports closed by Hetzner Cloud Firewall.
#   Invaders and bots scan the internet for open SSH ports, but the SSH service itself is hardened against brute-force attacks.
#   Key-only auth is what actually secures SSL connection.
#
# Run as root on a freshly provisioned server:
#     scp setup-server.sh root@<server-ip>:/root/
#     ssh root@<server-ip> 'bash /root/setup-server.sh'
#
# Requirements (setup via Hetzner):
#  - VPN with 4 GB RAM, 2 vCPU
#  - Ubuntu 26.04 LTS (Resolute Raccoon) cloud image
#  - root login via SSH
#  - public SSH key for root in /root/.ssh/authorized_keys
#  - Hetzner Cloud Firewall allows inbound 22/tcp (SSH), outbound everything
#  - for NetBird VPN: create free account and setup key (https://docs.netbird.io/manage/peers/register-machines-using-setup-keys)
#
# Idempotent: re-running is safe.
#
# IMPORTANT: When it finishes, open a NEW terminal and confirm you can log in
# as the new users BEFORE closing your current root session — root SSH login is
# disabled by then.

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
NETBIRD_SETUP_KEY="5CD****" # required for NetBird VPN (password manager)

ADMIN_USERNAME=""        # you. Sudo rights, administers the box.
ADMIN_PASSWORD="<PASSWORD>"   # password for console/su login as ${ADMIN_USERNAME}.
USERNAME="aiagent"            # the agent. NO sudo — it only owns its stacks.

# Git commit identities. Empty => <user>@<hostname> / <user>@<hostname>.local
# (the .local domain is reserved and undeliverable, so machine-made commits are
# obviously machine-made). For the ADMIN, set your real name and email here so
# commits you make on the server are attributed to you properly.
ADMIN_GIT_USER_NAME=""
ADMIN_GIT_USER_EMAIL=""
GIT_USER_NAME=""    # commit identity for ${USERNAME}
GIT_USER_EMAIL=""

SSH_PASSWORD_AUTH="no"        # "no" = key-only SSH (recommended); "yes" opens SSH to password brute-force attacks.
TIMEZONE="Europe/Berlin"
SWAP_SIZE="4G"                # set to "" to skip
NETBIRD_PORT="51820"          # WireGuard UDP port, for direct peer connections
NETBIRD_IFACE="wt0"           # NetBird's tunnel interface
SETUP_UFW="yes"               # host firewall, IN ADDITION to the Hetzner Cloud
#
# Inbound access is filtered twice: by UFW on the host (section 1) and by the
# Hetzner Cloud Firewall in the Cloud Console. Open your SSH port, 80, and 443
# in the Cloud Console too (if it is a public facing service), or the host rules never get a chance to apply.
# Set SETUP_UFW="no" to rely on the Hetzner firewall alone.

log()  { echo -e "\n\033[1;32m==>\033[0m \033[1m$*\033[0m"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
export DEBIAN_FRONTEND=noninteractive

# Quiet apt wrapper. -qq silences progress, Dpkg::Use-Pty=0 stops dpkg redrawing
# the terminal, and >/dev/null drops what is left of stdout. stderr is NOT
# redirected, so real errors and warnings still reach you — and 'set -e' still
# aborts on a non-zero exit. Run with APT_VERBOSE=1 to see everything again.
apt_get() {
  if [[ -n "${APT_VERBOSE:-}" ]]; then
    apt-get -y "$@"
  else
    apt-get -y -qq -o Dpkg::Use-Pty=0 "$@" >/dev/null
  fi
}

# ----------------------------------------------------------------------------
# 1. UFW host firewall
#     DOUBLE SECURITY: may already be blocked by Hetzners Cloud Firewall, but UFW adds a host-side filter.
# 
#     CAVEAT — Docker bypasses UFW. Docker writes its own nftables rules ahead
#     of UFW's chain, so any port published with '-p' is reachable from the
#     internet. Publish as "127.0.0.1:5432:5432" to keep a
#     port host-local, or don't publish at all and let Caddy reach the service
#     over the 'proxy' network by its service name.
# ----------------------------------------------------------------------------
if [[ "${SETUP_UFW}" == "yes" ]]; then
  log "Configuring UFW (default deny inbound)"
  apt_get update      # first apt run of the script; section 7 repeats it
  apt_get install ufw

  ufw --force reset >/dev/null   # idempotent: start from a known state.
                                 # NOTE: this also drops rules you added by hand.
  ufw default deny incoming
  ufw default allow outgoing

  # SSH first, always. Plain 'allow', not 'limit': 'limit' drops any source that
  # opens more than 6 connections in 30s, which trips on your own reconnects
  # during setup and looks exactly like a firewall block (silent timeout).
  # fail2ban already handles brute-force, based on actual auth failures.
  ufw allow 22/tcp comment 'SSH'

  # NetBird: outbound needs no rule (the daemon dials out and UFW allows
  # established return traffic), but opening the UDP port lets peers connect
  # DIRECTLY instead of silently degrading to a slower relay. The interface
  # rule is accepted even though wt0 does not exist until section 9.
  ufw allow "${NETBIRD_PORT}/udp" comment 'NetBird WireGuard'

  # Trust anything arriving through the tunnel. Without this, services stay
  # unreachable over NetBird even when the tunnel itself is up — UFW filters
  # tunnel traffic exactly like public traffic.
  ufw allow in on "${NETBIRD_IFACE}" comment 'NetBird tunnel'

  # allow forwarding to only Docker's actual documented 172.x pools ("default-address-pools")
  # 192.168.0.0/16 left out ... not sure if this is for good reasons
  ufw route allow in on "${NETBIRD_IFACE}" to 172.17.0.0/16 port 80 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.18.0.0/16 port 80 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.19.0.0/16 port 80 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.20.0.0/14 port 80 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.24.0.0/14 port 80 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.28.0.0/14 port 80 proto tcp

  ufw route allow in on "${NETBIRD_IFACE}" to 172.17.0.0/16 port 443 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.18.0.0/16 port 443 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.19.0.0/16 port 443 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.20.0.0/14 port 443 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.24.0.0/14 port 443 proto tcp
  ufw route allow in on "${NETBIRD_IFACE}" to 172.28.0.0/14 port 443 proto tcp

  # Caddy.
  ufw allow 80/tcp  comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'

  ufw --force enable             # --force skips the interactive y/n prompt
  ufw status verbose
fi

# ----------------------------------------------------------------------------
# 2. SSH hardening
#    These directives govern AUTHENTICATION and are enforced by sshd on every
#    login, independent of the socket activation Ubuntu 26.04 uses for the port.
# ----------------------------------------------------------------------------
log "Hardening SSH (password auth=${SSH_PASSWORD_AUTH}, no root login)"
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication ${SSH_PASSWORD_AUTH}
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
EOF
sshd -t   # validate before any restart

systemctl restart ssh.socket 2>/dev/null || true
systemctl restart ssh.service 2>/dev/null || systemctl restart ssh || true

# ----------------------------------------------------------------------------
# 3. fail2ban (writes bans straight into nftables, independent of UFW)
# ----------------------------------------------------------------------------
log "Configuring fail2ban"
apt_get install fail2ban
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = 22
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

# ----------------------------------------------------------------------------
# 4. Timezone
# ----------------------------------------------------------------------------
log "Setting timezone to ${TIMEZONE}"
timedatectl set-timezone "${TIMEZONE}"

# ----------------------------------------------------------------------------
# 5. Create the two non-root accounts, copy SSH keys in
#
#    ${ADMIN_USERNAME} — you. In the sudo group, so it administers the box.
#    ${USERNAME}       — the agent. Deliberately NOT in sudo: if the agent goes
#                        off the rails it can wreck its own stacks and nothing
#                        else. Escalate from ${ADMIN_USERNAME} instead.
#
#    Both get root's SSH key so you can log in as either. Both are created with
#    --disabled-password (no password hash at all), so neither can be reached
#    by password guessing; key auth is the only way in.
# ----------------------------------------------------------------------------
# Copy /root/.ssh/authorized_keys to a user, with the strict perms sshd demands.
install_ssh_key() {
  local u="$1"
  if [[ -f /root/.ssh/authorized_keys ]]; then
    install -d -m 700 -o "${u}" -g "${u}" "/home/${u}/.ssh"
    install -m 600 -o "${u}" -g "${u}" \
      /root/.ssh/authorized_keys "/home/${u}/.ssh/authorized_keys"
  else
    warn "No /root/.ssh/authorized_keys found. Ensure ${u} has an SSH key"
    warn "BEFORE you log out, or you may lock yourself out."
  fi
}

log "Creating agent user '${USERNAME}' (no sudo, with id 1000)"
if ! id "${USERNAME}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${USERNAME}"
fi
install_ssh_key "${USERNAME}"

log "Creating admin user '${ADMIN_USERNAME}'"
if ! id "${ADMIN_USERNAME}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${ADMIN_USERNAME}"
fi
usermod -aG sudo "${ADMIN_USERNAME}"
install_ssh_key "${ADMIN_USERNAME}"

# Admin account password (console / su / sudo — NOT SSH unless
# SSH_PASSWORD_AUTH=yes).
if [[ -n "${ADMIN_PASSWORD}" ]]; then
  echo "${ADMIN_USERNAME}:${ADMIN_PASSWORD}" | chpasswd
  log "Password set for ${ADMIN_USERNAME} (usable at the Hetzner console / via su)"
else
  warn "No ADMIN_PASSWORD set. Run 'sudo passwd ${ADMIN_USERNAME}' to add a console/su password."
fi

# Passwordless sudo for the admin only — validated before install (26.04's
# sudo-rs silently ignores a malformed file). Filename must contain no dots.
log "Configuring passwordless sudo for ${ADMIN_USERNAME}"
SUDOERS_TMP="$(mktemp)"
echo "${ADMIN_USERNAME} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_TMP}"
if visudo -cf "${SUDOERS_TMP}" >/dev/null 2>&1; then
  install -m 440 -o root -g root "${SUDOERS_TMP}" "/etc/sudoers.d/90-${ADMIN_USERNAME}"
else
  warn "sudoers validation failed — skipping passwordless sudo drop-in."
fi
rm -f "${SUDOERS_TMP}"

# Git commit identities. Installs git first: this runs before section 7, and
# Ubuntu's cloud image does not ship it.
# -H makes --global write to THAT user's ~/.gitconfig rather than root's.
apt_get install git
set_git_identity() {
  local u="$1" name="${2:-}" email="${3:-}"
  name="${name:-${u}@$(hostname)}"
  email="${email:-${u}@$(hostname).local}"
  log "Setting git identity for ${u}: ${name} <${email}>"
  sudo -u "${u}" -H git config --global user.name  "${name}"
  sudo -u "${u}" -H git config --global user.email "${email}"
}
set_git_identity "${ADMIN_USERNAME}" "${ADMIN_GIT_USER_NAME}" "${ADMIN_GIT_USER_EMAIL}"
set_git_identity "${USERNAME}"       "${GIT_USER_NAME}"       "${GIT_USER_EMAIL}"

# ----------------------------------------------------------------------------
# 6. Deploy directories, owned by the agent
#     These live under /opt, so only root can create them — and ${USERNAME} has
#     no sudo to do it itself. setup-agent.sh then fills them in unprivileged.
#
#     Probably not standard to do it this way..., use it or not.
# ----------------------------------------------------------------------------
log "Creating /opt/stacks and /opt/repos for ${USERNAME}"
install -d -o "${USERNAME}" -g "${USERNAME}" /opt/stacks /opt/repos

# ----------------------------------------------------------------------------
# 7. System update + base packages
# ----------------------------------------------------------------------------
log "Updating the system and installing base packages"
apt_get update
apt_get upgrade
# Packages used by exactly one section are installed by that section instead:
# ufw (1), fail2ban (3), git (5), unattended-upgrades (8), mise (10), docker (12).
apt_get install \
  ca-certificates curl gnupg lsb-release \
  htop rsync syncthing jq

# may also be meaningful to install with sudo apt to run commands like npx playwright install-deps --dry-run chromium later
# alternative: only available via mise
# sudo apt install nodejs npm

# ----------------------------------------------------------------------------
# 8. Automatic security updates, including reboots at 4am if updates require it
# ----------------------------------------------------------------------------
log "Enabling unattended security upgrades"
apt_get install unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
sed -i 's|//\s*Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' \
  /etc/apt/apt.conf.d/50unattended-upgrades || true
sed -i 's|//\s*Unattended-Upgrade::Automatic-Reboot-Time "02:00";|Unattended-Upgrade::Automatic-Reboot-Time "04:00";|' \
  /etc/apt/apt.conf.d/50unattended-upgrades || true

# ---------------------------------------------------------------------------
# 9. VPN (Login to NetBird)
# ---------------------------------------------------------------------------
log "Installing NetBird (WireGuard-based mesh VPN)"
curl -fsSL https://pkgs.netbird.io/install.sh | sh

netbird up --setup-key "${NETBIRD_SETUP_KEY}"

# ----------------------------------------------------------------------------
# 10. Mise: manage developer tools in user-space (no root required)
#     The binary is system-wide, the activation is per-user: each account opts
#     in via its own ~/.bashrc and keeps its own tools under
#     ~/.local/share/mise.
# ----------------------------------------------------------------------------
log "Installing mise"
# 'if cmd' suspends set -e for the whole chain, so a failure lands in the else.
if add-apt-repository -y ppa:jdxcode/mise >/dev/null \
   && apt_get update \
   && apt_get install mise; then

  # Append per user, guarded by grep so re-running the script does not stack up
  # duplicate lines in .bashrc/.profile.
  activate_mise_for() {
    local u="$1"
    local rc="/home/$1/.bashrc"
    local profile="/home/$1/.profile"
    local rc_line='eval "$(/usr/bin/mise activate bash)"'
    local profile_line='eval "$(/usr/bin/mise activate bash --shims)"'

    if [[ -f "${rc}" ]] && ! grep -qF "mise activate bash" "${rc}"; then
      printf '\n# mise: manage tool versions per project\n%s\n' "${rc_line}" >> "${rc}"
      chown "${u}:${u}" "${rc}"
      log "  activated mise for ${u} (.bashrc)"
    fi

    # Shims in .profile so non-interactive / login contexts (cron, ssh
    # commands, GUI sessions) still find mise-managed tools on PATH.
    if ! grep -qsF "mise activate bash --shims" "${profile}"; then
      printf '\n# mise: shims for non-interactive shells\n%s\n' "${profile_line}" >> "${profile}"
      chown "${u}:${u}" "${profile}"
      log "  activated mise shims for ${u} (.profile)"
    fi
  }
  activate_mise_for "${ADMIN_USERNAME}"
  activate_mise_for "${USERNAME}"
else
  # Drop the sources entry if it was added, so every later 'apt-get update'
  # does not warn about a repo with no release file.
  rm -f /etc/apt/sources.list.d/*mise*.list /etc/apt/sources.list.d/*mise*.sources
  warn "mise install failed (PPA likely has no build for this Ubuntu release)."
  warn "Skipped — install it later with: curl https://mise.run | sh"
fi

# ----------------------------------------------------------------------------
# 11. Swap
# ----------------------------------------------------------------------------
if [[ -n "${SWAP_SIZE}" && ! -f /swapfile ]]; then
  log "Creating ${SWAP_SIZE} swap file"
  fallocate -l "${SWAP_SIZE}" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
fi

# ----------------------------------------------------------------------------
# 12. Docker (official repo) + Compose plugin
#    26.04 has native `resolute` packages; fall back to `noble` if a mirror lags.
# ----------------------------------------------------------------------------
log "Installing Docker Engine + Compose plugin"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi
CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
write_docker_list() {
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $1 stable" \
    > /etc/apt/sources.list.d/docker.list
}
write_docker_list "${CODENAME}"
apt_get update
if ! apt-cache policy docker-ce | grep -q 'Candidate: [0-9]'; then
  warn "No docker-ce candidate for '${CODENAME}'; falling back to 'noble'."
  write_docker_list "noble"
  apt_get update
fi
apt_get install \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
# NOTE: the docker group is effectively root — a member can bind-mount / into a
# privileged container. So this hands ${USERNAME} a root-equivalent capability
# despite it having no sudo. It needs it to run its own compose stacks; if you
# want the agent genuinely confined, switch it to rootless Docker instead.
usermod -aG docker "${ADMIN_USERNAME}"
usermod -aG docker "${USERNAME}"

# ----------------------------------------------------------------------------
# 13. Docker daemon config — log rotation + sane defaults
# ----------------------------------------------------------------------------
log "Configuring Docker daemon (log rotation, live-restore)"
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
systemctl enable docker
systemctl restart docker

# ----------------------------------------------------------------------------
# 14. sane defaults for logging (syslog provides a second copy in a legacy format - worth keeping?)
# ----------------------------------------------------------------------------
log "Configure logging: 1GB max (journald); 1 month (keep default) (syslog - the legacy service)"
sudo install -d /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/00-size-cap.conf >/dev/null <<'EOF'
# Cap journal disk usage so a runaway log (e.g. a crash loop) can never fill the
# disk. journald enforces these continuously as it writes, deleting the oldest
# archived journals to stay under the limit.
#
# SystemMaxUse      — hard ceiling on TOTAL journal disk usage.
# SystemMaxFileSize — cap per INDIVIDUAL journal file, so rotation happens in
#                     smaller chunks and the total cap is enforced more tightly
#                     (only archived/rotated files can be vacuumed, not the active one).

[Journal]
SystemMaxUse=1000M
SystemMaxFileSize=100M
EOF
sudo systemctl restart systemd-journald

log "Add both users to adm group - grants read access to log files"
usermod -aG adm "${ADMIN_USERNAME}"
usermod -aG adm "${USERNAME}"

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
log "Setup complete."
cat <<EOF

Next steps:
  1. In a NEW terminal, verify SSH login as BOTH new users:
         ssh ${ADMIN_USERNAME}@<server-ip>   # your admin account
         ssh ${USERNAME}@<server-ip>   # the agent (no sudo)
     Only close this root session once that works — root login is now off.
     Sanity checks:
         ss -tnlp | grep ":22"
         sudo systemctl status ssh.socket

  2. In the Hetzner Cloud Console, configure the Cloud Firewall to allow
     inbound: 22/tcp (SSH), 80/tcp (if serving HTTPS), 443/tcp (if serving HTTPS), ${NETBIRD_PORT}/udp (NetBird).
     UFW on the host allows the same set, but it only ever sees traffic the
     Cloud Firewall already let through. Check the host side with:
         sudo ufw status verbose
     Remember: ports published by Docker with '-p' bypass UFW entirely. Bind
     them to 127.0.0.1 in compose if they should not be public.

  2b. Verify NetBird VPN:
         netbird status -d
     Do you see your peers? Is Connection type: P2P (peer-to-peer) or Relay (slower)?

  3. Verify Docker (log in as ${USERNAME} so the docker group applies):
         docker run --rm hello-world
         docker compose version

  4. Syncthing (optional, for file sync between your laptop and server).
     With this setup only reachable over NetBird, so it is not exposed to the public internet.
     Its web UI binds to 127.0.0.1:8384 and has no password until you set one,
     so do not open that port. Reach it by tunnelling:
         ssh -L 8384:localhost:8384 ${USERNAME}@<server-ip>

     As ${USERNAME}:
         syncthing                                        # configure, then Ctrl-C
         systemctl --user enable --now syncthing.service
         systemctl --user disable --now syncthing.service # undo

      Configuration:
        - nur localhost hat Zugriff auf GUI (keine Authentifizierung erforderlich)
        - turn off global discoery? (Globale Gerätesuche)
        - Gerätekennung vom Peer eingeben (der Peer muss die Verbindung bestätigen)
        - erweitert->address (auf beiden Rechnern): tcp://<netbird-name>.netbird.cloud:22000 (avoids using the syncthing relay-server)

     Service is currently killed the moment ${USERNAME}'s last session ends; sync then stops until the next login.
     To keep working, enable:
         sudo loginctl enable-linger ${USERNAME}

  5. NOT UP TO DATE:Run part 2 as ${USERNAME} — it sets up the Caddy stack and the git
     deploy repos. Copy it over and run it from that session (NOT as root,
     and not via sudo — the docker group only applies to a fresh login):
         scp setup-agent.sh ${USERNAME}@<server-ip>:~/
         ssh ${USERNAME}@<server-ip>
         bash ~/setup-agent.sh

  6. Install quarto? And then R, python, tex, ...:
        wget https://github.com/quarto-dev/quarto-cli/releases/download/v1.10.18/quarto-1.10.18-linux-amd64.deb (https://quarto.org/docs/get-started/)
        sudo apt install ./quarto-1.10.18-linux-amd64.deb
        quarto check

Worth knowing:
  * If you ever lock yourself out of SSH, the Hetzner Cloud Console (VNC) is
    your only way back — and it needs a password. Set ADMIN_PASSWORD in this
    script, or run 'passwd ${ADMIN_USERNAME}' now. Both accounts are created
    with no password at all, so without this there is no console login.
  * ${USERNAME} has no sudo, but IS in the docker group — which is
    root-equivalent (it can bind-mount / into a privileged container). Treat
    "no sudo" as a guard against accidents, not as a sandbox.
  * mise is activated per user in ~/.bashrc, which only applies to interactive
    shells.

Further thoughts (should be added to the dotfiles):
  mise use -g sops
  # add to .bashrc: export SOPS_EDITOR=nano
  git config diff.sops.textconv "sops -d"

EOF
