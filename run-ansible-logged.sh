#!/usr/bin/env bash
# Runs ansible-playbook and writes a log and an HTML report to logs/.
# The playbook comes first; further arguments go to ansible-playbook:
#     ./run-ansible-logged.sh vps-init-playbook.yml
#     ./run-ansible-logged.sh vps-init-playbook.yml --tags docker
#     ./run-ansible-logged.sh install-apps-playbook.yml --check --diff
set -uo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" != *.yml ]]; then
  echo "Usage: $0 <playbook>.yml [ansible-playbook options]" >&2
  exit 2
fi
PLAYBOOK=$1
NAME=$(basename "${PLAYBOOK}" .yml)

# Logs can contain details about the server: readable by root and the sudo
# group only (who could read them with sudo anyway).
umask 027
mkdir -p logs
chgrp -R sudo logs 2>/dev/null && chmod g+s logs   # new logs get group sudo too
chmod -R g+rX,o-rwx logs   # also for logs written before this line existed
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="logs/${TIMESTAMP}_${NAME}.log"
REPORT_FILE="logs/${TIMESTAMP}_${NAME}.html"

echo "Starting ${PLAYBOOK} at $(date)"
ansible-playbook "$@" 2>&1 | tee "${LOG_FILE}"
ANSIBLE_STATUS=${PIPESTATUS[0]}   # ansible-playbook's exit code, not tee's

if [[ ${ANSIBLE_STATUS} -eq 0 ]]; then
  STATUS_CLASS=success; STATUS_TEXT=SUCCESS
else
  STATUS_CLASS=failure; STATUS_TEXT="FAILURE (exit code ${ANSIBLE_STATUS})"
fi

# The log can contain <, > and &, so escape it before embedding it in HTML.
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

echo "Generating HTML report..."
cat > "${REPORT_FILE}" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Ansible Execution Report - ${TIMESTAMP}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .success { color: green; }
        .failure { color: red; }
        .section { margin-bottom: 20px; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>Ansible Execution Report</h1>
    <div class="section">
        <h2>Execution Summary</h2>
        <p><strong>Date:</strong> $(date)</p>
        <p><strong>Playbook:</strong> ${PLAYBOOK}</p>
        <p><strong>Status:</strong> <span class="${STATUS_CLASS}">${STATUS_TEXT}</span></p>
        <p><strong>Log File:</strong> ${LOG_FILE}</p>
    </div>
    <div class="section">
        <h2>Server Information</h2>
        <pre>Host: $(hostname)
User: $(id -un)</pre>
    </div>
    <div class="section">
        <h2>Execution Log</h2>
        <pre>$(html_escape < "${LOG_FILE}")</pre>
    </div>
</body>
</html>
EOF

echo "Execution completed with status: ${ANSIBLE_STATUS}"
echo "Log saved to: ${LOG_FILE}"
echo "Report saved to: ${REPORT_FILE}"

# Open the report in the default browser if on a desktop environment
if [[ -n "${DISPLAY:-}" ]] && command -v xdg-open >/dev/null; then
  xdg-open "${REPORT_FILE}"
fi

exit "${ANSIBLE_STATUS}"
