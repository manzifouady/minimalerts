# Minimal Server Alerts - minimalerts

[![Docker Publish](https://github.com/iamsoorena/minimalerts/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/iamsoorena/minimalerts/actions/workflows/docker-publish.yml)
[![GHCR Image](https://img.shields.io/badge/ghcr.io-iamsoorena%2Fminimalerts-blue)](https://github.com/iamsoorena/minimalerts/pkgs/container/minimalerts)

This folder contains an incident monitor that sends email and SMS alerts when the host is under stress.

📖 **For detailed architecture and lifecycle information, see [ARCHITECTURE.md](ARCHITECTURE.md)**

📦 **Current version: `1.0.0` (see [CHANGELOG.md](CHANGELOG.md))**

**Note**: This project uses a virtual environment (`.venv`) for Python dependencies. All commands should use the virtual environment's Python interpreter.

## TL;DR

This project watches your Linux server so you can sleep like a deterministic state machine.

- If the server is healthy: silence.
- If the server is melting: email and optional SMS.
- If it recovers: one recovery notice, no dramatic monologues.

Run it fast on any server:

```bash
git clone https://github.com/iamsoorena/minimalerts.git && cd minimalerts && docker compose up --build
```

No config present? It will ask for Gmail credentials on first run and generate config automatically.

## Why this exists (when Prometheus/Grafana already exist)

Because sometimes you need alerts in minutes, not a monitoring platform in phases.

Prometheus + Alertmanager + Grafana is excellent, but usually means:
- multiple components to deploy and connect
- rules, dashboards, retention, and routing to configure
- more moving parts than "I just need alerts on this one server"

Other good tools:
- Netdata
- Zabbix
- Nagios
- Uptime Kuma
- Datadog / New Relic

All of them are valid. Most are not a clean "under 60 seconds to useful server alerts" path for a fresh box.

`minimalerts` is the boring fast path:
- one command
- interactive first-run config (or mounted config)
- email/SMS alerts
- done

Now that we have AI agents, we can build what we actually need in hours, so I did.  
Think you can improve this more? Please don't hesitate to open a PR - AI will review and merge it.

## Checks

- High CPU busy %
- High CPU `iowait`
- High CPU `steal`
- High swap-out rate
- High root disk usage %
- High root inode usage %
- Low `MemAvailable`
- High RAM usage %
- High load-per-CPU
- Monitored services not active (`ssh`, `docker`)
- Recovery notification when the host returns healthy

## Files

- `monitor.py`: health check and notification sender
- `config.sample.json`: safe public template
- `config.json`: channels, recipients, thresholds (local secret file)
- `state.json`: internal monitor state (auto-created)
- `requirements.txt`: Python dependency list
- `Dockerfile`: container image definition
- `docker-entrypoint.sh`: container startup/config wizard
- `docker-compose.yml`: one-command Docker deployment

## Docker (One-Command Deploy)

You can run this project on any server with Docker in one command.

### Option A: Interactive setup in one command (recommended first run)

```bash
docker compose up --build
```

If `/data/config.json` does not exist, the container will ask for:
- Optional server name label (for alert subjects/messages)
- Gmail address
- Gmail App Password
- Alert recipient emails
- Optional SMS credentials

After setup, it runs continuously and checks health every 5 minutes.

If your environment still starts non-interactive and cannot prompt, run:

```bash
docker compose run --rm minimalerts setup
docker compose up -d
```

### Option B: Run with a prebuilt image

```bash
docker run --name minimalerts -it \
  --pid=host \
  -v minimalerts-data:/data \
  -v /:/hostfs:ro \
  -e MONITOR_PROC_PATH=/proc \
  -e MONITOR_ROOT_PATH=/hostfs \
  -e MONITOR_INTERVAL_SEC=300 \
  ghcr.io/iamsoorena/minimalerts:latest
```

The `latest` image is automatically published from `main` via GitHub Actions.

### Option C: Non-interactive setup with environment variables

```bash
docker run -d --name minimalerts --restart unless-stopped \
  --pid=host \
  -v minimalerts-data:/data \
  -v /:/hostfs:ro \
  -e MONITOR_PROC_PATH=/proc \
  -e MONITOR_ROOT_PATH=/hostfs \
  -e SERVER_NAME="prod-api-1" \
  -e SMTP_USER="your-email@gmail.com" \
  -e SMTP_PASSWORD="your16charapppass" \
  -e EMAIL_RECIPIENTS="ops1@example.com,ops2@example.com" \
  -e SMS_ENABLED="false" \
  ghcr.io/iamsoorena/minimalerts:latest
```

### Option D: Use your own config file as a volume

```bash
# first create local data folder and put your config there
mkdir -p ./monitor-data
cp config.sample.json ./monitor-data/config.json
# optional: set "server_name" in ./monitor-data/config.json

docker run -d --name minimalerts --restart unless-stopped \
  --pid=host \
  -v $(pwd)/monitor-data:/data \
  -v /:/hostfs:ro \
  -e MONITOR_PROC_PATH=/proc \
  -e MONITOR_ROOT_PATH=/hostfs \
  ghcr.io/iamsoorena/minimalerts:latest
```

### Docker Commands

```bash
# logs
docker logs -f minimalerts

# run one health check
docker exec -it minimalerts python3 /app/monitor.py --run-once

# verify Docker sees host-level metrics (CPU/RAM/disk)
docker exec -it minimalerts python3 /app/monitor.py --verify-host

# test notifications
docker exec -it minimalerts python3 /app/monitor.py --test-alert
```

### Send Test Notifications (Docker)

If the container is already running:

```bash
# email-only test
docker compose exec minimalerts python3 /app/monitor.py --test-email

# email + SMS test (SMS only if enabled in config)
docker compose exec minimalerts python3 /app/monitor.py --test-alert
```

If you prefer one-off commands without entering the running container:

```bash
# email-only test
docker compose run --rm minimalerts test-email

# email + SMS test
docker compose run --rm minimalerts test-alert
```

### Verify Host Metrics in Docker

Use this command to verify the container is reading full host metrics (not just container scope):

```bash
docker compose exec minimalerts python3 /app/monitor.py --verify-host
```

Look for:
- `warnings: []` (empty is good)
- `monitor_paths.root_path` set to `/hostfs`
- no warning about container filesystem or PID namespace

### Change Config When Using Docker

If you run with a named volume (example: `-v minimalerts-data:/data`), `config.json` lives at `/data/config.json` inside that volume.

```bash
# open shell in running container
docker exec -it minimalerts sh

# edit config
vi /data/config.json
# or
nano /data/config.json

# exit shell, then restart container to apply immediately
docker restart minimalerts
```

If you still prefer local editing, use copy-edit-copy:

```bash
docker cp minimalerts:/data/config.json ./config.json
# edit locally with your editor
docker cp ./config.json minimalerts:/data/config.json
docker restart minimalerts
```

If you use a bind mount (example: `-v $(pwd)/monitor-data:/data`), edit directly on host:

```bash
nano ./monitor-data/config.json
docker restart minimalerts
```

## Updating to Latest Version

### If you run from this repository (recommended)

```bash
git pull
docker compose pull
docker compose up -d --build
```

### If you run image-only deployment

```bash
docker pull ghcr.io/iamsoorena/minimalerts:latest
docker rm -f minimalerts
docker run -d --name minimalerts --restart unless-stopped \
  --pid=host \
  -v minimalerts-data:/data \
  -v /:/hostfs:ro \
  -e MONITOR_PROC_PATH=/proc \
  -e MONITOR_ROOT_PATH=/hostfs \
  ghcr.io/iamsoorena/minimalerts:latest
```

## Automatic Installation

The installation script guides you through configuration and automatically sets up everything:

```bash
# Clone or download the repository
git clone https://github.com/iamsoorena/minimalerts.git
cd minimalerts

# Run the interactive installation (requires root/sudo)
sudo ./install.sh
```

**What the installation script does:**
1. 🔧 **Interactive Configuration**: Guides you through server name, email (required), and SMS setup
2. 📧 **Email Setup**: Helps configure Gmail with step-by-step instructions
3. 📱 **SMS Setup**: Optional IPPanel SMS configuration
4. ⚙️ **Thresholds**: Customize monitoring thresholds or use defaults
5. ✅ **Validation**: Tests configuration before proceeding
6. 📧 **Mandatory Email Test**: Sends email-only test and requires confirmation
7. 🔒 **Security**: Sets proper file permissions
8. 🤖 **Systemd Setup**: Installs automatic 5-minute monitoring only after email is confirmed
9. ✅ **Verification**: Ensures everything works before completion

### Gmail Setup Guide
Before running the installation, prepare your Gmail credentials:

1. **Enable 2-Factor Authentication** on your Gmail account
2. **Generate App Password**:
   - Go to https://myaccount.google.com/security
   - Click "2-Step Verification" → "App passwords"
   - Select "Mail" and "Other (custom name)"
   - Enter "Server Monitor" as the name
   - Copy the 16-character password (ignore spaces)
3. **Installation will prompt** for your Gmail address and app password

### SMS Setup (Optional)
For SMS alerts via IPPanel:
- Sign up at https://ippanel.com
- Get your API Key from dashboard
- Create a SMS pattern for alerts
- Have your sender number ready

### Manual Installation (Alternative)

If you prefer manual setup:

```bash
# Copy configuration
cp config.sample.json config.json
# Edit config.json with your credentials

# Create virtual environment
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Install systemd files (replace default path with your current path)
sudo sed "s#/opt/server-alerts#$(pwd -P)#g" server-health-monitor.service | sudo tee /etc/systemd/system/server-health-monitor.service >/dev/null
sudo cp server-health-monitor.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now server-health-monitor.timer
```

`config.json`, `state.json`, and `.venv` are ignored by git to avoid leaking secrets.

### Server Name Behavior

- Set `server_name` in `config.json` to control how the host appears in alert messages.
- For Docker env-based setup, use `SERVER_NAME`.
- If `server_name` is empty or missing, alerts automatically include host identity from `ipinfo.io` (same idea as `curl ipinfo.io`) plus hostname.

## Automatic Scheduling

After installation, the monitor runs **automatically every 5 minutes** using systemd timers:

- **Service**: `server-health-monitor.service` - Executes the monitoring check
- **Timer**: `server-health-monitor.timer` - Triggers the service every 5 minutes
- **On Boot**: Starts 5 minutes after system boot
- **Persistent**: Catches up on missed runs after reboots

### Scheduling Details
```
Timer: server-health-monitor.timer
├── Runs every: 5 minutes
├── Accuracy: ±1 minute
├── On boot delay: 5 minutes
└── Persistent: Yes (catches up after downtime)
```

### Checking Schedule Status
```bash
# Check if timer is active
systemctl status server-health-monitor.timer

# See next run time
systemctl list-timers server-health-monitor.timer

# View execution logs
journalctl -u server-health-monitor.service -f
```

## Restarting Services After Configuration Changes

After modifying `config.json` (thresholds, recipients, API keys, etc.), the changes take effect immediately for manual runs. However, for automated monitoring:

### Manual Testing (Immediate)
```bash
# Test new configuration immediately
.venv/bin/python monitor.py --self-test

# Send test alert with new configuration
.venv/bin/python monitor.py --test-alert
```

### Systemd Service Management (if using systemd timers)
```bash
# Check service status
systemctl status server-health-monitor.service
systemctl status server-health-monitor.timer

# View recent logs
journalctl -u server-health-monitor.service -n 20 --no-pager
journalctl -u server-health-monitor.timer -n 10 --no-pager

# Restart timer (next run will use new config)
systemctl restart server-health-monitor.timer

# Force immediate check (bypasses timer)
systemctl start server-health-monitor.service
```

### Cron Job Alternative (if not using systemd)
If you're using cron instead of systemd timers, no restart is needed - the next scheduled run will automatically use the updated configuration.

## Useful Commands

### Installation & Status
```bash
# Install automatically (run as root)
sudo ./install.sh

# Check service status
systemctl status server-health-monitor.timer
systemctl status server-health-monitor.service

# View next scheduled run
systemctl list-timers server-health-monitor.timer

# View service logs
journalctl -u server-health-monitor.service -f
journalctl -u server-health-monitor.timer -f
```

### Manual Testing
```bash
# Run one health check
.venv/bin/python monitor.py --run-once

# Run internal self-test (no notifications sent)
.venv/bin/python monitor.py --self-test

# Send test alert (email + SMS)
.venv/bin/python monitor.py --test-alert

# Send test email only
.venv/bin/python monitor.py --test-email
```

### Configuration & Troubleshooting
```bash
# Edit configuration
nano config.json

# Restart timer after config changes
sudo systemctl restart server-health-monitor.timer

# Force immediate check
sudo systemctl start server-health-monitor.service

# View recent logs
journalctl -u server-health-monitor.service -n 20 --no-pager
```

## Default Thresholds (Current)

- `cpu_busy_percent`: `90`
- `iowait_percent`: `40`
- `steal_percent`: `10`
- `swap_out_per_sec`: `30`
- `mem_used_percent`: `88`
- `load1_per_cpu`: `3.0`
- `disk_used_percent`: `90`
- `inode_used_percent`: `90`
- `consecutive_failures`: `3`
- `cooldown_minutes`: `20`

These values are a balanced production baseline: sensitive enough to catch real incidents, but resistant to one-off spikes.
