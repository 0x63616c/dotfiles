#!/usr/bin/env bash
# Shared hook timing/logging primitive for dotfiles dispatchers (git + claude).
#
# Source this file, then call `hooklog_step`. It appends ONE JSONL line per step
# to $HOOKS_LOG (default ~/.local/state/hooks/timing.jsonl) so you can see exactly
# how long every hook costs you, across both git and Claude, in one place.
#
# Line shape (parse with jq):
#   {"ts":"<iso8601>","source":"git|claude","scope":"<repo-or-session>","event":"<hook/event>","step":"<step>","ms":<int>,"exit":<int>}
#
# Design rule: this must NEVER break its caller. Every function swallows its own
# errors and degrades to a no-op rather than failing a commit or a Claude turn.

HOOKS_LOG="${HOOKS_LOG:-$HOME/.local/state/hooks/timing.jsonl}"

# Millisecond clock. Prefer bash5 $EPOCHREALTIME (free, no subprocess); fall back
# to perl (macOS /bin/date has no %N and stock /bin/bash is 3.2 with no $EPOCHREALTIME).
if [ -n "${EPOCHREALTIME:-}" ]; then
  hooklog_now_ms() { local s="${EPOCHREALTIME/./}"; printf '%s' "${s%???}"; }
else
  hooklog_now_ms() { perl -MTime::HiRes=time -le 'print int(time()*1000)' 2>/dev/null || echo 0; }
fi

_hooklog_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Minimal JSON string escaping (backslash, quote, tab, CR, LF).
_hooklog_esc() {
  printf '%s' "${1-}" | perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g; s/\n/\\n/g' 2>/dev/null
}

# hooklog_step <source> <scope> <event> <step> <ms> <exit>
hooklog_step() {
  mkdir -p "$(dirname "$HOOKS_LOG")" 2>/dev/null || true
  printf '{"ts":"%s","source":"%s","scope":"%s","event":"%s","step":"%s","ms":%s,"exit":%s}\n' \
    "$(_hooklog_iso)" "$(_hooklog_esc "${1-}")" "$(_hooklog_esc "${2-}")" "$(_hooklog_esc "${3-}")" \
    "$(_hooklog_esc "${4-}")" "${5:-0}" "${6:-0}" >> "$HOOKS_LOG" 2>/dev/null || true
}
