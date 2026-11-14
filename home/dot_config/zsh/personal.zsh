# Personal Mac aliases and integrations.
# Homebrew prefix (empty if brew is missing)
if command -v brew >/dev/null 2>&1; then
  _brew_prefix="$(brew --prefix)"
  [ -f "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && \
    source "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  # syntax-highlighting must be sourced last among plugins
  [ -f "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && \
    source "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  unset _brew_prefix
fi

# Editor
alias code='cursor'

# vov's tool from the ~/coding/vov checkout: `vov` rebuilds when needed, else runs the cached binary.
[[ ! -d "$HOME/coding/vov/bin" ]] || path+=("$HOME/coding/vov/bin")

# Claude in ~/coding/vov (and its worktrees) gets vov's MCP keys from sops, for that process only (see vov/.mcp.json).
claude() {
  if [[ $PWD == $HOME/coding/vov(|-worktrees)(|/*) ]]; then
    PENPOT_MCP_KEY="$("$HOME/coding/vov/bin/vov" admin secrets get access PENPOT_MCP_KEY 2>/dev/null)" command claude "$@"
  else
    command claude "$@"
  fi
}
