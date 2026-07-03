#!/usr/bin/env bash
# Installer for the dotfiles claude launch wrapper + pre-session lifecycle hook.
# Idempotent: safe to re-run. Symlinks tracked files into ~/.claude and wires
# the wrapper into the shell so `claude`/`c` always skip permissions.
set -euo pipefail

# Repo root = two levels up from this script (claude/skills/install-claude-hooks/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"

WRAPPER="$REPO/claude/shell/claude-wrapper.zsh"
HOOK_SRC="$REPO/claude/hooks/pre-session.sh"
SKILL_SRC="$REPO/claude/skills/install-claude-hooks"

CLAUDE_HOOKS="$HOME/.claude/hooks"
CLAUDE_SKILLS="$HOME/.claude/skills"
RC="${1:-$HOME/.aliases}"   # shell file to source the wrapper from

mkdir -p "$CLAUDE_HOOKS" "$CLAUDE_SKILLS"

link() {  # link <src> <dest> — back up a real (non-symlink) dest first
  local src="$1" dest="$2"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$dest.bak.$(date +%s)"
    echo "  backed up existing $dest"
  fi
  ln -sfn "$src" "$dest"
  echo "  linked $dest -> $src"
}

echo "Installing claude wrapper + pre-session hook from $REPO"
link "$HOOK_SRC"   "$CLAUDE_HOOKS/pre-session.sh"
link "$SKILL_SRC"  "$CLAUDE_SKILLS/install-claude-hooks"

# Hook timing dispatcher: symlink it in, then idempotently route Calum's personal
# Claude hooks through it so each one is timed into the shared hooks log.
link "$REPO/claude/hooks/dispatch.sh" "$CLAUDE_HOOKS/dispatch.sh"
bash "$REPO/claude/hooks/wire-timing.sh" "$HOME/.claude/settings.json" || true

# Wire the wrapper into the shell (idempotent: match by stable path tail so the
# check holds whether the existing line uses $HOME or a resolved absolute path).
if [ -f "$RC" ] && grep -qF "claude/shell/claude-wrapper.zsh" "$RC"; then
  echo "  $RC already sources the wrapper"
else
  printf '\n# dotfiles: claude launch wrapper (claude/c skip permissions, pre-session hook)\nsource "%s"\n' "$WRAPPER" >> "$RC"
  echo "  appended source line to $RC"
fi

echo "Done. Run 'reload' (or open a new shell) to pick up the wrapper."
