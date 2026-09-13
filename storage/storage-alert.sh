#!/usr/bin/env bash
# Monitor a macOS volume and send notifications when free space gets low.
#
# Defaults:
#   volume: /
#   warning: at or below 25GB free
#   critical: at or below 10GB free
#   reminders: disabled
#
# Environment overrides:
#   STORAGE_ALERT_VOLUME (default /)
#   STORAGE_ALERT_WARN_FREE_GB (default 25)
#   STORAGE_ALERT_CRITICAL_FREE_GB (default 10)
#   STORAGE_ALERT_REMINDER_MINUTES (default 0)
#   NTFY_TOPIC
#
# Optional:
#   NTFY_TOPIC          - send alerts to ntfy.sh as a secondary channel
#   --ntfy-topic        - runtime override
#   --reminder-minutes  - repeat alerts on the same state every N minutes

set -eu -o pipefail

VOLUME="${STORAGE_ALERT_VOLUME:-/}"
WARN_FREE_GB="${STORAGE_ALERT_WARN_FREE_GB:-25}"
CRIT_FREE_GB="${STORAGE_ALERT_CRITICAL_FREE_GB:-10}"
REMINDER_MINUTES="${STORAGE_ALERT_REMINDER_MINUTES:-0}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
ALWAYS_NOTIFY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --volume)
      VOLUME="$2"
      shift 2
      ;;
    --warn-free-gb)
      WARN_FREE_GB="$2"
      shift 2
      ;;
    --critical-free-gb)
      CRIT_FREE_GB="$2"
      shift 2
      ;;
    --reminder-minutes)
      REMINDER_MINUTES="$2"
      shift 2
      ;;
    --ntfy-topic)
      NTFY_TOPIC="$2"
      shift 2
      ;;
    --always-notify)
      ALWAYS_NOTIFY=1
      shift 1
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: storage-alert.sh [options]

Options:
  --volume PATH            Volume to monitor (default /)
  --warn-free-gb N         Warning free-space threshold in GB (default: 25)
  --critical-free-gb N     Critical free-space threshold in GB (default: 10)
  --reminder-minutes N     Send the same warning again every N minutes (default: 0)
  --ntfy-topic TOPIC       Send notifications to ntfy.sh/TOPIC
  --always-notify          Notify on every run even if unchanged
  -h, --help              Show this help text
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--volume /] [--warn-free-gb 25] [--critical-free-gb 10] [--reminder-minutes 0] [--always-notify]"
      exit 1
      ;;
  esac
done

# Normalize numeric values
WARN_FREE_GB=$((WARN_FREE_GB + 0))
CRIT_FREE_GB=$((CRIT_FREE_GB + 0))
REMINDER_MINUTES=$((REMINDER_MINUTES + 0))

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/storage-alert"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/storage-alert"
mkdir -p "$STATE_DIR" "$LOG_DIR"

STATE_FILE="$STATE_DIR/last-state"
LOG_FILE="$LOG_DIR/storage-alert.log"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

notify() {
  local message="$1"
  local level="$2"
  local priority="3"
  local tags="disk,storage"
  local title="Disk space warning"
  local sound="Basso"

  if [ "$level" = "critical" ]; then
    priority="5"
    tags="disk,storage,warning"
    title="Disk space critical"
    sound="Sosumi"
  fi

  if command -v osascript >/dev/null 2>&1; then
    /usr/bin/osascript <<OSCRIPT
display notification "${message}" with title "${title}" sound name "${sound}"
OSCRIPT
  else
    log "WARN notification unavailable (osascript not found): $message"
  fi

  if [ -n "$NTFY_TOPIC" ]; then
    curl -fsS -m 10 \
      -H "Title: ${title}" \
      -H "Priority: ${priority}" \
      -H "Tags: ${tags}" \
      -d "${message}" \
      "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1 \
      || log "WARN ntfy post failed"
  fi
}

container_free_bytes="$(diskutil info -plist "$VOLUME" | plutil -extract APFSContainerFree raw - 2>/dev/null || true)"
container_total_bytes="$(diskutil info -plist "$VOLUME" | plutil -extract APFSContainerSize raw - 2>/dev/null || true)"
if [ -z "$container_free_bytes" ] || [ -z "$container_total_bytes" ]; then
  log "ERROR cannot read APFS container data for $VOLUME"
  exit 1
fi

free_gb="$(awk -v bytes="$container_free_bytes" 'BEGIN { printf "%.1f", bytes / 1000 / 1000 / 1000 }')"
total_gb="$(awk -v bytes="$container_total_bytes" 'BEGIN { printf "%.0f", bytes / 1000 / 1000 / 1000 }')"
warn_threshold_bytes=$((WARN_FREE_GB * 1000 * 1000 * 1000))
crit_threshold_bytes=$((CRIT_FREE_GB * 1000 * 1000 * 1000))
now_epoch="$(date +%s)"

state="ok"
reason=""
if (( container_free_bytes <= crit_threshold_bytes )); then
  state="critical"
  reason="${free_gb}GB free of ${total_gb}GB. At or below the critical ${CRIT_FREE_GB}GB limit."
elif (( container_free_bytes <= warn_threshold_bytes )); then
  state="warn"
  reason="${free_gb}GB free of ${total_gb}GB. At or below the warning ${WARN_FREE_GB}GB limit."
else
  reason="${free_gb}GB free of ${total_gb}GB."
fi

prev_state="ok"
prev_notified_epoch=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  read -r prev_state prev_notified_epoch < "$STATE_FILE" || true
  : "${prev_state:=ok}"
  : "${prev_notified_epoch:=0}"
fi

if [ "$state" = "ok" ]; then
  if [ "$prev_state" != "ok" ]; then
    log "RECOVERED ${VOLUME}: ${reason}"
  else
    log "OK ${VOLUME}: ${reason}"
  fi
  echo "ok $now_epoch" > "$STATE_FILE"
  exit 0
fi

should_notify=0
if [ "$ALWAYS_NOTIFY" -eq 1 ] || [ "$state" != "$prev_state" ]; then
  should_notify=1
elif [ "$prev_notified_epoch" -gt 0 ] && [ "$REMINDER_MINUTES" -gt 0 ]; then
  if (( now_epoch - prev_notified_epoch >= REMINDER_MINUTES * 60 )); then
    should_notify=1
  fi
fi

if [ "$should_notify" -eq 1 ]; then
  message="Mac storage ${state} on ${VOLUME}. ${reason}"
  notify "$message" "$state"
  log "ALERT ${message}"
  echo "$state $now_epoch" > "$STATE_FILE"
else
  log "SKIP duplicate ${state} alert for ${VOLUME}: ${reason}"
  # keep previous timestamp so reminders stay on schedule
fi

if [ "$state" = "critical" ]; then
  exit 2
fi

exit 1
