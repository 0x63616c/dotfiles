# Shared interactive shell behavior. Edit this file in dotfiles.
# Every integration is guarded, so a missing tool never breaks the shell.

# Reload the generated loader.
alias reload='source "$HOME/.zshrc"'

# Explicit shortcut: Claude sessions launched via c bypass permission prompts.
alias c='claude --dangerously-skip-permissions'
alias cr='c --resume'

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY INC_APPEND_HISTORY

# Completion
autoload -Uz compinit && compinit -u

# Sensible options
setopt AUTO_CD INTERACTIVE_COMMENTS

# Tool versions
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"

# Git worktrees: completion, and cd on `wtp cd` / `wtp add`
command -v wtp >/dev/null 2>&1 && eval "$(wtp shell-init zsh)"

# Prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
