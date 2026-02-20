# Server Alerts

This folder contains an incident monitor that sends email and SMS alerts when the host is under stress.

📖 **For detailed architecture and lifecycle information, see [ARCHITECTURE.md](ARCHITECTURE.md)**

**Note**: This project uses a virtual environment (`.venv`) for Python dependencies. All commands should use the virtual environment's Python interpreter.

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

## Automatic Installation

The installation script automatically sets up everything including systemd services and scheduling:

```bash
# Clone or download the repository
cd /root
git clone https://github.com/iamsoorena/minimalerts.git server-alerts
cd server-alerts

# Run the automatic installation (requires root/sudo)
sudo ./install.sh
```

**What the installation script does:**
1. ✅ Creates `config.json` from template
2. ✅ Sets up Python virtual environment (`.venv`)
3. ✅ Installs all dependencies
4. ✅ Configures proper file permissions
5. ✅ Installs systemd service and timer
6. ✅ Enables automatic monitoring (runs every 5 minutes)
7. ✅ Tests the installation

### Manual Installation (Alternative)

If you prefer manual setup:

```bash
# Copy configuration
cp config.sample.json config.json
# Edit config.json with your credentials

# Create virtual environment
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Install systemd files
sudo cp server-health-monitor.service /etc/systemd/system/
sudo cp server-health-monitor.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now server-health-monitor.timer
```

`config.json`, `state.json`, and `.venv` are ignored by git to avoid leaking secrets.

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
/root/server-alerts/.venv/bin/python /root/server-alerts/monitor.py --self-test

# Send test alert with new configuration
/root/server-alerts/.venv/bin/python /root/server-alerts/monitor.py --test-alert
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
- `mem_available_mb`: `2048`
- `mem_used_percent`: `88`
- `load1_per_cpu`: `3.0`
- `disk_used_percent`: `90`
- `inode_used_percent`: `90`
- `consecutive_failures`: `3`
- `cooldown_minutes`: `20`

These values are a balanced production baseline: sensitive enough to catch real incidents, but resistant to one-off spikes.
