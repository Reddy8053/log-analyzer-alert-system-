# 🔎 Log Analyzer & Alert System

A production-style **shell scripting project** that monitors critical logs, detects issues, and sends notifications. Built for DevOps/SRE portfolios.

## ✨ Features
- Incremental parsing of logs since last run (stateful)
- Detects **SSH brute-force attempts** from `/var/log/auth.log`
- Detects **HTTP 5xx spikes** from web access logs (nginx/apache)
- Checks **disk usage thresholds**
- Sends alerts via **email** (mail) and/or **Slack** (webhook)
- **Cron-friendly** with lightweight runtime and detailed logs

## 📦 Project Structure
```
log-analyzer-alert-system/
├── log_monitor.sh          # Main script
├── config.sh               # Configurable thresholds & alert settings
├── logs/
│   └── log_monitor.log     # Operational log
├── .state/                 # Line bookmarks per log file
├── alerts/
│   └── sample_alert.txt    # Example alert snapshot
├── LICENSE
└── README.md
```

## 🚀 Quick Start
1. **Clone or unzip** the repo.
2. Configure:
   ```bash
   cp config.sh config.sh # already present; just edit
   vim config.sh
   ```
   - Set `EMAIL_TO`, optionally set `SLACK_WEBHOOK_URL`.
   - Adjust thresholds (`SSH_FAIL_THRESHOLD`, `HTTP_5XX_THRESHOLD`, `DISK_USAGE_THRESHOLD`).
   - Set `WEB_ACCESS_LOG` if you have nginx/apache access logs.
3. **Run once manually** to create state files and verify:
   ```bash
   chmod +x log_monitor.sh
   ./log_monitor.sh
   ```
4. **(Optional) Schedule with cron** to run every 5 minutes:
   ```bash
   crontab -e
   */5 * * * * /path/to/log-analyzer-alert-system/log_monitor.sh >> /path/to/log-analyzer-alert-system/logs/cron.out 2>&1
   ```

## 🧪 Testing (without root)
If you don’t have access to system logs, you can **point the script to sample files**:
- Create a test `auth.log` and `access.log` in your project and temporarily set:
  ```bash
  LOGS_TO_MONITOR=("$(pwd)/auth.log")
  WEB_ACCESS_LOG="$(pwd)/access.log"
  ```
- Append lines and re-run to simulate new activity:
  ```bash
  echo "Failed password for invalid user test from 192.0.2.10 port 4242 ssh2" >> auth.log
  echo '127.0.0.1 - - [08/Oct/2025:10:00:01 +0000] "GET /health HTTP/1.1" 500 12 "-" "curl/8.0"' >> access.log
  ./log_monitor.sh
  ```

## 🔔 Alerts
- **Email:** requires `mail` (mailutils or bsd-mailx). Configure `EMAIL_TO`.
- **Slack:** set `ALERT_SLACK=1` and `SLACK_WEBHOOK_URL` to an **Incoming Webhook** URL.

Alert snapshots are saved under `alerts/alert_YYYYMMDD_HHMMSS.txt`.

## 🧰 Requirements
- Bash 4+
- Standard POSIX utilities: `sed`, `awk`, `grep`, `df`, `wc`
- Optional: `mail` for email; `curl` for Slack

## 🔒 Security & Ops Notes
- The script reads logs; ensure proper permissions or run with a service user that has read access.
- State is tracked by **line number per file**; if logs rotate between runs, the script will start from the top of the new file (safe default). For high-throughput environments, consider extending to inode+offset tracking.
- Keep your Slack webhook secret (don’t commit real URLs).

## 📝 License
MIT
