#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------
# Log Analyzer & Alert System - log_monitor.sh
# ----------------------------------------------
# Features:
#  - Incremental parsing since last run (per-log line bookmark)
#  - Detects failed SSH logins from /var/log/auth.log
#  - Detects HTTP 5xx spikes from web access log
#  - Checks disk usage thresholds
#  - Sends alerts via email or Slack
#  - Writes an operational log
# ----------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$SCRIPT_DIR/alerts"

TS() { date +"%Y-%m-%d %H:%M:%S"; }
LOG() { echo "$(TS) | $*" | tee -a "$LOG_DIR/log_monitor.log" >/dev/null; }

alert_buffer=""

add_alert() {
  local msg="$1"
  alert_buffer+="$msg\n"
  LOG "ALERT queued: ${msg%%$'\n'*}"
}

save_state() {
  local file="$1"; local lines="$2"
  local base="$(basename "$file")"
  echo "$lines" > "$STATE_DIR/${base}.state"
}

load_state() {
  local file="$1"
  local base="$(basename "$file")"
  if [[ -f "$STATE_DIR/${base}.state" ]]; then
    cat "$STATE_DIR/${base}.state"
  else
    echo "0"
  fi
}

new_lines_since_last_run() {
  local file="$1"
  [[ -f "$file" ]] || { echo ""; return; }
  local total_lines; total_lines=$(wc -l < "$file" || echo 0)
  local last; last=$(load_state "$file")
  local start=$(( last + 1 ))
  if (( start <= 0 )); then start=1; fi
  if (( start > total_lines )); then
    echo ""
  else
    sed -n "${start},${total_lines}p" "$file"
  fi
}

# ============================
# SSH Failed Login Detector
# ============================
check_ssh_failures() {
  local file="/var/log/auth.log"

  if [[ ! -f "$file" ]]; then
    LOG "auth.log not found at $file; skipping SSH checks"
    return
  fi

  local new; new="$(new_lines_since_last_run "$file")"
  local total_lines; total_lines=$(wc -l < "$file" || echo 0)
  save_state "$file" "$total_lines"

  [[ -z "$new" ]] && { LOG "No new auth.log lines"; return; }

  # Count failures
  local fails_count
  fails_count=$(grep -E "Failed password|Invalid user|authentication failure" <<<"$new" | wc -l || echo 0)

  # SAFE arithmetic
  # SAFE arithmetic
if ((${fails_count:-0} > 0)); then
  # Extract top IPs
  local top_ips
  top_ips=$(grep -Eo "from ([0-9]{1,3}\.){3}[0-9]{1,3}" <<<"$new" \
    | awk '{print $2}' | sort | uniq -c | sort -nr | head -n "${MAX_TOP_IPS:-5}")
  # SAFE threshold comparison
  if (( ${fails_count:-0} >= ${SSH_FAIL_THRESHOLD:-5} )); then
    add_alert "$(printf "🚨 SSH brute-force suspected: %d failed logins in last ~%d min.\nTop IPs (count):\n%s\n" \
      "${fails_count:-0}" "${RUN_WINDOW_MINUTES:-5}" "${top_ips:-none}")"
  else
    LOG "SSH failures below threshold: ${fails_count:-0} (< ${SSH_FAIL_THRESHOLD:-5})"
  fi
fi
}

# ============================
# HTTP 5xx Detector
# ============================
check_http_5xx() {
  local file="$WEB_ACCESS_LOG"
  [[ -n "$file" && -f "$file" ]] || { LOG "Web access log not set or missing; skipping HTTP 5xx check"; return; }

  local new; new="$(new_lines_since_last_run "$file")"
  local total_lines; total_lines=$(wc -l < "$file" || echo 0)
  save_state "$file" "$total_lines"

  [[ -z "$new" ]] && { LOG "No new access.log lines"; return; }

  local count_5xx
  count_5xx=$(awk '{code=$9} code ~ /^[5][0-9][0-9]$/' <<<"$new" | wc -l || echo 0)

  if (( ${count_5xx:-0} >= ${HTTP_5XX_THRESHOLD:-10} )); then
    local top_paths
    top_paths=$(awk 'match($0,/\"(GET|POST|PUT|PATCH|DELETE|HEAD) ([^ ]+)/,m){print m[2]}' <<<"$new" \
      | sort | uniq-c | sort -nr | head -n 5)

    add_alert "$(
      printf "🔥 HTTP 5xx spike: %d errors in last ~%d min.\nTop endpoints:\n%s\n" \
      "${count_5xx:-0}" "${RUN_WINDOW_MINUTES:-5}" "${top_paths:-none}"
    )"
  else
    LOG "HTTP 5xx below threshold: ${count_5xx:-0} (< ${HTTP_5XX_THRESHOLD:-10})"
  fi
}

# ============================
# Disk Usage Monitor
# ============================
check_disk_usage() {
  local overuse
  overuse=$(df -hP | awk -v th="${DISK_USAGE_THRESHOLD:-90}" '
    NR > 1 {
      gsub(/%/, "", $5)
      if ($5+0 >= th) { printf "%s (%s%%) on %s\n", $1, $5, $6 }
    }')

  if [[ -n "$overuse" ]]; then
    add_alert "$(printf "💽 Disk usage high (>%d%%):\n%s" "${DISK_USAGE_THRESHOLD:-90}" "$overuse")"
  else
    LOG "Disk usage OK (< ${DISK_USAGE_THRESHOLD:-90}%)"
  fi
}

# ============================
# Alert Dispatch
# ============================
send_email() {
  local subject="$1"; local body="$2"
  if [[ "${ALERT_EMAIL:-0}" -eq 1 ]]; then
    if command -v mail >/dev/null; then
      echo -e "$body" | mail -s "$subject" "$EMAIL_TO" || LOG "mail send failed"
      LOG "Email sent to $EMAIL_TO"
    else
      LOG "mail command not found; cannot send email"
    fi
  fi
}

send_slack() {
  local body="$1"
  if [[ "${ALERT_SLACK:-0}" -eq 1 && -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    if command -v curl >/dev/null; then
      curl -sS -X POST -H 'Content-type: application/json' \
        --data "$(printf '{"text": "%s"}' "$(echo -e "$body" | sed 's/"/\\"/g')")" \
        "$SLACK_WEBHOOK_URL" >/dev/null || LOG "Slack send failed"
      LOG "Slack notification sent"
    else
      LOG "curl not found; cannot send Slack notification"
    fi
  fi
}

# ============================
# Main Routine
# ============================
main() {
  LOG "===== Log monitor run started ====="
  check_ssh_failures
  check_http_5xx
  check_disk_usage

  if [[ -n "$alert_buffer" ]]; then
    local subject="Log Monitor Alerts ($(hostname)) - $(date +"%Y-%m-%d %H:%M")"
    local body
    body="$(
      printf "⏱ Window ~ last %d minutes\nHost: %s\n\n%s" \
      "${RUN_WINDOW_MINUTES:-5}" "$(hostname)" "$alert_buffer"
    )"

    local fname="$SCRIPT_DIR/alerts/alert_$(date +%Y%m%d_%H%M%S).txt"
    echo -e "$body" > "$fname"
    LOG "Alert saved to $fname"

    send_email "$subject" "$body"
    send_slack "$body"
  else
    LOG "No alerts generated this run"
  fi

  LOG "===== Log monitor run finished ====="
}

main "$@"
