#!/bin/bash

set -euo pipefail

echo "Server Health Monitor Installation"
echo "================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="$(pwd -P)"
SERVICE_NAME="server-health-monitor"
VENV_DIR="$INSTALL_DIR/.venv"
CONFIG_PATH="$INSTALL_DIR/config.json"

print_status() { echo -e "${GREEN}OK${NC} $1"; }
print_warning() { echo -e "${YELLOW}WARN${NC} $1"; }
print_error() { echo -e "${RED}ERR${NC} $1"; }
print_info() { echo -e "${BLUE}INFO${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    print_error "Run this script as root (sudo ./install.sh)."
    exit 1
fi

if [[ ! -f "$INSTALL_DIR/monitor.py" ]] || [[ ! -f "$INSTALL_DIR/config.sample.json" ]]; then
    print_error "Run install.sh from the repository root."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    print_error "python3 is required."
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    print_error "systemctl is required for automatic scheduling."
    exit 1
fi

print_info "Install directory: $INSTALL_DIR"

if [[ ! -f "$CONFIG_PATH" ]]; then
    cp "$INSTALL_DIR/config.sample.json" "$CONFIG_PATH"
    print_status "Created config.json from template"
else
    print_warning "config.json already exists and will be updated interactively."
fi

echo ""
read -r -p "Optional server name for alerts (leave empty to auto-use ipinfo.io): " server_name

echo ""
echo "EMAIL CONFIGURATION (REQUIRED)"
echo "=============================="
echo "Use a Gmail account with an App Password."
echo "1) Visit https://myaccount.google.com/security"
echo "2) Enable 2-Step Verification"
echo "3) Open App passwords, create one for Mail"
echo "4) Use the 16-character app password below (no spaces)"
echo ""

read -r -p "Gmail address: " user_email
while [[ -z "$user_email" || "$user_email" != *"@"* ]]; do
    read -r -p "Enter a valid email address: " user_email
done

read -r -s -p "Gmail App Password (16 chars): " app_password
echo ""
app_password="${app_password// /}"
while [[ ${#app_password} -ne 16 ]]; do
    read -r -s -p "App Password must be 16 chars. Re-enter: " app_password
    echo ""
    app_password="${app_password// /}"
done

read -r -p "Recipient emails (comma-separated): " recipients_input
while [[ -z "$recipients_input" ]]; do
    read -r -p "At least one recipient is required: " recipients_input
done

export CONFIG_PATH user_email app_password recipients_input server_name
python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_PATH"]
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

recipients = [x.strip() for x in os.environ["recipients_input"].split(",") if x.strip()]
if not recipients:
    raise SystemExit("no valid recipients provided")

cfg.setdefault("email", {})
cfg["server_name"] = os.environ.get("server_name", "").strip()
cfg["email"]["host_user"] = os.environ["user_email"].strip()
cfg["email"]["host_password"] = os.environ["app_password"].strip()
cfg["email"]["recipients"] = recipients
cfg["email"].setdefault("smtp_host", "smtp.gmail.com")
cfg["email"].setdefault("smtp_port", 587)

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
print_status "Saved email configuration"

echo ""
read -r -p "Configure SMS now? (y/n): " setup_sms
if [[ "$setup_sms" =~ ^[Yy]$ ]]; then
    read -r -p "IPPanel API key: " api_key
    read -r -p "Pattern code: " pattern_code
    read -r -p "Sender number (e.g. +983000505): " sender_number
    read -r -p "SMS recipients (comma-separated): " sms_recipients_input

    export api_key pattern_code sender_number sms_recipients_input
    python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_PATH"]
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

recipients = [x.strip() for x in os.environ["sms_recipients_input"].split(",") if x.strip()]
cfg.setdefault("sms", {})
cfg["sms"]["enabled"] = True
cfg["sms"]["api_key"] = os.environ["api_key"].strip()
cfg["sms"]["pattern_code"] = os.environ["pattern_code"].strip()
cfg["sms"]["sender_number"] = os.environ["sender_number"].strip()
cfg["sms"]["recipients"] = recipients

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    print_status "Saved SMS configuration"
else
    python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_PATH"]
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

cfg.setdefault("sms", {})
cfg["sms"]["enabled"] = False

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    print_info "SMS disabled for now"
fi

echo ""
read -r -p "Use default thresholds from config.sample.json? (y/n): " use_defaults
if [[ ! "$use_defaults" =~ ^[Yy]$ ]]; then
    read -r -p "cpu_busy_percent (default 90): " cpu_threshold
    read -r -p "mem_available_mb (default 2048): " mem_threshold
    read -r -p "disk_used_percent (default 90): " disk_threshold
    cpu_threshold="${cpu_threshold:-90}"
    mem_threshold="${mem_threshold:-2048}"
    disk_threshold="${disk_threshold:-90}"
    export cpu_threshold mem_threshold disk_threshold
    python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_PATH"]
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

cfg.setdefault("thresholds", {})
cfg["thresholds"]["cpu_busy_percent"] = int(os.environ["cpu_threshold"])
cfg["thresholds"]["mem_available_mb"] = int(os.environ["mem_threshold"])
cfg["thresholds"]["disk_used_percent"] = int(os.environ["disk_threshold"])

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    print_status "Saved custom thresholds"
fi

if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
    print_status "Created virtual environment"
else
    print_status "Using existing virtual environment"
fi

"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" >/dev/null 2>&1
print_status "Installed Python dependencies"

chmod 600 "$CONFIG_PATH"
chmod 755 "$INSTALL_DIR/monitor.py"
chmod 755 "$INSTALL_DIR/install.sh"
print_status "Set file permissions"

if "$VENV_DIR/bin/python" "$INSTALL_DIR/monitor.py" --self-test >/dev/null 2>&1; then
    print_status "Configuration self-test passed"
else
    print_error "Configuration self-test failed."
    exit 1
fi

echo ""
print_info "Sending mandatory EMAIL-ONLY test before scheduling..."
if "$VENV_DIR/bin/python" "$INSTALL_DIR/monitor.py" --test-email >/dev/null 2>&1; then
    print_status "Test email sent."
else
    print_error "Failed to send test email. Fix config.json and rerun install."
    exit 1
fi

read -r -p "Did you receive the test email? (y/n): " email_received
if [[ ! "$email_received" =~ ^[Yy]$ ]]; then
    print_error "Email was not confirmed. Installation aborted before scheduler setup."
    exit 1
fi

sed "s#/opt/server-alerts#$INSTALL_DIR#g" "$INSTALL_DIR/server-health-monitor.service" > "/etc/systemd/system/${SERVICE_NAME}.service"
cp "$INSTALL_DIR/server-health-monitor.timer" "/etc/systemd/system/${SERVICE_NAME}.timer"
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"
print_status "Installed and started systemd timer"

echo ""
print_status "Installation completed successfully."
echo "Timer status: $(systemctl is-active "${SERVICE_NAME}.timer")"
echo ""
echo "Useful commands:"
echo "  systemctl status ${SERVICE_NAME}.timer"
echo "  journalctl -u ${SERVICE_NAME}.service -f"
echo "  $VENV_DIR/bin/python $INSTALL_DIR/monitor.py --run-once"
echo "  $VENV_DIR/bin/python $INSTALL_DIR/monitor.py --test-alert"