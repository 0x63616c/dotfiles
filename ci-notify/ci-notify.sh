#!/usr/bin/env bash
# Poll GitHub Actions for the watched repo and post a macOS notification when the
# newest *completed* run on the watched branch changes — so you see, at a glance,
# whether main shipped and which services built, or what broke.
#
# WHY POLL (not push): GitHub can't push to this Mac, and its notifications API
# returns nothing for CI on your *own* pushes (reason=ci_activity stays empty), so
# the durable signal is `gh run list`. One newest-completed run is all we report;
# superseded in-flight runs get cancelled and are deliberately ignored.
#
# Service mapping: the CI workflow's job names ARE the services — build-{web,api,
# storybook,bosun}. conclusion==success => that image built & shipped; skipped =>
# unchanged. A green `deploy` job means the bosun webhook was accepted (image
# pushed), NOT that the swarm service is healthy on homelab — hence "shipped".
#
# Auth: uses your gh keyring login (runs as you). No secret lives in the plist.
# Fail-open: any network/gh/jq error logs and exits 0 — this must never spam or die.
set -uo pipefail

REPO="${CI_NOTIFY_REPO:-0x63616c/control-center}"
BRANCH="${CI_NOTIFY_BRANCH:-main}"
STATE_DIR="${CI_NOTIFY_STATE:-$HOME/.local/state/ci-notify}"
SEEN="$STATE_DIR/seen"          # last run id we already notified about
GROUP="ci-notify:$REPO"         # terminal-notifier group => new note replaces old
SENDER="${CI_NOTIFY_SENDER:-com.calum.ci-notify}"  # the CI.app stub identity => own
                                # Notification Center stack, NOT grouped with commits
mkdir -p "$STATE_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }

# --- newest COMPLETED, non-cancelled run on the branch -----------------------
runs_json="$(gh run list -R "$REPO" -b "$BRANCH" --limit 8 \
  --json databaseId,status,conclusion,displayTitle,event,url 2>/dev/null)" || {
  log "gh run list failed (offline?) — skipping"; exit 0; }

run="$(printf '%s' "$runs_json" | jq -c '
  [ .[] | select(.status=="completed" and .conclusion!="cancelled") ] | .[0] // empty
' 2>/dev/null)" || { log "jq parse failed — skipping"; exit 0; }

[ -n "$run" ] || { log "no completed runs yet — skipping"; exit 0; }

id="$(printf '%s' "$run" | jq -r '.databaseId')"
prev="$(cat "$SEEN" 2>/dev/null || true)"

# First ever run: seed the cursor silently so we don't flood the backlog.
if [ -z "$prev" ]; then printf '%s' "$id" > "$SEEN"; log "seeded cursor at $id (no notify)"; exit 0; fi
[ "$id" != "$prev" ] || exit 0   # nothing new

# --- per-job detail: which services shipped / what broke ---------------------
concl="$(printf '%s' "$run"  | jq -r '.conclusion')"
title="$(printf '%s' "$run"  | jq -r '.displayTitle')"
url="$(printf '%s'   "$run"  | jq -r '.url')"

jobs_json="$(gh run view "$id" -R "$REPO" --json jobs 2>/dev/null)" || jobs_json='{"jobs":[]}'

# services that built+pushed (build-<svc> jobs that succeeded)
deployed="$(printf '%s' "$jobs_json" | jq -r '
  [ .jobs[] | select(.name|startswith("build-")) | select(.conclusion=="success")
    | (.name|sub("^build-";"")) ] | join(", ")' 2>/dev/null)"
# jobs that failed (the "what broke" list)
broke="$(printf '%s' "$jobs_json" | jq -r '
  [ .jobs[] | select(.conclusion=="failure" or .conclusion=="timed_out")
    | .name ] | join(", ")' 2>/dev/null)"
# did the deploy job go green? (bosun webhook accepted => deploy ✅)
deploy_ok="$(printf '%s' "$jobs_json" | jq -r '
  any(.jobs[]; .name=="deploy" and .conclusion=="success")' 2>/dev/null)"

case "$concl" in
  success)
    emoji="✅"
    if [ -n "$deployed" ]; then headline="shipped — $deployed"; else headline="CI passed (no image changes)"; fi
    [ "$deploy_ok" = "true" ] && headline="$headline ✅ deploy"
    ;;
  failure|timed_out|startup_failure)
    emoji="❌"
    if [ -n "$broke" ]; then headline="CI failed — $broke"; else headline="CI failed"; fi
    ;;
  *) emoji="⚠️"; headline="CI $concl" ;;
esac

repo_short="${REPO##*/}"
TN="$(command -v terminal-notifier || true)"
if [ -n "$TN" ]; then
  "$TN" -title "[CI] $emoji $repo_short" -subtitle "$headline" -message "$title" \
        -open "$url" -group "$GROUP" -sender "$SENDER" >/dev/null 2>&1 || log "terminal-notifier failed"
else
  log "terminal-notifier not on PATH"
fi

printf '%s' "$id" > "$SEEN"
log "notified: [$concl] $repo_short — $headline (run $id)"
