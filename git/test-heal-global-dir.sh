#!/usr/bin/env bash
# Hermetic regression test for reconcile-hooks.sh content-integrity heal (D2 bug).
#
# WHY: reconcile_repo guards the POINTER (which dir owns core.hooksPath). A tool's
# `install` that resolves to our GLOBAL core.hooksPath instead overwrites the
# _dispatch symlinks with its own scripts — the pointer still reads "global = us",
# so the old reconcile saw nothing wrong while the dispatcher was dead machine-wide.
# heal_global_dir must detect a clobbered managed hook and restore the symlink. And
# reconcile_repo must still capture a repo whose local core.hooksPath points at us.
#
# Pure bash; OURS is injected via DOTFILES_HOOKS_DIR so the real global dir is never
# touched. Exits 0 on pass.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="$HERE/reconcile-hooks.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Fake global dispatcher dir: a _dispatch + symlinks, like install.sh produces.
gd="$tmp/hooks"; mkdir -p "$gd"
printf '#!/bin/sh\nexit 0\n' >"$gd/_dispatch"; chmod +x "$gd/_dispatch"
for h in pre-commit commit-msg pre-push post-merge; do ln -sfn _dispatch "$gd/$h"; done

# CLOBBER: a tool overwrites pre-push with its own script and backs ours up to .old
# (exactly what `lefthook install` does).
mv "$gd/pre-push" "$gd/pre-push.old"
printf '#!/bin/sh\necho i-am-lefthook\n' >"$gd/pre-push"; chmod +x "$gd/pre-push"

[ -L "$gd/pre-push" ] && fail "precondition: pre-push should be a clobbered regular file"

# HEAL.
DOTFILES_HOOKS_DIR="$gd" bash "$RECONCILE" --heal >/dev/null 2>&1

[ -L "$gd/pre-push" ] || fail "heal did not restore pre-push to a symlink"
[ "$(readlink "$gd/pre-push")" = "_dispatch" ] || fail "pre-push symlink does not point at _dispatch"
[ -e "$gd/pre-push.old" ] && fail "stale .old backup not cleaned"
[ -e "$gd/pre-push.clobbered" ] || fail "clobbering content not preserved for forensics"
# Untouched hooks stay symlinks.
[ -L "$gd/commit-msg" ] || fail "heal disturbed an intact hook"

# Second half: reconcile_repo must capture a repo whose local core.hooksPath points
# at its OWN tool dir (the pointer-hijack that lefthook/husky/bd do), moving it to
# hooks.delegate so our global dispatcher runs in front and delegates back.
repo="$tmp/repo"; git init -q "$repo"
toolhooks="$tmp/repo-lefthook"; mkdir -p "$toolhooks"
git -C "$repo" config core.hooksPath "$toolhooks"
DOTFILES_HOOKS_DIR="$gd" bash "$RECONCILE" --repo "$repo" quiet >/dev/null 2>&1
[ -z "$(git -C "$repo" config --local --get core.hooksPath || true)" ] \
  || fail "local core.hooksPath was not unset (capture failed)"
[ "$(git -C "$repo" config --local --get hooks.delegate || true)" = "$toolhooks" ] \
  || fail "hooks.delegate was not captured"

echo "PASS: heal restores clobbered dispatcher symlink; reconcile captures pointer hijack"
