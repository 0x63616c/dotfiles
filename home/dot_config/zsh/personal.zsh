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
