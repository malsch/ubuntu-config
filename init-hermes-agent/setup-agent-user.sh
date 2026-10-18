#!/usr/bin/env bash
#
# Agent account setup: creates the unprivileged agent user on a server that
# setup-hetzner-vps.sh has already prepared (it relies on git, mise and Docker
# being installed).
#   - user ${USERNAME} with root's SSH key, NO sudo
#   - git commit identity
#   - /opt/stacks and /opt/repos owned by the agent
#   - mise activation in its ~/.bashrc and ~/.profile
#   - docker and adm group membership
#
# Root SSH login is disabled once setup-hetzner-vps.sh has run, so run this
# from the admin account:
#     scp setup-agent-user.sh <admin>@<server-ip>:~/
#     ssh <admin>@<server-ip> 'sudo bash ~/setup-agent-user.sh'
#
# Idempotent: re-running is safe.

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
USERNAME="aiagent"            # the agent. NO sudo — it only owns its stacks.

# Git commit identity. Empty => <user>@<hostname> / <user>@<hostname>.local
# (the .local domain is reserved and undeliverable, so machine-made commits are
# obviously machine-made).
GIT_USER_NAME=""    # commit identity for ${USERNAME}
GIT_USER_EMAIL=""

log()  { echo -e "\n\033[1;32m==>\033[0m \033[1m$*\033[0m"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

# ----------------------------------------------------------------------------
# 1. Create the agent account, copy SSH keys in
#    Deliberately NOT in sudo: if the agent goes off the rails it can wreck its
#    own stacks and nothing else. Escalate from the admin account instead.
#
#    Gets root's SSH key so you can log in as it. Created with
#    --disabled-password (no password hash at all), so it cannot be reached
#    by password guessing; key auth is the only way in.
# ----------------------------------------------------------------------------
log "Creating agent user '${USERNAME}' (no sudo)"
if ! id "${USERNAME}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${USERNAME}"
fi

# Copy /root/.ssh/authorized_keys over, with the strict perms sshd demands.
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 700 -o "${USERNAME}" -g "${USERNAME}" "/home/${USERNAME}/.ssh"
  install -m 600 -o "${USERNAME}" -g "${USERNAME}" \
    /root/.ssh/authorized_keys "/home/${USERNAME}/.ssh/authorized_keys"
else
  warn "No /root/.ssh/authorized_keys found. Ensure ${USERNAME} has an SSH key"
  warn "or you will not be able to log in as it."
fi

# ----------------------------------------------------------------------------
# 2. Git commit identity
#    -H makes --global write to THAT user's ~/.gitconfig rather than root's.
# ----------------------------------------------------------------------------
GIT_USER_NAME="${GIT_USER_NAME:-${USERNAME}@$(hostname)}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-${USERNAME}@$(hostname).local}"
log "Setting git identity for ${USERNAME}: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
sudo -u "${USERNAME}" -H git config --global user.name  "${GIT_USER_NAME}"
sudo -u "${USERNAME}" -H git config --global user.email "${GIT_USER_EMAIL}"

# ----------------------------------------------------------------------------
# 3. Deploy directories, owned by the agent
#     These live under /opt, so only root can create them — and ${USERNAME} has
#     no sudo to do it itself. setup-agent.sh then fills them in unprivileged.
#
#     Probably not standard to do it this way..., use it or not.
# ----------------------------------------------------------------------------
log "Creating /opt/stacks and /opt/repos for ${USERNAME}"
install -d -o "${USERNAME}" -g "${USERNAME}" /opt/stacks /opt/repos

# ----------------------------------------------------------------------------
# 4. Mise activation (the binary was installed system-wide by
#    setup-hetzner-vps.sh). Guarded by grep so re-running the script does not
#    stack up duplicate lines in .bashrc/.profile.
# ----------------------------------------------------------------------------
if [[ -x /usr/bin/mise ]]; then
  rc="/home/${USERNAME}/.bashrc"
  profile="/home/${USERNAME}/.profile"
  rc_line='eval "$(/usr/bin/mise activate bash)"'
  profile_line='eval "$(/usr/bin/mise activate bash --shims)"'

  if [[ -f "${rc}" ]] && ! grep -qF "mise activate bash" "${rc}"; then
    printf '\n# mise: manage tool versions per project\n%s\n' "${rc_line}" >> "${rc}"
    chown "${USERNAME}:${USERNAME}" "${rc}"
    log "Activated mise for ${USERNAME} (.bashrc)"
  fi

  # Shims in .profile so non-interactive / login contexts (cron, ssh
  # commands, GUI sessions) still find mise-managed tools on PATH.
  if ! grep -qsF "mise activate bash --shims" "${profile}"; then
    printf '\n# mise: shims for non-interactive shells\n%s\n' "${profile_line}" >> "${profile}"
    chown "${USERNAME}:${USERNAME}" "${profile}"
    log "Activated mise shims for ${USERNAME} (.profile)"
  fi
else
  warn "mise not found at /usr/bin/mise — skipped activation for ${USERNAME}."
fi

# ----------------------------------------------------------------------------
# 5. Groups
#    NOTE: the docker group is effectively root — a member can bind-mount / into
#    a privileged container. So this hands ${USERNAME} a root-equivalent
#    capability despite it having no sudo. It needs it to run its own compose
#    stacks; if you want the agent genuinely confined, switch it to rootless
#    Docker instead.
# ----------------------------------------------------------------------------
if getent group docker >/dev/null; then
  log "Adding ${USERNAME} to docker group"
  usermod -aG docker "${USERNAME}"
else
  warn "No docker group — is Docker installed? Skipped."
fi

log "Adding ${USERNAME} to adm group - grants read access to log files"
usermod -aG adm "${USERNAME}"

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
log "Agent setup complete."
cat <<EOF

Next steps:
  1. In a NEW terminal, verify SSH login:
         ssh ${USERNAME}@<server-ip>   # the agent (no sudo)

  2. Verify Docker (log in as ${USERNAME} so the docker group applies):
         docker run --rm hello-world
         docker compose version

  3. Syncthing (optional, for file sync between your laptop and server).
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

  4. NOT UP TO DATE:Run part 2 as ${USERNAME} — it sets up the Caddy stack and the git
     deploy repos. Copy it over and run it from that session (NOT as root,
     and not via sudo — the docker group only applies to a fresh login):
         scp setup-agent.sh ${USERNAME}@<server-ip>:~/
         ssh ${USERNAME}@<server-ip>
         bash ~/setup-agent.sh

Worth knowing:
  * ${USERNAME} has no sudo, but IS in the docker group — which is
    root-equivalent (it can bind-mount / into a privileged container). Treat
    "no sudo" as a guard against accidents, not as a sandbox.
  * mise is activated in ~/.bashrc, which only applies to interactive shells.

EOF
