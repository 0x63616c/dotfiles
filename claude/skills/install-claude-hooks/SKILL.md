---
name: install-claude-hooks
description: Use when Calum wants to install, reinstall, or update the dotfiles claude launch wrapper and pre-session lifecycle hook on a machine — symlinks the tracked wrapper/hook into ~/.claude and wires the shell so `claude` and `c` always run with --dangerously-skip-permissions.
---

# Install Claude Hooks

Installs the tracked claude launch wrapper + pre-session lifecycle hook from dotfiles.

After install, on any interactive zsh that sources `~/.aliases`:
- `claude` and `c` are **identical** — both always run with `--dangerously-skip-permissions`.
- `cc` is the escape hatch — same launch, but **without** skip-permissions.
- Every launch first runs `~/.claude/hooks/pre-session.sh` (the lifecycle hook), before the actual session starts.

## Install / reinstall

```bash
~/.claude/skills/install-claude-hooks/install.sh
```

Idempotent. It:
1. Symlinks `claude/hooks/pre-session.sh` → `~/.claude/hooks/pre-session.sh` (backs up a real file first).
2. Symlinks this skill → `~/.claude/skills/install-claude-hooks`.
3. Appends a `source .../claude/shell/claude-wrapper.zsh` line to `~/.aliases` if missing.
4. Symlinks `claude/hooks/dispatch.sh` → `~/.claude/hooks/dispatch.sh` and runs `wire-timing.sh` to route Calum's personal `settings.json` hooks through it (NotchBar's hooks are left alone). Each hook is then timed into `~/.local/state/hooks/timing.jsonl`.

> Git hooks are a separate installer: `./git/install.sh` (sets global `core.hooksPath`). Both log to the same file.

Pass a different shell file as `$1` to source from somewhere other than `~/.aliases`.

Then run `reload`.

## Customize the lifecycle hook

Edit `claude/hooks/pre-session.sh` in the dotfiles repo (it's the symlink target, so edits are tracked in git). Put any command you want to run before every session there. It receives the launch args (`"$@"`) and runs best-effort — its exit code does not block the session.

## Files (all in dotfiles)

| Path | Role |
|---|---|
| `claude/shell/claude-wrapper.zsh` | Defines `claude`/`c`/`cc`. `command claude` bypasses the functions to the real binary (cmux wrapper → `~/.local/bin/claude`), so no recursion and cmux integration is preserved. |
| `claude/hooks/pre-session.sh` | The pre-session lifecycle hook. Edit to taste. |
| `claude/skills/install-claude-hooks/install.sh` | This installer. |
