#!/usr/bin/env bash
# Daily restic backup of this Mac to the Synology NAS over Tailscale, plus the
# weekly maintenance that keeps the repo healthy.
#
#   restic-backup backup     snapshot + apply retention   (daily, 12:00)
#   restic-backup maintain   prune + check                (weekly, Sun 12:30)
#   restic-backup verify     force the deep data check    (manual)
#   restic-backup status     print repo stats             (manual)
#   restic-backup progress   live progress of a running backup (manual)
#
# Why a wrapper and not a bare `restic` in the plist: unattended runs need
# preflight gates (is the NAS even reachable? are we about to flatten the
# battery?), and they need to *say something* when they skip — a backup system
# that silently does nothing is worse than no backup system, because you think
# you're covered.
#
# Config lives outside this repo (which is public) at ~/.config/restic/env.
# See the README for the install steps.

set -uo pipefail

MODE="${1:-backup}"

# ── Locate our sibling files ─────────────────────────────────────────────────
# This script is symlinked onto PATH as ~/.local/bin/restic-backup, so
# dirname $0 points at ~/.local/bin, not the repo. Walk the symlink chain to
# find the real directory holding restic-excludes.txt. (`readlink -f` exists on
# current macOS but not on every box this might get copied to.)
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _target=$(readlink "$SELF")
  case "$_target" in
    /*) SELF="$_target" ;;
    *)  SELF="$(dirname "$SELF")/$_target" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
EXCLUDE_FILE="$SCRIPT_DIR/restic-excludes.txt"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/restic"
ENV_FILE="$CONFIG_DIR/env"
PASSWORD_FILE="$CONFIG_DIR/hometb-password"

LOG_DIR="$HOME/.cache/restic-backup"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$MODE.log"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

# ── ntfy ─────────────────────────────────────────────────────────────────────
# The topic is PUBLIC — anyone who guesses the name can read every message.
# Nothing identifying goes in a notification body: no hostnames, no tailscale
# IPs, no repo paths, no filenames. Counts, sizes, durations, status. That's it.
notify() {
  local priority="$1" tags="$2" title="$3" body="$4"
  [ -n "${NTFY_TOPIC:-}" ] || return 0
  curl -fsS -m 15 \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: $tags" \
    -d "$body" \
    "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 \
    || log "WARN ntfy post failed (backup itself unaffected)"
}

# A skip is not a failure — exit 0 so launchd doesn't back off — but it must be
# visible, and it must say *why*. Silence is the enemy.
skip() {
  log "SKIP $1"
  notify low next_track_button "Backup skipped" "⏭️ $1"
  exit 0
}

fail() {
  log "FAIL $1"
  notify urgent rotating_light "Backup FAILED" "❌ $1"
  exit 1
}

# ── Config ───────────────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] || fail "config missing — run the install steps"
# shellcheck source=/dev/null
. "$ENV_FILE"   # RESTIC_REPOSITORY, NAS_SSH_HOST, NAS_SSH_PORT, NTFY_TOPIC

[ -f "$PASSWORD_FILE" ] || fail "password file missing"
[ -f "$EXCLUDE_FILE" ]  || fail "exclude file missing"

# restic only honours '#' as a comment when it is the first character of the
# line — there is no inline-comment support. A path line with a trailing
# "# 30G" annotation becomes a literal pattern containing spaces and a hash,
# matches nothing, and restic says nothing about it. That silently put ~94 GiB
# of caches into the first real snapshot. Refuse to run rather than produce
# another quietly-wrong backup.
if grep -qE '^[^#].*[^[:space:]][[:space:]]+#' "$EXCLUDE_FILE"; then
  log "exclude file has inline comments on these lines:"
  grep -nE '^[^#].*[^[:space:]][[:space:]]+#' "$EXCLUDE_FILE" | tee -a "$LOG_FILE"
  fail "exclude file has inline comments — those patterns match nothing"
fi

export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"

# The SSH key has a non-default name, so a bare sftp would never offer it.
# Passing it through restic's own sftp.args keeps the whole configuration in
# this repo instead of scattering a Host block into ~/.ssh/config.
#   IdentitiesOnly  don't let the agent offer other keys first and trip the
#                   server's MaxAuthTries before ours is tried
#   BatchMode       never prompt for a password — an unattended run must fail
#                   loudly, not hang forever waiting on stdin nobody will type
SFTP_OPT=(-o "sftp.args=-i ${NAS_SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes")
# restic's own cache. Kept out of ~/Library/Caches so an over-eager cleanup of
# that directory can't force a full re-index on the next run.
export RESTIC_CACHE_DIR="$HOME/.cache/restic"

# ── Preflight gates ──────────────────────────────────────────────────────────

# Only one run at a time. `prune` can take hours on a repo this size, and a
# `backup` starting on top of it would just block on the repo lock and then sit
# there holding a launchd slot. mkdir is the atomic primitive available
# everywhere; macOS has no flock(1).
LOCK_DIR="$LOG_DIR/.lock"
acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local owner age
    owner=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "?")
    # A lock whose process is gone is stale — a crash or a hard reboot mid-run.
    # Reclaim it rather than staying wedged forever.
    if [ "$owner" != "?" ] && ! kill -0 "$owner" 2>/dev/null; then
      log "WARN reclaiming stale lock from dead pid $owner"
      rm -rf "$LOCK_DIR"
      mkdir "$LOCK_DIR" 2>/dev/null || skip "could not acquire lock"
    else
      age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || date +%s) ))
      skip "another run still going (${age}s)"
    fi
  fi
  echo $$ > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
}

# Reachability: test the port we actually need, not the tailscale layer.
# `tailscale ping` can succeed while sshd is down or DSM has dropped SSH, and
# then restic hangs instead of skipping cleanly.
gate_nas() {
  nc -z -G 5 -w 5 "$NAS_SSH_HOST" "${NAS_SSH_PORT:-22}" 2>/dev/null \
    || skip "NAS unreachable"
}

# A 145 GiB initial backup will drain a laptop battery. Deltas are smaller but
# still not free. AC, or >40%.
gate_power() {
  local batt pct
  batt=$(pmset -g batt 2>/dev/null)
  case "$batt" in
    *"'AC Power'"*) return 0 ;;
  esac
  pct=$(printf '%s' "$batt" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
  [ -n "$pct" ] || return 0   # desktop, or pmset unavailable — don't block
  [ "$pct" -gt 40 ] || skip "on battery (${pct}%)"
}

# Sparse-file bomb detector.
#
# restic sizes its work from apparent size (st_size), not allocated blocks. A
# single sparse VM disk therefore poisons a whole run: OrbStack's data.img.raw
# is 8192G apparent / 22G allocated, and it made a run estimate 8.99 TB of work
# — 8 TB of it zeroes restic had to read in order to find out they were zeroes.
# `du` reports 22G and hides this completely, so a du-based survey will never
# find it.
#
# Both offenders are excluded by path now, but the next one will arrive with
# some future app. This turns "silently waste a whole night" into "fail loudly
# in 30 seconds". Threshold is well above any plausible real file here (largest
# genuine one is a 4.6G WhatsApp media tar).
gate_sparse_bomb() {
  local found
  found=$(find /Users/calum \
      \( -path '*/Library/Caches' -o -path '*/.worktrees' -o -path '*/.cache' \
         -o -path '*/Library/Developer' -o -path '*/Library/CloudStorage' \
         -o -path '*HUAQ24HBR6.dev.orbstack' -o -path '*/Claude/vm_bundles' \
         -o -path '*/OrbStack' -o -path '*/node_modules' \) -prune -o \
      -type f -size +100G -print 2>/dev/null | head -3)
  if [ -n "$found" ]; then
    # Deliberately not naming the paths in the notification — the ntfy topic is
    # public. The log has them.
    log "SPARSE BOMB DETECTED:"; printf '%s\n' "$found" | tee -a "$LOG_FILE"
    fail "found file(s) over 100G apparent size not covered by excludes — see log"
  fi
}

# ── Modes ────────────────────────────────────────────────────────────────────

# bytes → human, for notification bodies. awk rather than numfmt(1): numfmt is
# GNU coreutils, i.e. Homebrew-only on macOS, and a backup script should not
# fail to describe itself because a brew package went missing.
human() {
  awk -v b="$1" 'BEGIN{
    split("B KiB MiB GiB TiB", u, " "); i=1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i==1 ? "%d%s" : "%.1f%s"), b, u[i]
  }'
}

do_backup() {
  local started json summary rc
  started=$(date +%s)
  log "=== backup starting ==="

  json="$LOG_DIR/last-backup.json"

  # taskpolicy -b runs restic at background QoS: macOS throttles both its CPU
  # and its disk I/O, so a midday backup doesn't make the machine feel slow.
  # Better than nice(1), which only covers CPU.
  #
  # -x                       don't cross filesystem boundaries — keeps restic
  #                          out of /Volumes/* SMB mounts and the OrbStack NFS
  #                          mount. NOT sufficient on its own: macOS File
  #                          Provider mounts under ~/Library/CloudStorage share
  #                          the home directory's st_dev, so -x sees no boundary
  #                          and walks straight into them. The first run hit
  #                          this and tried to back the NAS up onto itself
  #                          (9 TB estimated instead of 128 GB). That path is
  #                          excluded explicitly in the exclude file.
  # --exclude-caches         honours CACHEDIR.TAG (Cargo and friends drop these)
  # --exclude-if-present     drop a .nobackup file anywhere to skip that dir
  # --skip-if-unchanged      no empty snapshot when the Mac sat idle
  # --read-concurrency 12    default is 2. ~/Library/Mobile Documents (iCloud
  #                          Drive) is served by File Provider, and every read
  #                          is an IPC round-trip to fileproviderd/bird — the
  #                          first run crawled its 57k files at ~2.2 files/s
  #                          while local APFS files fly. The cost is latency,
  #                          not bandwidth or CPU, so concurrency is the lever.
  #                          Only bites on a first run: later backups have a
  #                          parent snapshot and skip unchanged files on
  #                          metadata alone, without ever opening them.
  taskpolicy -b restic "${SFTP_OPT[@]}" backup /Users/calum \
    -x \
    --exclude-caches \
    --exclude-if-present .nobackup \
    --exclude-file="$EXCLUDE_FILE" \
    --skip-if-unchanged \
    --read-concurrency 12 \
    --tag auto \
    --json > "$json" 2>>"$LOG_FILE"
  rc=$?

  if [ $rc -ne 0 ]; then
    # rc=3 means "completed, but some files could not be read" — a real
    # snapshot exists. Worth flagging, not worth screaming about.
    if [ $rc -eq 3 ]; then
      log "WARN backup completed with unreadable files (rc=3)"
    else
      fail "backup exited $rc"
    fi
  fi

  summary=$(grep '"message_type":"summary"' "$json" | tail -1)
  local elapsed files_new files_chg added snap
  elapsed=$(( $(date +%s) - started ))
  if [ -n "$summary" ]; then
    files_new=$(jq -r '.files_new'            <<<"$summary")
    files_chg=$(jq -r '.files_changed'        <<<"$summary")
    added=$(jq -r '.data_added'               <<<"$summary")
    snap=$(jq -r '.snapshot_id[0:8]'          <<<"$summary")
  else
    # --skip-if-unchanged produced no snapshot: nothing changed.
    log "no changes — no snapshot created"
    notify low zzz "Backup: no changes" "😴 Nothing changed · ${elapsed}s"
    return 0
  fi

  log "backup ok: +$files_new new, ~$files_chg changed, $(human "$added") added, snap $snap, ${elapsed}s"

  # Retention. `forget` without --prune is metadata-only and takes seconds;
  # actually reclaiming the space is `maintain`'s job, weekly. Running --prune
  # here would mean hours of repacking every single night.
  restic "${SFTP_OPT[@]}" forget \
    --keep-last 3 \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 24 \
    --keep-yearly -1 \
    --keep-tag keep \
    >>"$LOG_FILE" 2>&1 \
    || log "WARN forget failed — retention not applied this run"

  notify low white_check_mark "Backup OK" \
    "✅ $(printf '%dm%02ds' $((elapsed/60)) $((elapsed%60))) · +$(human "$added") · $files_new new / $files_chg changed · snap $snap"
}

do_maintain() {
  local started elapsed rc
  started=$(date +%s)
  log "=== maintain starting ==="

  # prune is the expensive one — it repacks data over SFTP. Hours, potentially.
  taskpolicy -b restic "${SFTP_OPT[@]}" prune >>"$LOG_FILE" 2>&1
  rc=$?
  [ $rc -eq 0 ] || fail "prune exited $rc"

  # Structural check: every blob a snapshot references exists, index is sane.
  # Cheap, but it never opens a pack file — it cannot see bitrot.
  taskpolicy -b restic "${SFTP_OPT[@]}" check >>"$LOG_FILE" 2>&1
  rc=$?
  [ $rc -eq 0 ] || fail "check exited $rc"

  elapsed=$(( $(date +%s) - started ))
  log "maintain ok (${elapsed}s)"
  notify low broom "Maintenance OK" \
    "🧹 Prune + check clean · $(printf '%dm%02ds' $((elapsed/60)) $((elapsed%60)))"

  # First maintenance run of the month also verifies a twelfth of the actual
  # data. See do_verify for why it's n/12 and not a percentage.
  if [ "$(date +%-d)" -le 7 ]; then
    do_verify
  fi
}

do_verify() {
  local slice started elapsed rc
  # n/12 is a *deterministic* partition of the pack files by ID, so rotating
  # the month through it verifies every byte in the repo exactly once per year.
  # The `5%` form restic also accepts picks packs at random — some get checked
  # twice, others never, and there's no coverage guarantee. Determinism is the
  # whole point of a bitrot check.
  slice="$(date +%-m)/12"
  started=$(date +%s)
  log "=== verify (slice $slice) starting ==="

  taskpolicy -b restic "${SFTP_OPT[@]}" check --read-data-subset="$slice" >>"$LOG_FILE" 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - started ))

  if [ $rc -ne 0 ]; then
    fail "data verification failed on slice $slice — possible corruption"
  fi
  log "verify ok (slice $slice, ${elapsed}s)"
  notify low mag "Verify OK" \
    "🔍 Slice $slice verified · $(printf '%dm%02ds' $((elapsed/60)) $((elapsed%60)))"
}

# Live progress of a run happening right now. Reads the --json stream the
# backup is already writing, so it costs nothing and doesn't touch the repo
# (which would block on the repo lock).
do_progress() {
  local json="$LOG_DIR/last-backup.json"
  if ! pgrep -f 'restic -o sftp' >/dev/null 2>&1; then
    if pgrep -f 'restic-backup (backup|maintain)' >/dev/null 2>&1; then
      echo "preflight running (sparse-bomb scan takes ~80s) — no upload started yet"
      return 0
    fi
    echo "no backup running."
    grep -hE 'backup ok|FAIL|SKIP|no changes' "$LOG_DIR/backup.log" 2>/dev/null | tail -1
    return 0
  fi
  while pgrep -f 'restic -o sftp' >/dev/null 2>&1; do
    tail -1 "$json" 2>/dev/null | jq -r '
      select(.message_type=="status")
      | "\((.percent_done*100)|floor)%  "
      + "\(.files_done // 0)/\(.total_files // 0) files  "
      + "\(((.bytes_done // 0)/1000000000)|floor)/\(((.total_bytes // 0)/1000000000)|floor) GB  "
      + "\((.seconds_elapsed // 0)/60|floor)m elapsed"' 2>/dev/null \
      | tr -d '\n' | awk '{printf "\r\033[K%s", $0}'
    sleep 3
  done
  echo
  grep -hE 'backup ok|FAIL|SKIP|no changes' "$LOG_DIR/backup.log" 2>/dev/null | tail -1
}

do_status() {
  restic "${SFTP_OPT[@]}" snapshots --compact 2>&1 | tail -20
  echo
  restic "${SFTP_OPT[@]}" stats --mode raw-data 2>&1
  echo
  restic "${SFTP_OPT[@]}" stats --mode restore-size latest 2>&1
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "$MODE" in
  backup)
    acquire_lock; gate_nas; gate_power; gate_sparse_bomb; do_backup ;;
  maintain)
    acquire_lock; gate_nas; gate_power; do_maintain ;;
  verify)
    acquire_lock; gate_nas; gate_power; do_verify ;;
  progress)
    do_progress ;;
  status)
    gate_nas; do_status ;;
  *)
    echo "usage: restic-backup {backup|maintain|verify|status|progress}" >&2; exit 2 ;;
esac
