#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import smtplib
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from email.message import EmailMessage

try:
    from ippanel import Client
except Exception:
    Client = None


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
STATE_PATH = os.path.join(BASE_DIR, "state.json")


def now_utc_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except Exception as exc:
        print(f"[{now_utc_iso()}] failed to load {path}: {exc}")
        return default


def save_json(path, data):
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


def read_proc_stat_cpu():
    with open("/proc/stat", "r", encoding="utf-8") as f:
        first = f.readline().strip()
    parts = first.split()
    if not parts or parts[0] != "cpu":
        raise RuntimeError("unexpected /proc/stat format")
    vals = [int(x) for x in parts[1:11]]
    keys = [
        "user",
        "nice",
        "system",
        "idle",
        "iowait",
        "irq",
        "softirq",
        "steal",
        "guest",
        "guest_nice",
    ]
    return dict(zip(keys, vals))


def read_mem_available_mb():
    with open("/proc/meminfo", "r", encoding="utf-8") as f:
        txt = f.read()
    m = re.search(r"^MemAvailable:\s+(\d+)\s+kB$", txt, re.MULTILINE)
    if not m:
        return None
    return int(m.group(1)) // 1024


def read_mem_total_mb():
    with open("/proc/meminfo", "r", encoding="utf-8") as f:
        txt = f.read()
    m = re.search(r"^MemTotal:\s+(\d+)\s+kB$", txt, re.MULTILINE)
    if not m:
        return None
    return int(m.group(1)) // 1024


def read_load1():
    with open("/proc/loadavg", "r", encoding="utf-8") as f:
        return float(f.read().split()[0])


def read_pswpout():
    with open("/proc/vmstat", "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("pswpout "):
                return int(line.split()[1])
    return None


def read_root_disk_used_pct():
    total, used, _free = shutil.disk_usage("/")
    if total <= 0:
        return None
    return (used * 100.0) / total


def read_root_inode_used_pct():
    s = os.statvfs("/")
    if s.f_files <= 0:
        return None
    used = s.f_files - s.f_ffree
    return (used * 100.0) / s.f_files


def service_active(service):
    unit = service if service.endswith(".service") else f"{service}.service"
    p = subprocess.run(
        ["systemctl", "is-active", unit],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    return p.stdout.strip() == "active"


def send_email(cfg, subject, body):
    email_cfg = cfg.get("email", {})
    sender = email_cfg.get("host_user")
    password = email_cfg.get("host_password")
    recipients = email_cfg.get("recipients", [])
    smtp_host = email_cfg.get("smtp_host", "smtp.gmail.com")
    smtp_port = int(email_cfg.get("smtp_port", 587))

    if not sender or not password or not recipients:
        raise RuntimeError("email config missing sender/password/recipients")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = sender
    msg["To"] = ", ".join(recipients)
    msg.set_content(body)

    with smtplib.SMTP(smtp_host, smtp_port, timeout=20) as s:
        s.starttls()
        s.login(sender, password)
        s.send_message(msg)


def normalize_phone(phone):
    digits = re.sub(r"\D", "", phone or "")
    if digits.startswith("98"):
        return digits
    if digits.startswith("0"):
        return "98" + digits[1:]
    if digits.startswith("9"):
        return "98" + digits
    raise ValueError(f"unsupported phone format: {phone}")


def send_sms(cfg, code):
    if Client is None:
        raise RuntimeError("ippanel package is not installed")

    sms_cfg = cfg.get("sms", {})
    api_key = sms_cfg.get("api_key")
    sender = sms_cfg.get("sender_number")
    pattern_code = sms_cfg.get("pattern_code")
    recipients = sms_cfg.get("recipients", [])

    if not api_key or not sender or not pattern_code or not recipients:
        raise RuntimeError("sms config missing api_key/sender/pattern/recipients")

    client = Client(api_key)
    pattern_values = {"verification-code": str(code)}

    errors = []
    for phone in recipients:
        try:
            dest = normalize_phone(phone)
            client.send_pattern(pattern_code, sender, dest, pattern_values)
        except Exception as exc:
            errors.append(f"{phone}: {exc}")

    if errors:
        raise RuntimeError("sms send errors: " + " | ".join(errors))


def send_notifications(cfg, subject, body, sms_code):
    errors = []
    try:
        send_email(cfg, subject, body)
    except Exception as exc:
        errors.append(f"email failed: {exc}")

    # Check if SMS is enabled before attempting to send
    if cfg.get("sms", {}).get("enabled", False):
        try:
            send_sms(cfg, sms_code)
        except Exception as exc:
            errors.append(f"sms failed: {exc}")

    return errors


def evaluate(cfg, state, metrics):
    t = cfg.get("thresholds", {})
    reasons = []

    iowait_limit = float(t.get("iowait_percent", 20))
    steal_limit = float(t.get("steal_percent", 10))
    swapout_limit = float(t.get("swap_out_per_sec", 40))
    memavail_limit = float(t.get("mem_available_mb", 1200))
    mem_used_pct_limit = float(t.get("mem_used_percent", 85))
    cpu_busy_limit = float(t.get("cpu_busy_percent", 90))
    load_limit = float(t.get("load1_per_cpu", 2.0))
    disk_used_limit = float(t.get("disk_used_percent", 90))
    inode_used_limit = float(t.get("inode_used_percent", 90))

    if metrics.get("iowait_pct") is not None and metrics["iowait_pct"] >= iowait_limit:
        reasons.append(f"iowait high ({metrics['iowait_pct']:.2f}% >= {iowait_limit}%)")
    if metrics.get("steal_pct") is not None and metrics["steal_pct"] >= steal_limit:
        reasons.append(f"steal high ({metrics['steal_pct']:.2f}% >= {steal_limit}%)")
    if metrics.get("swap_out_per_sec") is not None and metrics["swap_out_per_sec"] >= swapout_limit:
        reasons.append(
            f"swap out high ({metrics['swap_out_per_sec']:.2f}/s >= {swapout_limit}/s)"
        )
    if metrics.get("mem_available_mb") is not None and metrics["mem_available_mb"] <= memavail_limit:
        reasons.append(
            f"MemAvailable low ({metrics['mem_available_mb']}MB <= {memavail_limit}MB)"
        )
    if metrics.get("mem_used_pct") is not None and metrics["mem_used_pct"] >= mem_used_pct_limit:
        reasons.append(
            f"RAM usage high ({metrics['mem_used_pct']:.2f}% >= {mem_used_pct_limit}%)"
        )
    if metrics.get("cpu_busy_pct") is not None and metrics["cpu_busy_pct"] >= cpu_busy_limit:
        reasons.append(
            f"CPU usage high ({metrics['cpu_busy_pct']:.2f}% >= {cpu_busy_limit}%)"
        )
    if metrics.get("load1_per_cpu") is not None and metrics["load1_per_cpu"] >= load_limit:
        reasons.append(
            f"load per cpu high ({metrics['load1_per_cpu']:.2f} >= {load_limit})"
        )
    if metrics.get("disk_used_pct") is not None and metrics["disk_used_pct"] >= disk_used_limit:
        reasons.append(
            f"disk usage high ({metrics['disk_used_pct']:.2f}% >= {disk_used_limit}%)"
        )
    if metrics.get("inode_used_pct") is not None and metrics["inode_used_pct"] >= inode_used_limit:
        reasons.append(
            f"inode usage high ({metrics['inode_used_pct']:.2f}% >= {inode_used_limit}%)"
        )

    for svc, is_active in metrics.get("service_active", {}).items():
        if not is_active:
            reasons.append(f"service down ({svc})")

    return reasons


def build_alert(hostname, reasons, metrics):
    lines = [
        f"Server health alert on {hostname}",
        f"Time (UTC): {now_utc_iso()}",
        "",
        "Reasons:",
    ]
    for r in reasons:
        lines.append(f"- {r}")

    lines += [
        "",
        "Metrics:",
        f"- iowait_pct: {metrics.get('iowait_pct')}",
        f"- steal_pct: {metrics.get('steal_pct')}",
        f"- swap_out_per_sec: {metrics.get('swap_out_per_sec')}",
        f"- mem_available_mb: {metrics.get('mem_available_mb')}",
        f"- mem_total_mb: {metrics.get('mem_total_mb')}",
        f"- mem_used_mb: {metrics.get('mem_used_mb')}",
        f"- mem_used_pct: {metrics.get('mem_used_pct')}",
        f"- cpu_busy_pct: {metrics.get('cpu_busy_pct')}",
        f"- load1: {metrics.get('load1')}",
        f"- cpu_count: {metrics.get('cpu_count')}",
        f"- load1_per_cpu: {metrics.get('load1_per_cpu')}",
        f"- disk_used_pct: {metrics.get('disk_used_pct')}",
        f"- inode_used_pct: {metrics.get('inode_used_pct')}",
        f"- services: {metrics.get('service_active')}",
    ]
    return "\n".join(lines)


def build_recovery_message(hostname, metrics):
    return (
        f"Server recovery notice on {hostname}\n"
        f"Time (UTC): {now_utc_iso()}\n\n"
        "The host has returned to healthy state after a previous alert.\n\n"
        "Current quick metrics:\n"
        f"- cpu_busy_pct: {metrics.get('cpu_busy_pct')}\n"
        f"- iowait_pct: {metrics.get('iowait_pct')}\n"
        f"- steal_pct: {metrics.get('steal_pct')}\n"
        f"- mem_used_pct: {metrics.get('mem_used_pct')}\n"
        f"- disk_used_pct: {metrics.get('disk_used_pct')}\n"
        f"- load1_per_cpu: {metrics.get('load1_per_cpu')}\n"
        f"- services: {metrics.get('service_active')}\n"
    )


def collect_metrics(cfg, state, now_ts):
    cpu = read_proc_stat_cpu()
    pswpout = read_pswpout()
    mem_avail = read_mem_available_mb()
    mem_total = read_mem_total_mb()
    load1 = read_load1()
    cpu_count = os.cpu_count() or 1
    disk_used_pct = read_root_disk_used_pct()
    inode_used_pct = read_root_inode_used_pct()

    services = {}
    for svc in cfg.get("services", ["ssh", "docker"]):
        services[svc] = service_active(svc)

    iowait_pct = None
    steal_pct = None
    cpu_busy_pct = None
    swap_out_per_sec = None

    if state.get("last_cpu") and state.get("last_ts"):
        prev = state["last_cpu"]
        total_prev = sum(prev.values())
        total_now = sum(cpu.values())
        delta_total = total_now - total_prev
        if delta_total > 0:
            iowait_pct = (cpu["iowait"] - prev["iowait"]) * 100.0 / delta_total
            steal_pct = (cpu["steal"] - prev["steal"]) * 100.0 / delta_total
            delta_idle = (cpu["idle"] - prev["idle"]) + (cpu["iowait"] - prev["iowait"])
            cpu_busy_pct = ((delta_total - delta_idle) * 100.0) / delta_total

    if state.get("last_pswpout") is not None and state.get("last_ts"):
        dt = now_ts - float(state["last_ts"])
        if dt > 0:
            swap_out_per_sec = (pswpout - int(state["last_pswpout"])) / dt

    mem_used_mb = None
    mem_used_pct = None
    if mem_total is not None and mem_avail is not None:
        mem_used_mb = max(mem_total - mem_avail, 0)
        if mem_total > 0:
            mem_used_pct = (mem_used_mb * 100.0) / mem_total

    metrics = {
        "iowait_pct": round(iowait_pct, 2) if iowait_pct is not None else None,
        "steal_pct": round(steal_pct, 2) if steal_pct is not None else None,
        "cpu_busy_pct": round(cpu_busy_pct, 2) if cpu_busy_pct is not None else None,
        "swap_out_per_sec": round(swap_out_per_sec, 2) if swap_out_per_sec is not None else None,
        "mem_available_mb": mem_avail,
        "mem_total_mb": mem_total,
        "mem_used_mb": mem_used_mb,
        "mem_used_pct": round(mem_used_pct, 2) if mem_used_pct is not None else None,
        "load1": load1,
        "cpu_count": cpu_count,
        "load1_per_cpu": round(load1 / max(cpu_count, 1), 3),
        "disk_used_pct": round(disk_used_pct, 2) if disk_used_pct is not None else None,
        "inode_used_pct": round(inode_used_pct, 2) if inode_used_pct is not None else None,
        "service_active": services,
    }
    return cpu, pswpout, metrics


def run_once():
    cfg = load_json(CONFIG_PATH, {})
    if not cfg:
        print(f"[{now_utc_iso()}] missing config at {CONFIG_PATH}")
        return 2

    state = load_json(
        STATE_PATH,
        {
            "last_cpu": None,
            "last_pswpout": None,
            "last_ts": None,
            "breach_streak": 0,
            "last_alert_ts": 0,
            "incident_open": False,
        },
    )

    now_ts = time.time()
    cpu, pswpout, metrics = collect_metrics(cfg, state, now_ts)

    reasons = evaluate(cfg, state, metrics)
    if reasons:
        state["breach_streak"] = int(state.get("breach_streak", 0)) + 1
    else:
        state["breach_streak"] = 0

    consecutive = int(cfg.get("consecutive_failures", 3))
    cooldown = int(cfg.get("cooldown_minutes", 20)) * 60
    should_alert = (
        len(reasons) > 0
        and state["breach_streak"] >= consecutive
        and (now_ts - float(state.get("last_alert_ts", 0))) >= cooldown
    )

    hostname = socket.gethostname()
    if should_alert:
        subject = f"[ALERT] {hostname} health issue detected"
        body = build_alert(hostname, reasons, metrics)
        delivery_errors = send_notifications(cfg, subject, body, int(now_ts) % 1000000)

        if delivery_errors:
            print(f"[{now_utc_iso()}] ALERT trigger with delivery issues: {'; '.join(delivery_errors)}")
        else:
            print(f"[{now_utc_iso()}] ALERT sent successfully")
        state["last_alert_ts"] = now_ts
        state["incident_open"] = True
    else:
        if reasons:
            print(
                f"[{now_utc_iso()}] breach detected (streak {state['breach_streak']}/{consecutive}), waiting for confirmation: {reasons}"
            )
        else:
            if state.get("incident_open") and bool(cfg.get("notify_recovery", True)):
                recovery_subject = f"[RECOVERY] {hostname} health recovered"
                recovery_body = build_recovery_message(hostname, metrics)
                recovery_errors = send_notifications(
                    cfg, recovery_subject, recovery_body, int(now_ts) % 1000000
                )
                if recovery_errors:
                    print(
                        f"[{now_utc_iso()}] recovery notify had delivery issues: {'; '.join(recovery_errors)}"
                    )
                else:
                    print(f"[{now_utc_iso()}] recovery notification sent")
            state["incident_open"] = False
            print(f"[{now_utc_iso()}] healthy")

    state["last_cpu"] = cpu
    state["last_pswpout"] = pswpout
    state["last_ts"] = now_ts
    save_json(STATE_PATH, state)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Server health monitor")
    parser.add_argument("--run-once", action="store_true", help="run a single check")
    parser.add_argument("--test-alert", action="store_true", help="send a test alert immediately")
    parser.add_argument("--self-test", action="store_true", help="collect metrics and print evaluation without sending notifications")
    args = parser.parse_args()

    cfg = load_json(CONFIG_PATH, {})
    if args.test_alert:
        hostname = socket.gethostname()
        subject = f"[TEST] {hostname} monitor alert channel test"
        body = (
            f"This is a test alert from {hostname} at {now_utc_iso()}.\n"
            "If you received this, email channel is configured correctly."
        )
        errors = []
        try:
            send_email(cfg, subject, body)
        except Exception as exc:
            errors.append(f"email failed: {exc}")

        # Check if SMS is enabled before attempting to send test SMS
        if cfg.get("sms", {}).get("enabled", False):
            try:
                send_sms(cfg, int(time.time()) % 1000000)
            except Exception as exc:
                errors.append(f"sms failed: {exc}")
        if errors:
            print(f"[{now_utc_iso()}] test alert partial/failed: {'; '.join(errors)}")
            return 1
        print(f"[{now_utc_iso()}] test alert sent")
        return 0

    if args.self_test:
        state = load_json(
            STATE_PATH,
            {
                "last_cpu": None,
                "last_pswpout": None,
                "last_ts": None,
                "breach_streak": 0,
                "last_alert_ts": 0,
                "incident_open": False,
            },
        )
        now_ts = time.time()
        _cpu, _pswpout, metrics = collect_metrics(cfg, state, now_ts)
        reasons = evaluate(cfg, state, metrics)
        print(
            json.dumps(
                {
                    "time_utc": now_utc_iso(),
                    "metrics": metrics,
                    "reasons": reasons,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.run_once:
        return run_once()

    return run_once()


if __name__ == "__main__":
    sys.exit(main())
