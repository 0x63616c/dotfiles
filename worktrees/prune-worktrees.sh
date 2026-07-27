#!/usr/bin/env bash
# Prune wtp-managed worktrees under ~/.worktrees/<repo>/**/ that are safe to
# delete: git status clean, and branch fully merged into the repo's default
# remote branch (origin/main or origin/master). Never touches the main
# checkout. Dry-run by default; pass --apply to actually remove.
#
# Why this exists: Claude Code's EnterWorktree({path}) (the form wtp's
# workflow requires) never registers as "owner" of the worktree, so
# ExitWorktree refuses to clean it up. Worktrees pile up forever otherwise.

set -uo pipefail

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

WORKTREES_ROOT="$HOME/.worktrees"
[ -d "$WORKTREES_ROOT" ] || exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }

# Linked worktrees have a *file* named .git (not a dir) at their root, unlike
# the main checkout. Branch names with slashes (feat/foo) nest arbitrarily
# deep, so we can't assume a fixed depth.
find "$WORKTREES_ROOT" -type f -name .git 2>/dev/null | while read -r gitfile; do
  wt=$(dirname "$gitfile")
  label=${wt#"$WORKTREES_ROOT"/}

  main_toplevel=$(git -C "$wt" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
  [ -z "$main_toplevel" ] && continue

  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    log "SKIP $label — uncommitted changes"
    continue
  fi

  default_branch=$(git -C "$wt" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/##')
  [ -z "$default_branch" ] && default_branch="origin/main"
  git -C "$wt" fetch origin --quiet 2>/dev/null

  branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if ! git -C "$wt" merge-base --is-ancestor HEAD "$default_branch" 2>/dev/null; then
    log "SKIP $label — branch '$branch' not merged into $default_branch"
    continue
  fi

  if [ "$APPLY" = 1 ]; then
    log "REMOVE $label (branch '$branch', merged+clean)"
    git -C "$main_toplevel" worktree remove "$wt" --force
    git -C "$main_toplevel" branch -D "$branch" 2>/dev/null
  else
    log "WOULD REMOVE $label (branch '$branch', merged+clean) — rerun with --apply"
  fi
done
