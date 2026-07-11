#!/usr/bin/env bash
# cmux-autocolor.sh — color cmux workspaces deterministically by project path.
#
# Identity = git toplevel of the workspace's directory (fallback: the dir itself),
# hashed into a fixed 16-color palette. Same repo -> same color, forever, seeded.
#
# Snapshot-at-creation: a workspace's existing custom_color IS the cache. We only
# color workspaces whose color is unset, so:
#   - color never flickers when panes/focus/cwd drift after creation
#   - manual color choices are respected
# Set CMUX_AUTOCOLOR_OVERRIDE=1 to recolor even already-colored workspaces.
#
# Runs as a launchd LaunchAgent: startup sweep, then blocks on `cmux events`.
set -uo pipefail

CMUX="${CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
command -v "$CMUX" >/dev/null 2>&1 || CMUX="cmux"
PY="$(command -v python3 || echo python3)"

# The socket runs in password mode (automation.socketControlMode), so an
# externally-launched daemon must authenticate. Read the secret straight from
# the local cmux.json — it never leaves this machine, never hits the plist.
CMUX_JSON="${CMUX_JSON:-$HOME/.config/cmux/cmux.json}"
if [ -z "${CMUX_SOCKET_PASSWORD:-}" ] && [ -f "$CMUX_JSON" ]; then
  CMUX_SOCKET_PASSWORD="$("$PY" -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("automation",{}).get("socketPassword","") or "")
except Exception: pass' "$CMUX_JSON" 2>/dev/null)"
  export CMUX_SOCKET_PASSWORD
fi
CURSOR="${CMUX_AUTOCOLOR_CURSOR:-$HOME/.cache/cmux-autocolor.seq}"
LOGF="${CMUX_AUTOCOLOR_LOG:-$HOME/.cache/cmux-autocolor.log}"
mkdir -p "$(dirname "$CURSOR")"

# 16 named colors cmux understands (workspace-action --color).
COLORS=(Red Crimson Orange Amber Olive Green Teal Aqua Blue Navy Indigo Purple Magenta Rose Brown Charcoal)

# Append directly to the log file each call — the daemon blocks forever, so
# relying on stdout (block-buffered to a file) would never flush.
log() { printf '%s cmux-autocolor: %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOGF"; }

# path -> stable identity to hash (git toplevel, else the path itself)
anchor_for() {
  local dir="$1" root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && { printf '%s' "$root"; return; }
  printf '%s' "$dir"
}

# identity string -> named color (stable, seeded)
color_for() {
  local h
  h=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s' "${COLORS[$(( h % 16 ))]}"
}

# workspace_id -> "<current_directory>\t<custom_color>" (custom_color empty if unset)
ws_info() {
  "$CMUX" rpc workspace.list 2>/dev/null | "$PY" -c '
import sys, json
wid = sys.argv[1]
try:
    ws = json.load(sys.stdin)["workspaces"]
except Exception:
    sys.exit(0)
for w in ws:
    if w.get("id") == wid:
        print("%s\t%s" % (w.get("current_directory") or "", w.get("custom_color") or ""))
        break
' "$1"
}

# Color one workspace by id (skips already-colored unless OVERRIDE).
apply() {
  local id="$1" info dir cur
  [ -n "$id" ] || return 0
  info=$(ws_info "$id") || return 0
  dir=${info%%$'\t'*}
  cur=${info#*$'\t'}
  [ -n "$dir" ] || return 0
  if [ -n "$cur" ] && [ "${CMUX_AUTOCOLOR_OVERRIDE:-0}" != "1" ]; then
    return 0  # already colored — leave it (snapshot cache)
  fi
  local color; color=$(color_for "$(anchor_for "$dir")")
  if "$CMUX" workspace-action --workspace "$id" --action set-color --color "$color" >/dev/null 2>&1; then
    log "colored $id ($dir) -> $color"
  fi
}

# Wait for the cmux socket so we don't hot-loop while the app is down.
until "$CMUX" ping >/dev/null 2>&1; do sleep 5; done
log "socket up; sweeping existing workspaces"

# Startup sweep: color every currently-uncolored workspace.
"$CMUX" rpc workspace.list 2>/dev/null | "$PY" -c '
import sys, json
try:
    for w in json.load(sys.stdin)["workspaces"]:
        print(w["id"])
except Exception:
    pass
' | while read -r id; do apply "$id"; done

log "streaming workspace.created events"

# Live: react to new workspaces forever. --reconnect + cursor-file survive brief
# socket blips; if the stream ends (cmux quit), we exit and launchd relaunches us.
"$CMUX" events --category workspace --name workspace.created \
  --cursor-file "$CURSOR" --reconnect 2>/dev/null \
| while IFS= read -r line; do
    id=$(printf '%s' "$line" | "$PY" -c 'import sys,json
try: print(json.load(sys.stdin).get("workspace_id") or "")
except Exception: print("")' 2>/dev/null)
    apply "$id"
  done

log "event stream ended; exiting for launchd restart"
