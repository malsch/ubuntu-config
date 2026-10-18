#!/usr/bin/env bash
#
# Mininmal git-based docker compose deployments. NOT TESTED!!!!!
#
# General idea, when you push to a bare repo on the server, a post-receive hook fast-forwards a working clone and runs a deploy command (e.g. docker compose up -d).
# see, eg. https://symbioquine.net/2021-11-30-minimal-git-based-docker-compose-deployments/

# This user has no sudo — nothing below needs it.
#
# Run as the agent user (NOT root, NOT via sudo):
#     ssh -p <port> aiagent@<server-ip>
#     bash ~/setup-agent.sh
#
# Idempotent: re-running is safe.

# ----------------------------------------------------------------------------
# 3. Create new directories  -> not sure if its worth keeping somewhere.
#     These live under /opt, so only root can create them — and ${USERNAME} has
#     no sudo to do it itself. setup-agent.sh then fills them in unprivileged.
#
#     Probably not standard to do it this way..., use it or not.
# ----------------------------------------------------------------------------
log "Creating /opt/stacks and /opt/repos for ${USERNAME}"
install -d -o "${USERNAME}" -g "${USERNAME}" /opt/stacks /opt/repos

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

GIT_DEPLOY_PROJECTS=(
  hermes
  # "api"
)
GIT_DEFAULT_BRANCH="main"
GIT_DEPLOY_CMD="docker compose down; docker compose up -d"   # run in the deploy dir per push - or add option: --build
                                                # (runs via bash -c: ';' and '&&' OK, but no '|' or '&' — they break the sed that installs the hook)
log()  { echo -e "\n\033[1;32m==>\033[0m \033[1m$*\033[0m"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

if [[ $EUID -eq 0 ]]; then
  echo "Run as the agent user, not root (this script owns the user-level setup)." >&2
  exit 1
fi
USERNAME="$(id -un)"


# ----------------------------------------------------------------------------
# 3. Clone-based git deployment (per project)
#    Per NAME: a bare push-target repo, a working clone (deploy dir), and a
#    post-receive hook that fast-forwards the clone and redeploys. All of it
#    runs as ${USERNAME}, so repos and commits belong to them, not root.
#    Idempotent: existing repos/clones/hooks are reused or refreshed.
# ----------------------------------------------------------------------------
if [[ ${#GIT_DEPLOY_PROJECTS[@]} -gt 0 ]]; then
  log "Setting up clone-based git deployment"

  for NAME in "${GIT_DEPLOY_PROJECTS[@]}"; do
    REPO="/opt/repos/${NAME}.git"
    CLONE="/opt/stacks/${NAME}"

    # Bare push-target repo.
    if [[ ! -d "${REPO}" ]]; then
      git init --bare -b "${GIT_DEFAULT_BRANCH}" "${REPO}"
    fi

    # Working clone (deploy dir). Refuse to clobber a non-empty, non-repo dir.
    if [[ -d "${CLONE}/.git" ]]; then
      :  # already a clone
    elif [[ -e "${CLONE}" && -n "$(ls -A "${CLONE}" 2>/dev/null)" ]]; then
      warn "${CLONE} exists and is not empty; skipping clone for '${NAME}'."
      warn "Pick a fresh path or remove that directory, then re-run."
    else
      git clone "${REPO}" "${CLONE}"
    fi

    # post-receive hook: fast-forward the clone, then run the deploy command.
    HOOK_TMP="$(mktemp)"
    cat > "${HOOK_TMP}" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
CLONE_DIR="__CLONE_DIR__"
BRANCH="__BRANCH__"
DEPLOY_CMD="__DEPLOY_CMD__"
# Hooks inherit GIT_DIR pointing at the bare repo; clear it so the commands
# below act on the clone, not the bare repo.
unset GIT_DIR GIT_WORK_TREE
while read -r _old _new ref; do
  if [[ "${ref}" != "refs/heads/${BRANCH}" ]]; then
    echo ">>> ${ref#refs/heads/} pushed (only ${BRANCH} deploys); skipping."
    continue
  fi
  echo ">>> Updating ${CLONE_DIR} to ${BRANCH}"
  cd "${CLONE_DIR}"
  git fetch --quiet origin
  if git rev-parse --verify -q HEAD >/dev/null; then
    # Fast-forward only: never overwrite uncommitted/divergent local work —
    # fail the deploy loudly instead so nothing is silently lost.
    if ! git merge --ff-only "origin/${BRANCH}"; then
      echo "!!! ${CLONE_DIR} diverged from origin/${BRANCH} or has uncommitted"
      echo "!!! changes. Deploy aborted — reconcile on the server, then re-push."
      exit 1
    fi
  else
    git checkout -B "${BRANCH}" "origin/${BRANCH}"   # first deploy (empty clone)
  fi
  echo ">>> Running: ${DEPLOY_CMD}"
  # Run through 'mise exec' so the deploy command sees the tool versions pinned
  # by this project's mise.toml. Hooks are non-interactive, so the 'mise
  # activate' line in ~/.bashrc never fires here — without this, only system
  # binaries are on PATH. Harmless when the project has no mise.toml.
  if [[ -x /usr/bin/mise ]]; then
    /usr/bin/mise exec -- bash -c "${DEPLOY_CMD}"
  else
    bash -c "${DEPLOY_CMD}"
  fi
  echo ">>> Deploy complete."
done
HOOK
    sed -i \
      -e "s|__CLONE_DIR__|${CLONE}|g" \
      -e "s|__BRANCH__|${GIT_DEFAULT_BRANCH}|g" \
      -e "s|__DEPLOY_CMD__|${GIT_DEPLOY_CMD}|g" \
      "${HOOK_TMP}"
    install -m 755 "${HOOK_TMP}" "${REPO}/hooks/post-receive"
    rm -f "${HOOK_TMP}"
    log "  '${NAME}' ready — push to: ${USERNAME}@<server-ip>:${REPO}"
  done
fi

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
cat <<EOF

Next steps:
  1. Deploy a project (for each NAME in GIT_DEPLOY_PROJECTS). On your laptop,
     inside the project's git repo:
         git remote add prod ${USERNAME}@<server-ip>:/opt/repos/<name>.git
         git push -u prod ${GIT_DEFAULT_BRANCH}
     The push checks out into /opt/stacks/<name> and runs:
         ${GIT_DEPLOY_CMD}
     To edit on the server instead: cd /opt/stacks/<name>, commit, and
     'git push' (its origin is the bare repo) — then 'git pull' on your laptop.

     Commit a .dockerignore (must list .git) and a .gitignore (must list .env
     and other secrets) in each project. Because the deploy may run with --build,
     .dockerignore keeps .git and secrets out of your images; .gitignore keeps
     credentials out of the repo. Add both on your LAPTOP and commit them — do
     not create them in the server's clone.

EOF
