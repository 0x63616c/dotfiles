#!/usr/bin/env bash
# Hermetic regression test for the _dispatch bare/worktree-less guard.
#
# WHY: tools like dolt (`bd dolt push`) drive git inside a bare object-store repo.
# Git still fires hooks there, but our delegated tool (lefthook) hard-crashes —
# its first move `git rev-parse --show-toplevel` errors "must be run in a work
# tree" (exit 128), which aborts the host tool's git op. That broke `bd dolt push`.
# The dispatcher must short-circuit (exit 0) and NEVER reach the delegate in a repo
# with no work tree.
#
# Pure bash; no network; touches only a mktemp dir. Exits 0 on pass, non-zero on fail.
set -u
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git init --bare -q "$tmp/bare.git"

# Delegate that mimics lefthook: leaves a sentinel if reached, then runs the exact
# probe that crashes lefthook in a bare repo.
deleg="$tmp/deleg"; mkdir -p "$deleg"
cat >"$deleg/pre-push" <<EOF
#!/bin/sh
echo REACHED >>"$tmp/sentinel"
git rev-parse --show-toplevel
EOF
chmod +x "$deleg/pre-push"
git -C "$tmp/bare.git" config hooks.delegate "$deleg"

# Fire pre-push through the dispatcher, in the bare-repo context.
out="$(cd "$tmp/bare.git" && GIT_DIR="$tmp/bare.git" "$HOOKS_DIR/pre-push" origin "$tmp/bare.git" </dev/null 2>&1)"
code=$?

[ "$code" -eq 0 ] || fail "dispatcher exited $code in bare repo (want 0). output: $out"
printf '%s' "$out" | grep -qi 'must be run in a work tree' \
  && fail "lefthook-style work-tree crash leaked through: $out"
[ -e "$tmp/sentinel" ] && fail "delegate ran in a bare repo (guard did not short-circuit)"

# Sanity: in a NORMAL work tree the dispatcher must still reach the delegate.
work="$tmp/work"; git init -q "$work"
git -C "$work" config hooks.delegate "$deleg"
rm -f "$tmp/sentinel"
( cd "$work" && "$HOOKS_DIR/pre-push" origin "$work" </dev/null >/dev/null 2>&1 )
[ -e "$tmp/sentinel" ] || fail "delegate did NOT run in a normal work tree (guard too aggressive)"

echo "PASS: bare-repo guard exits 0 and skips delegate; normal work tree still delegates"
