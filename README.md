# dotfiles

My dotfiles, configs, and other bits worth sharing across machines.

## Contents

### Hook timing (centralized)

Every git hook and every personal Claude Code hook is routed through a single
dispatcher that times each one and appends a JSONL line to one shared log:
`~/.local/state/hooks/timing.jsonl` (`{ts,source,scope,event,step,ms,exit}`).
See it live with `tail -f ~/.local/state/hooks/timing.jsonl | jq .`.

| Path | What it does |
|---|---|
| `lib/hooklog.sh` | Shared timing/logging primitive both dispatchers source. Millisecond clock (free via bash5 `$EPOCHREALTIME`, perl fallback) + `hooklog_step`. Swallows its own errors so it can never break a commit or a Claude turn. |
| `git/hooks/_dispatch` | Centralized git-hook dispatcher. Every hook name symlinks to it (installed via global `core.hooksPath`). Runs `handlers.d/<hook>/NN-*.sh` in order (drop a file to extend — never edit the dispatcher), times each + the repo's own delegated hook, then chains to it. Gating hooks (`pre-*`, `commit-msg`) fail-fast; `post-*` run everything. |
| `git/hooks/handlers.d/post-commit/` | Current post-commit handlers: `10-lolcommits.sh` (webcam commit selfie), `20-cmux-notify.sh` (cmux toast when committing inside cmux). |
| `git/reconcile-hooks.sh` | **Capture-and-delegate**, so the dispatcher fronts EVERY repo even when beads/lefthook/husky claim a repo-local `core.hooksPath`. Saves the tool's path into `hooks.delegate`, unsets the local override (our dispatcher then delegates back to the tool — nothing breaks). Idempotent + reversible: `--all` (sweep), `--restore [repo]`, `--status`. Opt a repo out with `git config hooks.optout true`. |
| `shell/git-hooks-shell.zsh` | Self-heal triggers sourced from `~/.aliases`: zsh `chpwd` + a `git` wrapper (reconciles before commit/push/merge) + a `bd` shim. Current-repo-only, fail-open. |
| `git/launchd/…plist.template` | Background launchd sweep (`com.calum.git-hooks-reconcile`, every 600s) that re-captures any stray override across all repos. `install.sh` fills in paths and loads it. |
| `git/install.sh` | Points global `core.hooksPath` at `git/hooks`, (re)creates the hook symlinks, wires the shell self-heal into `~/.aliases`, installs+loads the launchd sweep, runs an initial capture sweep, and bootstraps the auto-push LaunchAgent (see below). Idempotent. |
| `shell/claude-wrapper.zsh` | Launch wrapper sourced from `~/.aliases`. Makes `claude` and `c` identical — both always run with `--dangerously-skip-permissions`; `cc` is the escape hatch (no skip). Every launch first runs the pre-session lifecycle hook. `command claude` bypasses the functions to the real binary, so no recursion and cmux integration is preserved. |
| `claude/hooks/dispatch.sh` | Transparent Claude-hook timing wrapper: `dispatch.sh <Event> <label> <cmd...>` runs the real hook with stdin/stdout/exit inherited (Claude's hook protocol untouched), times it, logs one line. |
| `claude/hooks/wire-timing.sh` | Idempotent jq transform that routes Calum's **personal** `settings.json` hooks through `dispatch.sh`. Leaves externally-managed hooks (NotchBar, tagged `# notchbar-`) alone. Backs up + validates before replacing. |
| `claude/hooks/pre-session.sh` | Pre-session lifecycle hook. Runs once before every `claude`/`c`/`cc` launch (before the actual session starts), receives the launch args, best-effort (exit code doesn't block). Edit it to run anything you want before any session. |
| `skills/install-claude-hooks/` | Skill + `install.sh` to symlink the wrapper sourcing, pre-session hook, `dispatch.sh`, and this skill into `~/.claude`, and run `wire-timing.sh`. Idempotent. |

### cmux + OpenCode

cmux file-managed settings and OpenCode's cmux plugin list are tracked here, while
cmux's volatile session restore state stays local.

| Path | What it does |
|---|---|
| `cmux/settings.json` | Symlink target for `~/.config/cmux/settings.json`. Stores stable cmux settings such as keyboard shortcuts. Do not track `~/.config/cmux/cmux.json`, it contains volatile `terminal.resumeCommands` session IDs. |
| `opencode/opencode.json` | Symlink target for `~/.config/opencode/opencode.json`. Enables cmux's OpenCode restore and feed plugins with absolute file URLs to the cmux-managed plugin files. The plugin files themselves are installed/updated by `cmux hooks setup`, not tracked here. |

### `nvim/`

[LazyVim](https://lazyvim.org) config, tracked whole. `~/.config/nvim` is a symlink to
`nvim/`. Plugin data/state lives in `~/.local/share/nvim` + `~/.local/state/nvim` (machine-local,
not tracked). New machine: symlink `nvim/` → `~/.config/nvim`, launch `nvim`, LazyVim bootstraps
from the pinned `lazy-lock.json`.

| Path | What it does |
|---|---|
| `nvim/lazyvim.json` | Enabled LazyVim extras: `lang.typescript` (vtsls), `lang.json`, `lang.markdown`, `lang.typescript.biome` (Biome format/lint — matches tidepool's toolchain). |
| `nvim/lazy-lock.json` | Pinned plugin commit SHAs — reproducible setup across machines. |
| `nvim/lua/plugins/` | Personal plugin overrides (only what differs from LazyVim defaults). |

### Auto-push (continuous backup of this repo)

A LaunchAgent that every 5 minutes (and once at each login/reboot) auto-commits any
local changes in this repo and pushes to its upstream branch — so the dotfiles are
always backed up to GitHub without you remembering to push.

| Path | What it does |
|---|---|
| `auto-push/auto-push.sh` | Staged-commit-and-push the target repo (path passed as `$1`). Commits only when the tree is dirty; the unattended snapshot bypasses ALL git hooks (`core.hooksPath=/dev/null`) so it never fires the webcam selfie / timing dispatcher / commit-msg guards meant for human commits. Fail-soft: a transient push/auth failure logs and the next tick retries (not `set -e`). |
| `auto-push/launchd/…plist.template` | `com.calum.dotfiles-autopush` LaunchAgent: `StartInterval` 300s + `RunAtLoad`. `install.sh` fills `__SCRIPT__/__REPO__/__HOME__/__PATH__/__SSH_ENV__` (machine-specific). |
| `auto-push/install.sh` | Bakes this repo's path into the plist, resolves `git` onto launchd's PATH, injects the GUI `SSH_AUTH_SOCK` if present (ssh remote), and bootstraps the agent. Idempotent. Auto-run at the end of `git/install.sh`. Logs: `~/.local/state/autopush/{log,err}`. |

> Uninstall: `launchctl bootout gui/$(id -u)/com.calum.dotfiles-autopush && rm ~/Library/LaunchAgents/com.calum.dotfiles-autopush.plist`.

### `claude/`

[Claude Code](https://claude.com/claude-code) setup. Symlink these into `~/.claude/`.

| Path | What it does |
|---|---|
| `skills/install-claude-hooks/` | Skill + `install.sh` to symlink the launch wrapper, pre-session hook, `dispatch.sh`, and this skill into `~/.claude`, and run `wire-timing.sh`. |
| `skills/publish-setup/` | Skill for bootstrapping iOS app publishing (Fastlane match, ASC key, secrets sync). |
| `skills/saving-a-memory/` | Skill for where/how to save memories (global `~/.claude/CLAUDE.md` by default; never project-local from a worktree). |
| `skills/writing-goals/` | Skill for composing `/goal` conditions that are tight, transcript-verifiable, and dodge-proof. |
| `statusline-command.sh` | Tokyo Night statusline for Claude Code: left clock `[5:30pm]`, model + effort `(medium)`, cwd (OSC-8 link to the GitHub remote), git branch + dirty flag, `origin/main` short SHA with `(-N, age)` when local `main` is ahead/unpushed (N commits + age of origin/main's tip), and context-window %. Wire via `statusLine.command` in `settings.json`. |
| `themes/blackout.json` | Blackout theme for Claude Code (`{name, base, overrides}`). Symlink target for `~/.claude/themes/blackout.json`; select it as the theme in `settings.json`. |

### `themes/`

True-black **Blackout** theme (plus a **Lucent Orng++** OpenCode variant) for Cursor / VS Code, OpenCode, and Antinote. Previously the standalone `0x63616c/themes` repo, now vendored here.

| Path | What it does |
|---|---|
| `themes/cursor/` | Cursor & VS Code theme: `palette/palette.json` is the single source of color, `bun run build` regenerates, `scripts/install.sh` links into Cursor + VS Code. Symlink target for `~/.cursor/extensions/blackout-theme` and `~/.vscode/extensions/blackout-theme`. |
| `themes/opencode/` | OpenCode TUI themes: `blackout.json` + `lucent-orng-plusplus.json` (opaque variant of the built-in `lucent-orng`). Loaded via the global OpenCode plugin config (`"plugin": ["…/dotfiles/themes"]`). |
| `themes/antinote/` | Blackout theme for [Antinote](https://antinote.io). Antinote is sandboxed, so `sync.sh` **copies** (not links) `blackout.json` into its container. |

See `themes/README.md` for full per-app install + tweak instructions.

## Install

```bash
git clone https://github.com/0x63616c/dotfiles.git
cd dotfiles

# Centralized git-hook dispatcher: sets global core.hooksPath, times every hook,
# wires the self-heal (shell + launchd), and captures repos that claim core.hooksPath
./git/install.sh

# Claude launch wrapper + pre-session hook + hook-timing dispatcher
# (symlinks, wires ~/.aliases, routes personal settings.json hooks through dispatch.sh)
./claude/skills/install-claude-hooks/install.sh   # then run `reload`

# Claude skills (install-claude-hooks is wired by its own installer above)
ln -s "$PWD/claude/skills/publish-setup"                   ~/.claude/skills/publish-setup
ln -s "$PWD/claude/skills/saving-a-memory"                 ~/.claude/skills/saving-a-memory
ln -s "$PWD/claude/skills/writing-goals"                   ~/.claude/skills/writing-goals

# Statusline (then set statusLine.command to this path in ~/.claude/settings.json)
ln -s "$PWD/claude/statusline-command.sh"                  ~/.claude/statusline-command.sh

# Claude theme (then select "blackout" as the theme in ~/.claude/settings.json)
mkdir -p ~/.claude/themes
ln -s "$PWD/claude/themes/blackout.json"                   ~/.claude/themes/blackout.json

# Neovim (LazyVim) config
ln -s "$PWD/nvim"                                          ~/.config/nvim

# cmux + OpenCode config
mkdir -p ~/.config/cmux ~/.config/opencode
ln -s "$PWD/cmux/settings.json"                            ~/.config/cmux/settings.json
ln -s "$PWD/opencode/opencode.json"                        ~/.config/opencode/opencode.json

# Themes — Cursor/VS Code Blackout (links into both editors)
./themes/cursor/scripts/install.sh
```
