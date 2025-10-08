#!/usr/bin/env bash
# ==============================
# Log Analyzer & Alert System - config.sh
# ==============================

# Logs to monitor (space-separated)
LOGS_TO_MONITOR=("/var/log/auth.log" "/var/log/syslog")

# Optional: Web server access log (nginx/apache). Leave empty to skip.
WEB_ACCESS_LOG="/var/log/nginx/access.log"

# Thresholds
SSH_FAIL_THRESHOLD=5          # failed ssh logins in the window
HTTP_5XX_THRESHOLD=20         # number of 5xx responses in the window
DISK_USAGE_THRESHOLD=85       # % used on any mounted filesystem to trigger alert

# Time window (for labeling; the script processes new lines since last run)
RUN_WINDOW_MINUTES=5

# Alert channels
ALERT_EMAIL=1                 # 1=enable, 0=disable
EMAIL_TO="admin@example.com"

ALERT_SLACK=0                 # 1=enable, 0=disable
SLACK_WEBHOOK_URL=""          # e.g., https://hooks.slack.com/services/XXX/YYY/ZZZ

# Internal dirs
STATE_DIR="./.state"
LOG_DIR="./logs"

# Tuning
MAX_TOP_IPS=5                 # top N malicious IPs to include
