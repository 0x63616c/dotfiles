# dotfiles

My dotfiles, configs, and other bits worth sharing across machines.

## Contents

### cmux + OpenCode

cmux file-managed settings and OpenCode's cmux plugin list are tracked here, while
cmux's volatile session restore state stays local.

| Path | What it does |
|---|---|
| `cmux/settings.json` | Symlink target for `~/.config/cmux/settings.json`. Stores stable cmux settings such as keyboard shortcuts. Do not track `~/.config/cmux/cmux.json`, it contains volatile `terminal.resumeCommands` session IDs. |
| `cmux/organize-workspace` | CLI (symlinked onto PATH) that groups the current cmux window's workspaces by their enclosing git repo — one collapsible group per repo, named after the lowercase repo basename, each with a stable unique colour + SF Symbol icon. Nested sub-folders resolve to their repo; workspaces not in any git repo land in an `other…` group pinned last. Reuses/renames existing groups so it's idempotent. `--dry-run` prints the plan; `--window <ref>` targets another window. |
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
| `auto-push/auto-push.sh` | Staged-commit-and-push the target repo (path passed as `$1`). Commits only when the tree is dirty; the unattended snapshot bypasses ALL git hooks (`core.hooksPath=/dev/null`). Fail-soft: a transient push/auth failure logs and the next tick retries (not `set -e`). |
| `auto-push/launchd/…plist.template` | `com.calum.dotfiles-autopush` LaunchAgent: `StartInterval` 300s + `RunAtLoad`. `install.sh` fills `__SCRIPT__/__REPO__/__HOME__/__PATH__/__SSH_ENV__` (machine-specific). |
| `auto-push/install.sh` | Bakes this repo's path into the plist, resolves `git` onto launchd's PATH, injects the GUI `SSH_AUTH_SOCK` if present (ssh remote), and bootstraps the agent. Idempotent — run it directly to (re)install. Logs: `~/.local/state/autopush/{log,err}`. |

> Uninstall: `launchctl bootout gui/$(id -u)/com.calum.dotfiles-autopush && rm ~/Library/LaunchAgents/com.calum.dotfiles-autopush.plist`.

### `claude/`

[Claude Code](https://claude.com/claude-code) setup. Symlink these into `~/.claude/`.

| Path | What it does |
|---|---|
| `skills/codebase-audit/` | Skill for whole-repo health audits (naming drift, DRY, stale docs, dead code, scale readiness) with a fixed scoreboard report format; repo-scoped counterpart to per-diff code review. |
| `skills/publish-setup/` | Skill for bootstrapping iOS app publishing (Fastlane match, ASC key, secrets sync). |
| `skills/saving-a-memory/` | Skill for where/how to save memories (global `~/.claude/CLAUDE.md` by default; never project-local from a worktree). |
| `skills/writing-goals/` | Skill for composing `/goal` conditions that are tight, transcript-verifiable, and dodge-proof. |
| `skills/using-presenterm/` | Skill for authoring [presenterm](https://github.com/mfontanini/presenterm) terminal slideshows, including the house style (blackout theme, front-matter title slide, implicit slide ends). |
| `statusline-command.sh` | Tokyo Night statusline for Claude Code: left clock `[5:30pm]`, model + effort `(medium)`, cwd (OSC-8 link to the GitHub remote), git branch + dirty flag, `origin/main` short SHA with `(-N, age)` when local `main` is ahead/unpushed (N commits + age of origin/main's tip), and context-window %. Wire via `statusLine.command` in `settings.json`. |
| `themes/blackout.json` | Blackout theme for Claude Code (`{name, base, overrides}`) — full Blackout-palette match: true-black surfaces, off-white text, Vercel-blue hero accent, amber/purple/cyan/pink semantic accents. Keys verified against claude-code 2.1.206. Symlink target for `~/.claude/themes/blackout.json`; select it as the theme in `settings.json`. |

### `codex/`

[Codex](https://developers.openai.com/codex) terminal UI setup.

| Path | What it does |
|---|---|
| `themes/blackout.tmTheme` | Blackout syntax-highlighting theme for Codex CLI/TUI. Symlink target for `~/.codex/themes/blackout.tmTheme`; set `[tui].theme = "blackout"` in `~/.codex/config.toml`. |

### `themes/`

True-black **Blackout** theme (plus a **Lucent Orng++** OpenCode variant) for Cursor / VS Code, OpenCode, Codex, Claude, Neovim, presenterm, and Antinote. Previously the standalone `0x63616c/themes` repo, now vendored here.

| Path | What it does |
|---|---|
| `themes/cursor/` | Cursor & VS Code theme: `palette/palette.json` is the single source of color, `bun run build` regenerates, `scripts/install.sh` links into Cursor + VS Code. Symlink target for `~/.cursor/extensions/blackout-theme` and `~/.vscode/extensions/blackout-theme`. |
| `themes/opencode/` | OpenCode TUI themes: `blackout.json` + `lucent-orng-plusplus.json` (opaque variant of the built-in `lucent-orng`). Loaded via the global OpenCode plugin config (`"plugin": ["…/dotfiles/themes"]`). |
| `themes/antinote/` | Blackout theme for [Antinote](https://antinote.io). Antinote is sandboxed, so `sync.sh` **copies** (not links) `blackout.json` into its container. |

### `presenterm/`

| Path | What it does |
|---|---|
| `presenterm/themes/blackout.yaml` | Blackout theme for [presenterm](https://github.com/mfontanini/presenterm). Symlink target for `~/Library/Application Support/presenterm/themes/blackout.yaml` (presenterm's macOS config dir when `XDG_CONFIG_HOME` is unset; on Linux it's `~/.config/presenterm/themes/`). presenterm auto-loads any `.yaml` there as a theme named after the file, so decks reference it with `theme: {name: blackout}`. |

See `themes/README.md` for full per-app install + tweak instructions.

## Install

```bash
git clone https://github.com/0x63616c/dotfiles.git
cd dotfiles

# Claude skills
ln -s "$PWD/claude/skills/codebase-audit"                  ~/.claude/skills/codebase-audit
ln -s "$PWD/claude/skills/publish-setup"                   ~/.claude/skills/publish-setup
ln -s "$PWD/claude/skills/saving-a-memory"                 ~/.claude/skills/saving-a-memory
ln -s "$PWD/claude/skills/writing-goals"                   ~/.claude/skills/writing-goals
ln -s "$PWD/claude/skills/using-presenterm"                ~/.claude/skills/using-presenterm

# Statusline (then set statusLine.command to this path in ~/.claude/settings.json)
ln -s "$PWD/claude/statusline-command.sh"                  ~/.claude/statusline-command.sh

# Claude theme (then select "blackout" as the theme in ~/.claude/settings.json)
mkdir -p ~/.claude/themes
ln -s "$PWD/claude/themes/blackout.json"                   ~/.claude/themes/blackout.json

# Codex theme (then set [tui].theme = "blackout" in ~/.codex/config.toml)
mkdir -p ~/.codex/themes
ln -s "$PWD/codex/themes/blackout.tmTheme"                  ~/.codex/themes/blackout.tmTheme

# Neovim (LazyVim) config
ln -s "$PWD/nvim"                                          ~/.config/nvim

# cmux + OpenCode config
mkdir -p ~/.config/cmux ~/.config/opencode
ln -s "$PWD/cmux/settings.json"                            ~/.config/cmux/settings.json
ln -s "$PWD/opencode/opencode.json"                        ~/.config/opencode/opencode.json

# cmux workspace organizer CLI (onto PATH)
mkdir -p ~/.local/bin
ln -s "$PWD/cmux/organize-workspace"                       ~/.local/bin/organize-workspace

# Themes — Cursor/VS Code Blackout (links into both editors)
./themes/cursor/scripts/install.sh

# presenterm Blackout theme (macOS: presenterm uses App Support unless XDG_CONFIG_HOME is set)
mkdir -p "$HOME/Library/Application Support/presenterm/themes"
ln -s "$PWD/presenterm/themes/blackout.yaml"               "$HOME/Library/Application Support/presenterm/themes/blackout.yaml"

# Auto-push continuous backup (installs + loads the LaunchAgent for this repo)
./auto-push/install.sh
```
