#!/usr/bin/env bash
# RAM watchdog (macOS has no cgroups). Dev tooling spawned under cmux/claude —
# Playwright headless Chromium + vitest worker pools — can saturate this 32GB box
# and swap-thrash the WHOLE machine (happened 2026-06-07: a `ship` workflow hit
# 32GB). This is a targeted, GENTLE OOM-killer: when the combined RSS of
# unambiguously-disposable dev-test processes stays over THRESHOLD_GB for two
# consecutive checks, it SIGTERMs the single heaviest one.
#
# Safety: it ONLY ever matches `chrome-headless-shell` (Playwright) and `vitest`
# workers — never your real Chrome, never a vite dev server you're using, never the
# claude daemon or cmux, never another app. SIGTERM only (graceful), every kill
# logged to ~/.local/state/mem-watchdog/log.jsonl. Tune via MEM_WATCHDOG_THRESHOLD_GB.
#
# NOT `set -e`: a transient ps/awk hiccup must never abort the watchdog.
set -uo pipefail

THRESHOLD_GB="${MEM_WATCHDOG_THRESHOLD_GB:-20}"
INTERVAL="${MEM_WATCHDOG_INTERVAL:-15}"
# Disposable dev-test processes safe to terminate to relieve pressure. The [v]
# trick keeps the watchdog's own grep from matching itself.
PATTERN='chrome-headless-shell|[v]itest'
STATE_DIR="${HOME}/.local/state/mem-watchdog"
LOG="${STATE_DIR}/log.jsonl"
mkdir -p "$STATE_DIR"

log() { printf '%s\n' "$*" >>"$LOG"; }
thresh_kb=$(awk -v g="$THRESHOLD_GB" 'BEGIN{printf "%d", g*1024*1024}')
log "{\"ts\":\"$(date '+%F %T %Z')\",\"event\":\"watchdog-start\",\"threshold_gb\":$THRESHOLD_GB,\"interval_s\":$INTERVAL}"

over=0
while true; do
  cands="$(ps -axo rss=,pid=,args= 2>/dev/null | grep -iE "$PATTERN" | grep -v grep || true)"
  if [ -z "$cands" ]; then over=0; sleep "$INTERVAL"; continue; fi
  total_kb=$(printf '%s\n' "$cands" | awk '{s+=$1} END{print s+0}')
  if [ "${total_kb:-0}" -gt "$thresh_kb" ]; then
    over=$((over + 1))
    if [ "$over" -ge 2 ]; then
      heavy="$(printf '%s\n' "$cands" | sort -rn -k1,1 | head -1)"
      top_kb=$(printf '%s' "$heavy" | awk '{print $1}')
      top_pid=$(printf '%s' "$heavy" | awk '{print $2}')
      top_cmd=$(printf '%s' "$heavy" | awk '{$1="";$2="";sub(/^ +/,"");print}' | cut -c1-120 | sed 's/"/\\"/g')
      total_gb=$(awk -v k="$total_kb" 'BEGIN{printf "%.1f", k/1024/1024}')
      top_gb=$(awk -v k="$top_kb" 'BEGIN{printf "%.1f", k/1024/1024}')
      if [ -n "${top_pid:-}" ] && kill "$top_pid" 2>/dev/null; then act="SIGTERM"; else act="kill-failed"; fi
      log "{\"ts\":\"$(date '+%F %T %Z')\",\"action\":\"$act\",\"total_gb\":$total_gb,\"threshold_gb\":$THRESHOLD_GB,\"killed_pid\":${top_pid:-0},\"killed_gb\":$top_gb,\"cmd\":\"$top_cmd\"}"
      over=0
    fi
  else
    over=0
  fi
  sleep "$INTERVAL"
done
