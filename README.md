# Server Alerts

This folder contains an incident monitor that sends email and SMS alerts when the host is under stress.

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

## Install / Enable

```bash
cp /root/server-alerts/config.sample.json /root/server-alerts/config.json
# edit config.json with your real credentials/recipients

python3 -m venv /root/server-alerts/.venv
/root/server-alerts/.venv/bin/pip install -U pip
/root/server-alerts/.venv/bin/pip install -r /root/server-alerts/requirements.txt
chmod 600 /root/server-alerts/config.json
systemctl daemon-reload
systemctl enable --now server-health-monitor.timer
```

`config.json`, `state.json`, and `.venv` are ignored by git to avoid leaking secrets.

## Useful Commands

```bash
# run one health check
/root/server-alerts/.venv/bin/python /root/server-alerts/monitor.py --run-once

# run internal self-test (no notifications sent)
/root/server-alerts/.venv/bin/python /root/server-alerts/monitor.py --self-test

# send a test alert (email + sms)
/root/server-alerts/.venv/bin/python /root/server-alerts/monitor.py --test-alert

# inspect logs
journalctl -u server-health-monitor.service -n 100 --no-pager
journalctl -u server-health-monitor.timer -n 50 --no-pager
```

## Default Thresholds (Current)

- `cpu_busy_percent`: `90`
- `iowait_percent`: `20`
- `steal_percent`: `10`
- `swap_out_per_sec`: `30`
- `mem_available_mb`: `2048`
- `mem_used_percent`: `88`
- `load1_per_cpu`: `1.8`
- `disk_used_percent`: `90`
- `inode_used_percent`: `90`
- `consecutive_failures`: `3`
- `cooldown_minutes`: `20`

These values are a balanced production baseline: sensitive enough to catch real incidents, but resistant to one-off spikes.
