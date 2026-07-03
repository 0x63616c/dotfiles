#!/usr/bin/env bash
# Installer for the dotfiles centralized git-hook dispatcher.
# Points the GLOBAL core.hooksPath at this repo's git/hooks dir and makes sure
# every hook name symlinks to _dispatch. Idempotent: safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/hooks"

# Every git hook name -> symlink to _dispatch (which recovers the fired hook from $0).
HOOK_NAMES=(
  applypatch-msg pre-applypatch post-applypatch
  pre-commit prepare-commit-msg commit-msg post-commit
  pre-merge-commit post-merge pre-rebase
  pre-push post-checkout post-rewrite
  pre-auto-gc push-to-checkout sendemail-validate
)
for h in "${HOOK_NAMES[@]}"; do
  ln -sfn _dispatch "$HOOKS_DIR/$h"
done

chmod +x "$HOOKS_DIR/_dispatch"
find "$HOOKS_DIR/handlers.d" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

# Back up any pre-existing global hooks dir that isn't already us.
PREV="$(git config --global --get core.hooksPath || true)"
if [ -n "$PREV" ] && [ "$PREV" != "$HOOKS_DIR" ] && [ -e "$PREV" ] && [ ! -L "$PREV" ]; then
  mv "$PREV" "$PREV.bak.$(date +%s)"
  echo "  backed up previous hooks dir: $PREV"
fi

git config --global core.hooksPath "$HOOKS_DIR"
echo "core.hooksPath -> $HOOKS_DIR"
echo "hooks log       -> ${HOOKS_LOG:-$HOME/.local/state/hooks/timing.jsonl}"

chmod +x "$SCRIPT_DIR/reconcile-hooks.sh"

# --- self-heal: keep our dispatcher in front of repos that claim core.hooksPath ---
# 1) Shell integration (chpwd + git wrapper + bd shim), sourced from ~/.aliases.
RC="${1:-$HOME/.aliases}"
SHELL_SRC="$(cd "$SCRIPT_DIR/.." && pwd)/shell/git-hooks-shell.zsh"
if [ -f "$RC" ] && grep -qF "shell/git-hooks-shell.zsh" "$RC"; then
  echo "  $RC already sources the git-hooks shell integration"
else
  printf '\n# dotfiles: keep global git-hook dispatcher in front of every repo (self-heal)\nsource "%s"\n' "$SHELL_SRC" >> "$RC"
  echo "  appended git-hooks shell source to $RC"
fi

# 2) Background launchd sweep (re-captures stray overrides every few minutes).
LA_DIR="$HOME/Library/LaunchAgents"
PLIST="$LA_DIR/com.calum.git-hooks-reconcile.plist"
mkdir -p "$LA_DIR" "$HOME/.local/state/hooks"
sed -e "s#__SCRIPT__#$SCRIPT_DIR/reconcile-hooks.sh#g" -e "s#__HOME__#$HOME#g" \
  "$SCRIPT_DIR/launchd/com.calum.git-hooks-reconcile.plist.template" > "$PLIST"
launchctl bootout "gui/$(id -u)/com.calum.git-hooks-reconcile" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
  && echo "  loaded launchd sweep (com.calum.git-hooks-reconcile, every 600s)" \
  || echo "  (could not bootstrap launchd; load manually: launchctl bootstrap gui/$(id -u) $PLIST)"

# 3) Initial sweep so currently-overridden repos are captured now.
echo "  initial sweep:"
bash "$SCRIPT_DIR/reconcile-hooks.sh" --all | sed 's/^/    /'

echo
echo "Done. Repos with their own core.hooksPath (beads/lefthook/husky) are now captured:"
echo "their hooks run via our dispatcher's delegation (hooks.delegate). Opt a repo out"
echo "with 'git config hooks.optout true'; undo a capture with 'reconcile-hooks.sh --restore'."

# --- bootstrap the auto-push LaunchAgent (commits + pushes this repo every 5 min) ---
AUTOPUSH_INSTALL="$(cd "$SCRIPT_DIR/.." && pwd)/auto-push/install.sh"
if [ -x "$AUTOPUSH_INSTALL" ]; then
  echo
  echo "Auto-push LaunchAgent:"
  bash "$AUTOPUSH_INSTALL" | sed 's/^/  /'
fi
