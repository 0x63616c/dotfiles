# Claude launch wrapper — tracked in dotfiles, sourced from ~/.aliases.
#
# Goal: `claude` and `c` are IDENTICAL. Both always run with
# --dangerously-skip-permissions, from anywhere an interactive zsh sources this.
# `cc` is the escape hatch that launches WITHOUT skip-permissions.
#
# Every launch (skip or not) first runs the pre-session lifecycle hook
# ~/.claude/hooks/pre-session.sh — your single place to run a command before
# the actual claude session starts.
#
# `command claude` deliberately bypasses these functions and resolves to the
# real binary on PATH (the cmux wrapper, which then finds ~/.local/bin/claude),
# so cmux session/hook injection is preserved and there is no recursion.

# Shared prelaunch: fire the lifecycle hook, then keep the native binary signed.
__claude_prelaunch() {
  local hook="$HOME/.claude/hooks/pre-session.sh"
  [ -x "$hook" ] && "$hook" "$@"
  local bin
  bin=$(readlink "$HOME/.local/bin/claude" 2>/dev/null)
  [ -n "$bin" ] && { codesign --verify --quiet "$bin" 2>/dev/null \
    || codesign --force -s - --preserve-metadata=entitlements "$bin" 2>/dev/null; }
  return 0
}

# Default claude: always skip permissions.
claude() {
  __claude_prelaunch "$@"
  command claude --dangerously-skip-permissions "$@"
}

# c == claude (kept as a deliberate alias of the wrapped binary).
c() { claude "$@"; }

# cc: escape hatch — run the lifecycle hook but WITHOUT --dangerously-skip-permissions.
cc() {
  __claude_prelaunch "$@"
  command claude "$@"
}
