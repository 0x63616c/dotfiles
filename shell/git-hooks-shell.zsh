# dotfiles: keep our global git-hook dispatcher in front of EVERY repo.
#
# Tools (beads/lefthook/husky) and manual edits can set a repo-local core.hooksPath
# that shadows our global dispatcher. reconcile-hooks.sh "captures" that (saves it to
# hooks.delegate, unsets the override) so our dispatcher runs and then delegates back
# to the tool — nothing breaks. This file triggers that reconcile at the cheap,
# high-value moments. All hot-path calls touch ONLY the current repo and are
# fail-open: they can never block a shell or a git command.
#
# Other self-heal layers: a background launchd sweep (all repos, every few minutes)
# and the pre-session hook. See git/reconcile-hooks.sh for the full rationale.

_DOTFILES_RECONCILE="${_DOTFILES_RECONCILE:-$HOME/code/github.com/0x63616c/dotfiles/git/reconcile-hooks.sh}"

# Reconcile just the current repo, quietly. Never errors out.
_dotfiles_reconcile_cwd() {
  [ -x "$_DOTFILES_RECONCILE" ] || return 0
  command git rev-parse --git-dir >/dev/null 2>&1 || return 0
  "$_DOTFILES_RECONCILE" current quiet >/dev/null 2>&1 || true
}

# chpwd: reconcile whenever you cd into a repo.
autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _dotfiles_reconcile_cwd

# git wrapper: reconcile right before the subcommands that actually fire hooks, so a
# re-override is healed in the same breath as the operation. `command git` bypasses
# this function (no recursion); the function only exists in interactive shells, so
# hooks calling `git` are unaffected.
git() {
  case "${1:-}" in
    # Guard the call: if only this wrapper survived into a shell snapshot without the
    # helper (e.g. Claude Code's tool shell), a bare call would print "command not
    # found" on every git invocation. typeset -f makes a missing helper a silent no-op.
    commit|push|merge|rebase|cherry-pick|revert|am)
      typeset -f _dotfiles_reconcile_cwd >/dev/null 2>&1 && _dotfiles_reconcile_cwd ;;
  esac
  command git "$@"
}

# beads shim: `bd` can re-claim core.hooksPath (init / hook reinstall). Reconcile
# right after it runs so the next commit is already ours again.
if command -v bd >/dev/null 2>&1; then
  bd() {
    command bd "$@"; local rc=$?
    typeset -f _dotfiles_reconcile_cwd >/dev/null 2>&1 && _dotfiles_reconcile_cwd
    return $rc
  }
fi

# lefthook shim (PREVENTION): `lefthook install` writes to whatever core.hooksPath
# resolves to. When our reconcile has unset a repo's local core.hooksPath, that
# resolves to our GLOBAL dispatcher dir, so `lefthook install` overwrites the
# _dispatch symlinks machine-wide (the exact outage this whole system exists to
# prevent). Force install into the repo's OWN hooks dir by pinning a local
# core.hooksPath for the duration of the install, then reconcile captures that
# pointer back into hooks.delegate. Non-`install` subcommands pass straight through.
# `command lefthook` inside hooks bypasses this (no recursion); the function only
# exists in interactive shells. Heal-on-cd/git is the backstop for installs that
# bypass this shim (e.g. bun postinstall invoking node_modules/.bin/lefthook directly).
lefthook() {
  if [ "${1:-}" = install ]; then
    command git rev-parse --git-dir >/dev/null 2>&1 || { command lefthook "$@"; return $?; }
    local hooksdir; hooksdir="$(command git rev-parse --absolute-git-dir 2>/dev/null)/hooks"
    command git config --local core.hooksPath "$hooksdir" 2>/dev/null
    command lefthook "$@"; local rc=$?
    typeset -f _dotfiles_reconcile_cwd >/dev/null 2>&1 && _dotfiles_reconcile_cwd
    return $rc
  fi
  command lefthook "$@"
}
