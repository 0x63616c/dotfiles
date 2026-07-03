#!/usr/bin/env bash
# Idempotently route Calum's PERSONAL Claude hooks through dispatch.sh so each one
# is timed into the shared hooks log. Leaves externally-managed hooks untouched —
# specifically anything tagged with a `# notchbar-...` comment, which NotchBar's
# own installer greps for and would re-add/duplicate if we rewrote it.
#
# Targets: any hook whose command references ~/.claude/hooks/<name>.sh (personal
# hooks live there), excluding notchbar and anything already wrapped. The rewrite is
#   <dispatch> <EventName> <name> <original command...>
# dispatch.sh runs the original transparently (stdin/stdout/exit preserved).
#
# Safe: backs up settings.json, validates the transform as JSON, and only then
# replaces the file. Idempotent: re-running is a no-op once wired.
set -euo pipefail

SETTINGS="${1:-$HOME/.claude/settings.json}"
DISPATCH="${DISPATCH:-$HOME/.claude/hooks/dispatch.sh}"

[ -f "$SETTINGS" ] || { echo "  no settings file at $SETTINGS, skipping"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "  jq required for hook wiring; skipping"; exit 0; }

tmp="$(mktemp)"
jq --arg dispatch "$DISPATCH" '
  if .hooks then
    .hooks |= with_entries(
      .key as $event |
      .value |= map(
        if .hooks then
          .hooks |= map(
            if (.command | type == "string")
               and (.command | test("/\\.claude/hooks/"))
               and (.command | test("notchbar") | not)
               and (.command | test("dispatch\\.sh") | not)
            then
              (.command | capture("/\\.claude/hooks/(?<n>[^ /]+)\\.sh").n) as $label
              | .command = ($dispatch + " " + $event + " " + $label + " " + .command)
            else . end
          )
        else . end
      )
    )
  else . end
' "$SETTINGS" > "$tmp"

jq -e . "$tmp" >/dev/null 2>&1 || { echo "  transform produced invalid JSON; aborting (settings unchanged)"; rm -f "$tmp"; exit 1; }

if diff -q "$SETTINGS" "$tmp" >/dev/null 2>&1; then
  echo "  settings.json hooks already wired (no change)"
  rm -f "$tmp"
else
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  mv "$tmp" "$SETTINGS"
  echo "  wired personal hooks through dispatch.sh (backup saved next to settings.json)"
fi
