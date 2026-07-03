#!/usr/bin/env bash
# Centralized Claude Code hook timing wrapper (dotfiles).
#
# Claude runs hooks with a delicate protocol: the event JSON arrives on stdin,
# stdout can carry context/permission decisions, and the exit code can BLOCK the
# action (exit 2). So this wrapper is deliberately TRANSPARENT — it does not parse,
# aggregate, or rewrite anything. It runs the real hook with stdin/stdout/stderr
# inherited, times how long it took, appends one JSONL line to the shared hooks
# log, and exits with the hook's own exit code. The protocol is passed through
# byte-for-byte; the only added cost is the timing math (free via $EPOCHREALTIME).
#
# Usage (from settings.json):
#   dispatch.sh <EventName> <label> <command> [args...]
# e.g.
#   dispatch.sh PreToolUse guard-npm /Users/calum/.claude/hooks/guard-npm.sh
#
# Wrap only hooks you own. Externally-managed hooks (e.g. NotchBar's, tagged with
# a `# notchbar-...` comment its installer greps for) must stay unwrapped.
set -uo pipefail

# Resolve through the ~/.claude/hooks symlink to find the dotfiles lib alongside us.
SELF="$0"
link="$(readlink "$SELF" 2>/dev/null || true)"
if [ -n "$link" ]; then
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
fi
HERE="$(cd "$(dirname "$SELF")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../lib/hooklog.sh" 2>/dev/null || {
  hooklog_now_ms() { echo 0; }
  hooklog_step() { :; }
}

event="${1:-unknown}"
label="${2:-unknown}"
shift 2 2>/dev/null || true

scope="${CLAUDE_CODE_SESSION_ID:-$(basename "$PWD")}"

t0="$(hooklog_now_ms)"
"$@"                       # inherit stdin/stdout/stderr — protocol untouched
code=$?
hooklog_step claude "$scope" "$event" "$label" "$(( $(hooklog_now_ms) - t0 ))" "$code"
exit "$code"
