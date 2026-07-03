#!/usr/bin/env bash
# Auto-commit any local changes in the target repo and push to its upstream branch.
# Runs every 5 min via the com.calum.dotfiles-autopush LaunchAgent and survives reboot
# (LaunchAgents in ~/Library/LaunchAgents auto-load at login; RunAtLoad fires one push
# immediately on load). The repo path is passed as $1 (baked in by install.sh).
#
# Machine snapshots bypass ALL git hooks (core.hooksPath=/dev/null): an unattended
# every-5-min commit must not trigger the webcam selfie, the timing dispatcher, or the
# commit-msg/fake-data guards meant for human commits. Your real commits are unaffected.
#
# NOTE: deliberately NOT `set -e` — a transient network/auth failure must log and let the
# next tick retry, never abort the agent.
set -uo pipefail

log() { echo "$(date '+%F %T') $*"; }

REPO="${1:-${AUTOPUSH_REPO:-}}"
[ -n "$REPO" ] || { log "no repo specified (pass path as \$1 or set AUTOPUSH_REPO)"; exit 0; }
cd "$REPO" 2>/dev/null || { log "cannot cd into $REPO"; exit 0; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { log "not a git work tree: $REPO"; exit 0; }

branch="$(git symbolic-ref --quiet --short HEAD || true)"
[ -n "$branch" ] || { log "detached HEAD in $REPO, skipping"; exit 0; }

# Stage + commit only if the tree is actually dirty, then push.
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  committed=false
  if git -c core.hooksPath=/dev/null commit --no-verify -m "chore(autopush): snapshot $(date '+%F %T %Z')" >/dev/null 2>&1; then
    log "committed snapshot on $branch"
    committed=true
  else
    log "nothing to commit on $branch (or commit failed)"
  fi

  if [ "$committed" = true ]; then
    if out="$(git push origin "$branch" 2>&1)"; then
      log "push ok ($branch): ${out:-up-to-date}"
    else
      log "push FAILED ($branch) — will retry next tick: $out"
    fi
  fi
else
  log "tree clean on $branch, skipping"
fi
