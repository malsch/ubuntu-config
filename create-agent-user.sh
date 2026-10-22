#!/usr/bin/env bash
# Creates the agent account 'aiagent' with create-user-playbook.yml:
#   no sudo, bash, docker + adm + shared groups, lingering off,
#   SSH keys copied from you (the admin who runs this with sudo).
# Only the password is asked. Re-running is safe.
#
#     sudo ./create-agent-user.sh
#
# Extra arguments go to ansible-playbook, e.g. -e username=otheragent.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
cd "$(dirname "$0")"

exec ansible-playbook create-user-playbook.yml \
  -e username=aiagent \
  -e sudo=no -e sudo_timeout_hours=24 -e passwordless_sudo=no \
  -e ssh_keys_from=me -e shell=bash \
  -e docker=yes -e adm=yes -e shared=yes \
  -e linger=no \
  "$@"
