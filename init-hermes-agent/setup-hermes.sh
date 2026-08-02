############################
# install dependencies (though the hermes script will do this itself)
# Read and adapt; do not pipe to bash.
############################

# run as username - no sudo needed
mise use -g python@3.11
mise use -g node@22

# Now change to sudo apt
# before running the script, sudo apt  as admin user that will be needed later.
su ${ADMIN_USERNAME} -c "sudo apt install ripgrep ffmpeg"
# Python build tools
su ${ADMIN_USERNAME} -c "sudo apt install build-essential python3-dev libffi-dev"
# Chromium system libraries for Playwright 
su ${ADMIN_USERNAME} -c "sudo apt install libnss3 libnspr4 fonts-liberation"

############################
# Most major dependencies installed, now install hermes
############################

curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

############################
# Finalize installation
############################
# run something like `export PATH="/home/aiagent/.local/bin:$PATH"` or `uv python update-shell`

# install chromium dependencies (fonts etc)
npx playwright install-deps --dry-run chromium 2>&1 | tail -n +2 | xargs # run by user, who installed node@22 above

sudo apt install <output> # run by ${ADMIN_USERNAME}
# sudo apt install fonts-freefont-ttf fonts-ipafont-gothic fonts-noto-color-emoji fonts-tlwg-loma-otf fonts-unifont fonts-wqy-zenhei libfontenc1 libxfont2 x11-xkb-utils xauth xfonts-cyrillic xfonts-encodings xfonts-scalable xfonts-utils xserver-common xvfb

############################
# Configure & Start service, Clean-Up
############################
# run hermes setup
# or copy the files '.env', 'config.yaml', '.gitignore' inside the '.hermes/'-folder

cd .hermes | git init
# + git add / git commit the few remaining files (most are excluded because of .gitignore)

# Start gateway
hermes gateway install --start-now --start-on-login
systemctl --user enable hermes-gateway
# For logs
# hermes gateway status
# journalctl --user -u hermes-gateway -f 

# Configure model providers
# GitHub provides some free credits for universities
# AI Usage dashboards:
# https://github.com/settings/billing/ai_usage?period=3&group=7&customer=11900714&chart_selection=2&view=models
# https://openrouter.ai/activity
hermes model

# Configure tools
hermes tools

# Update hermes: This pulls the latest code from main, updates dependencies, and prompts you to configure any new options that were added since your last update.
hermes update


############################
# Install https://github.com/nesquena/hermes-webui
# and reboot automatically
###########################

# ---- Config — adjust for your environment ----
WEBUI_REPO="/home/aiagent/hermes-webui"           # git clone of nesquena/hermes-webui
PYTHON_BIN="/home/aiagent/.local/share/mise/installs/python/3.11/bin/python3"
AGENT_VENV_BIN="/home/aiagent/.hermes/hermes-agent/venv/bin"
NODE_BIN="/home/aiagent/.local/share/mise/installs/node/22/bin"
HERMES_HOME="/home/aiagent/.hermes"
SYSTEMD_USER_DIR="/home/aiagent/.config/systemd/user"

# ---- 1. Clone the repo (skip if already present) ----
if [ ! -d "$WEBUI_REPO" ]; then
    cd "$(dirname "$WEBUI_REPO")"
    git clone https://github.com/nesquena/hermes-webui.git hermes-webui
fi

# ---- 2. systemd --user unit ----
mkdir -p "$SYSTEMD_USER_DIR"

cat > "$SYSTEMD_USER_DIR/hermes-webui.service" <<EOF
[Unit]
Description=Hermes Web UI
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=${WEBUI_REPO}
Environment="PATH=${AGENT_VENV_BIN}:${NODE_BIN}:/home/aiagent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="HERMES_HOME=${HERMES_HOME}"
# --foreground: bootstrap.py execv's into server.py, so systemd supervises
# the real server process directly rather than a launcher wrapper.
ExecStart=${PYTHON_BIN} ${WEBUI_REPO}/bootstrap.py --foreground
Restart=always
RestartSec=5
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

# ---- 3. Enable + start ----
# Linger lets the user unit start at boot without an active login session —
# without it, systemd --user units only run while you're logged in.
loginctl enable-linger "$(whoami)" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now hermes-webui.service

# ---- 4. Verify ----
sleep 2
systemctl --user status hermes-webui.service --no-pager -l
echo
curl -sS -m 5 "http://127.0.0.1:8787/health"

# change in webui-env file:
# HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace
# HERMES_WEBUI_SSE_CHUNKED=1
# and/or change it via the webui

# also put mise.toml in /workspace
# run `uv venv`

##########################
# Maybe we want a docker terminal that hermes runs in? Build local docker image.
##########################
docker build -t mise-dev --build-arg USER_UID="$(id -u)" --build-arg USER_GID="$(id -g)" .

docker run -it --rm \
  -v "$HOME/.local/share/mise:/home/ubuntu/.local/share/mise:ro" \
  -v "$HOME/.config/mise:/home/ubuntu/.config/mise:ro" \
  -v /var/log:/var/log:ro -v /var/log/journal:ro -v /etc/machine-id:ro \
  -v "$PWD:/work" -w /work \
  mise-dev:latest