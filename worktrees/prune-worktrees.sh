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

# Merged-PR branch names, fetched once per repo and cached here. Doing this
# per-worktree meant ~40 `gh` calls in 90s, which trips GitHub's secondary
# rate limit; the failed calls then read as "not merged" and the worktree was
# skipped even though its PR had landed. One call per repo instead.
PR_CACHE_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$PR_CACHE_DIR"' EXIT

# Without gh, squash-merged branches are indistinguishable from unmerged ones
# and nothing gets pruned. Say so instead of failing quietly — launchd's
# minimal PATH excludes Homebrew, which hid this for a full day of runs.
command -v gh >/dev/null 2>&1 || \
  log "WARN gh not on PATH — squash-merged branches will be skipped"

# Echoes the merged-PR number for $2 (branch) in repo rooted at $1, or nothing.
merged_pr_for() {
  local main_toplevel=$1 branch=$2
  local cache="$PR_CACHE_DIR/$(echo "$main_toplevel" | tr '/' '_')"
  if [ ! -f "$cache" ]; then
    (cd "$main_toplevel" && gh pr list --state merged --limit 500 \
      --json number,headRefName -q '.[] | "\(.headRefName)\t\(.number)"' \
      2>/dev/null) > "$cache" || true
  fi
  awk -F'\t' -v b="$branch" '$1 == b {print $2; exit}' "$cache"
}

# Linked worktrees have a *file* named .git (not a dir) at their root, unlike
# the main checkout. Branch names with slashes (feat/foo) nest arbitrarily
# deep, so we can't assume a fixed depth.
#
# Process substitution (not a pipe) so the loop body runs in *this* shell —
# a piped `while` gets a subshell, and the PR cache built inside it would be
# discarded between iterations.
while read -r gitfile; do
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

  # Three escalating "is this merged?" tests. Only the first works on a plain
  # merge commit; the repo squash-merges PRs, which rewrites history so the
  # branch's commits never become ancestors of main. Without the fallbacks
  # every worktree is skipped forever (34G of them, observed 2026-07-28).
  merged_by=""
  if git -C "$wt" merge-base --is-ancestor HEAD "$default_branch" 2>/dev/null; then
    merged_by="ancestor of $default_branch"
  elif [ -z "$(git -C "$wt" cherry "$default_branch" HEAD 2>/dev/null | grep '^+')" ] \
       && [ -n "$(git -C "$wt" cherry "$default_branch" HEAD 2>/dev/null)" ]; then
    # Every commit has an equivalent patch-id upstream. The second test guards
    # against an empty branch (no commits) reading as "fully merged".
    merged_by="all patches present in $default_branch"
  else
    # Squash-merged multi-commit branch: patch-ids won't match, but GitHub
    # knows the PR landed.
    pr=$(merged_pr_for "$main_toplevel" "$branch")
    [ -n "$pr" ] && merged_by="merged PR #$pr"
  fi

  if [ -z "$merged_by" ]; then
    log "SKIP $label — branch '$branch' not merged into $default_branch (no equivalent patches, no merged PR)"
    continue
  fi

  if [ "$APPLY" = 1 ]; then
    log "REMOVE $label (branch '$branch', clean, $merged_by)"
    git -C "$main_toplevel" worktree remove "$wt" --force
    git -C "$main_toplevel" branch -D "$branch" 2>/dev/null
  else
    log "WOULD REMOVE $label (branch '$branch', clean, $merged_by) — rerun with --apply"
  fi
done < <(find "$WORKTREES_ROOT" -type f -name .git 2>/dev/null)
