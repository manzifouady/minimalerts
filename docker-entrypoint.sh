#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/app"
DATA_DIR="${MONITOR_DATA_DIR:-/data}"
CONFIG_PATH="${MONITOR_CONFIG_PATH:-$DATA_DIR/config.json}"
STATE_PATH="${MONITOR_STATE_PATH:-$DATA_DIR/state.json}"
INTERVAL_SEC="${MONITOR_INTERVAL_SEC:-300}"

export MONITOR_CONFIG_PATH="$CONFIG_PATH"
export MONITOR_STATE_PATH="$STATE_PATH"

mkdir -p "$DATA_DIR"

create_config_from_env() {
  python3 - <<'PY'
import json
import os

sample_path = "/app/config.sample.json"
config_path = os.environ["MONITOR_CONFIG_PATH"]

with open(sample_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

sender = os.environ.get("SMTP_USER", "").strip()
password = os.environ.get("SMTP_PASSWORD", "").strip()
recipients_raw = os.environ.get("EMAIL_RECIPIENTS", "").strip()
recipients = [x.strip() for x in recipients_raw.split(",") if x.strip()]

if not sender or not password or not recipients:
    raise SystemExit("Missing SMTP_USER/SMTP_PASSWORD/EMAIL_RECIPIENTS")

cfg.setdefault("email", {})
cfg["email"]["host_user"] = sender
cfg["email"]["host_password"] = password
cfg["email"]["recipients"] = recipients
cfg["email"]["smtp_host"] = os.environ.get("SMTP_HOST", cfg["email"].get("smtp_host", "smtp.gmail.com"))
cfg["email"]["smtp_port"] = int(os.environ.get("SMTP_PORT", cfg["email"].get("smtp_port", 587)))

sms_enabled = os.environ.get("SMS_ENABLED", "false").strip().lower() in {"1", "true", "yes", "y"}
cfg.setdefault("sms", {})
cfg["sms"]["enabled"] = sms_enabled

if sms_enabled:
    cfg["sms"]["api_key"] = os.environ.get("SMS_API_KEY", cfg["sms"].get("api_key", "")).strip()
    cfg["sms"]["pattern_code"] = os.environ.get("SMS_PATTERN_CODE", cfg["sms"].get("pattern_code", "")).strip()
    cfg["sms"]["sender_number"] = os.environ.get("SMS_SENDER_NUMBER", cfg["sms"].get("sender_number", "")).strip()
    sms_recipients_raw = os.environ.get("SMS_RECIPIENTS", "").strip()
    if sms_recipients_raw:
        cfg["sms"]["recipients"] = [x.strip() for x in sms_recipients_raw.split(",") if x.strip()]

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

interactive_config_wizard() {
  echo ""
  echo "No config file found at $CONFIG_PATH"
  echo "Starting interactive setup."
  echo ""
  echo "Gmail setup help:"
  echo "1) https://myaccount.google.com/security"
  echo "2) Enable 2-Step Verification"
  echo "3) App passwords -> create Mail app password"
  echo ""

  local smtp_user smtp_password recipients setup_sms sms_api_key sms_pattern sms_sender sms_recipients
  read -r -p "Gmail address: " smtp_user
  while [[ -z "$smtp_user" || "$smtp_user" != *"@"* ]]; do
    read -r -p "Enter a valid Gmail address: " smtp_user
  done

  read -r -s -p "Gmail App Password (16 chars): " smtp_password
  echo ""
  smtp_password="${smtp_password// /}"
  while [[ ${#smtp_password} -ne 16 ]]; do
    read -r -s -p "Password must be 16 chars. Re-enter: " smtp_password
    echo ""
    smtp_password="${smtp_password// /}"
  done

  read -r -p "Recipient emails (comma-separated): " recipients
  while [[ -z "$recipients" ]]; do
    read -r -p "At least one recipient is required: " recipients
  done

  export SMTP_USER="$smtp_user"
  export SMTP_PASSWORD="$smtp_password"
  export EMAIL_RECIPIENTS="$recipients"

  read -r -p "Enable SMS now? (y/n): " setup_sms
  if [[ "$setup_sms" =~ ^[Yy]$ ]]; then
    export SMS_ENABLED="true"
    read -r -p "IPPanel API key: " sms_api_key
    read -r -p "Pattern code: " sms_pattern
    read -r -p "Sender number (e.g. +983000505): " sms_sender
    read -r -p "SMS recipients (comma-separated): " sms_recipients
    export SMS_API_KEY="$sms_api_key"
    export SMS_PATTERN_CODE="$sms_pattern"
    export SMS_SENDER_NUMBER="$sms_sender"
    export SMS_RECIPIENTS="$sms_recipients"
  else
    export SMS_ENABLED="false"
  fi

  create_config_from_env
  chmod 600 "$CONFIG_PATH"
  echo "Config written to $CONFIG_PATH"
}

if [[ ! -f "$CONFIG_PATH" ]]; then
  if [[ -n "${SMTP_USER:-}" && -n "${SMTP_PASSWORD:-}" && -n "${EMAIL_RECIPIENTS:-}" ]]; then
    create_config_from_env
    chmod 600 "$CONFIG_PATH"
    echo "Config created from environment variables."
  elif [[ -t 0 && -t 1 ]]; then
    interactive_config_wizard
  else
    echo "Config not found at $CONFIG_PATH."
    echo "Either mount a config volume or provide SMTP_USER, SMTP_PASSWORD, EMAIL_RECIPIENTS."
    exit 1
  fi
fi

# Run explicit command modes first.
if [[ "${1:-}" == "setup" ]]; then
  python3 "$APP_DIR/monitor.py" --self-test
  echo "Setup completed. You can now run the container in background mode."
  exit 0
fi

if [[ "${1:-}" == "once" ]]; then
  exec python3 "$APP_DIR/monitor.py" --run-once
fi

if [[ "${1:-}" == "self-test" ]]; then
  exec python3 "$APP_DIR/monitor.py" --self-test
fi

if [[ "${1:-}" == "test-alert" ]]; then
  exec python3 "$APP_DIR/monitor.py" --test-alert
fi

if [[ "${1:-}" == "test-email" ]]; then
  exec python3 "$APP_DIR/monitor.py" --test-email
fi

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

echo "Starting monitor loop (interval: ${INTERVAL_SEC}s)"
while true; do
  python3 "$APP_DIR/monitor.py" --run-once || true
  sleep "$INTERVAL_SEC"
done
