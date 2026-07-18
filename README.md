# dotfiles

My dotfiles, configs, and other bits worth sharing across machines.

## Contents

### cmux + OpenCode

cmux file-managed settings and OpenCode's cmux plugin list are tracked here, while
cmux's volatile session restore state stays local.

| Path | What it does |
|---|---|
| `cmux/settings.json` | Symlink target for `~/.config/cmux/settings.json`. Stores stable cmux settings such as keyboard shortcuts. Do not track `~/.config/cmux/cmux.json`, it contains volatile `terminal.resumeCommands` session IDs. |
| `cmux/organize-workspaces` | CLI (symlinked onto PATH) that groups the current cmux window's workspaces by their enclosing git repo — one collapsible group per repo, named after the lowercase repo basename, each with a colour + SF Symbol icon from the palette config (see `cmux/palette.conf`), falling back to a stable name-hash, and every member workspace tinted to its group's colour + its description set to the git branch it's on. Repos are ordered alphabetically; nested sub-folders resolve to their repo; workspaces not in any git repo land in an `other…` group forced last — which only appears when there's a genuine non-git workspace. Empty groups (only their throwaway anchor left, no real workspaces) are deleted. Pinned groups are left floating on top (cmux owns that). Reuses existing groups and skips any rename/colour/icon/description/tint that's already correct, then applies the whole sidebar order in a single atomic `reorder-workspaces` — so re-runs don't shuffle — and prints a coloured tree of the result. `--dry-run` prints the plan; `--window <ref>` targets another window. Every `run` first waits for cmux's RPC socket to answer (up to ~15s) — on shell start the daemon isn't accepting yet, so the first call would otherwise die with `Failed to write to socket (Broken pipe)` — then self-logs its full output (banner + cmux calls + resulting tree) to `$XDG_STATE_HOME/organize-workspaces/run.log` (override with `ORGANIZE_LOG_FILE`, trimmed to the last 2000 lines) — so a backgrounded auto-run whose output goes to `/dev/null` is still inspectable; `organize-workspaces logs [-f] [-n <n>]` tails it. `organize-workspaces install` wires the whole thing up itself — symlinks the script into `~/.local/bin` (override with `ORGANIZE_BIN_DIR`), ensures that dir is on `PATH`, and (re)writes the auto-run snippet in `~/.zshrc` so it runs on every shell opened inside a cmux workspace; the snippet logs a breadcrumb each shell start (including a "NOT on PATH; skipped" line if the command can't be found), so you can tell whether it actually fired. `install` is idempotent and self-healing (refreshes a stale block in place), refuses to overwrite a different file/symlink already holding the name (`--force` repoints it), and warns if another copy shadows it on `PATH`. |
| `cmux/palette.conf` | Curated colour + icon per repo for `organize-workspaces`, symlinked to `~/.config/organize-workspaces/palette.conf` by its `install`. One `<name>  <#RRGGBB\|->  [sf-symbol]` line per repo, whitespace-separated; `-` or an omitted field means "hash this column instead", so a colour can be pinned without pinning an icon. `#` at line start or after the three fields is a comment. Names match lowercase. Any repo absent from this file gets a colour + icon deterministically hashed from its name — stable across runs, so nothing needs listing here unless you dislike what it drew. `organize-workspaces test <name>` prints the resolved pair and whether each half came from this file or the hash. |
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
| `nvim/lua/plugins/snacks-dashboard.lua` | Dashboard header: CALUM ASCII art over a status line for this repo, justified to the art's width — short SHA on the left, commit age + sync state on the right (`#a309986` … `5m ago ✓`). `✓` in sync, `⇣N` remote has N commits to pull, `⇡N` N local commits unpushed. Locates the repo by resolving its own path through the `~/.config/nvim` symlink, so it works wherever the repo is cloned. Sync state is read from the cached remote ref (no network on startup); a detached `git fetch` refreshes it for the next launch. |

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

### `hammerspoon/`

macOS automation config. `~/.hammerspoon` is a symlink to `hammerspoon/`.
Requires `brew install --cask hammerspoon media-control`, plus Accessibility
permission for Hammerspoon (System Settings → Privacy & Security → Accessibility).

| Path | What it does |
|---|---|
| `hammerspoon/init.lua` | Mic-watcher: auto pause/resume media around Wispr Flow dictation. Polls the default input device's in-use state; when any app grabs the mic (Wispr recording) it sends a system-wide play/pause toggle via `media-control` to pause whatever's playing (Spotify, YouTube, anything in the media-key routing), and toggles again on mic release to resume. Toggles fire only in mic-on/mic-off pairs, so a failed dictation launch (mic never grabbed) does nothing and playback state can't desync. Pressing the physical play/pause media key mid-dictation sets a user-took-control flag and the auto-resume is skipped (an eventtap watches `systemDefined` key events; needs Accessibility). Known limits: resuming by clicking a player's UI mid-dictation isn't detected (only the media key is), and any mic-grabbing app (Zoom etc.) also triggers the pause. Reading playback state via MediaRemote (`nowplaying-cli`, `media-control get`) is blind to Chrome on macOS 26 — that's why the design is a stateless paired toggle rather than pause/play commands. |

### `splitflap/`

A complete, self-contained build plan for a **modular 4×16 (64-module) split-flap
display** — 3D-printable on a Bambu (dual-color), ESP32-driven, with a web control
app, culminating in "HELLO WORLD". Not a dotfile: nothing to symlink, it's a
project you build from. Start at `splitflap/docs/00-build-guide.md`.

| Path | What it does |
|---|---|
| `splitflap/docs/00-build-guide.md` | Master guide — every phase from empty printer to "HELLO WORLD" (two paths, honest about what to print vs. build). |
| `splitflap/docs/01-bom.md` | Bill of materials + real 2025–26 pricing; cost per one (~$4/module at scale) and for all (~$425 for 4×16), re-checked arithmetic. |
| `splitflap/docs/02-dimensions.md` | Every part dimension, tolerance, and Bambu print setting. |
| `splitflap/docs/03-electronics.md` | Wiring, the 74HC595/165 shift-register driver chain, and the power budget. |
| `splitflap/docs/04-research-notes.md` | Cited, adversarially-verified research the build rests on (24 confirmed / 1 refuted), with honest caveats on what pricing/specs are estimated vs. verified. |
| `splitflap/firmware/splitflap-esp32/` | ESP32/PlatformIO firmware: non-blocking stepper scheduler, hall homing, WiFi, HTTP `/api/text`, status WebSocket. `bringup` (1 module) + `board` (full 4×16) build profiles. |
| `splitflap/webapp/index.html` | Single-file control app with a live split-flap preview; served off the ESP32 or opened locally. |
| `splitflap/hardware/openscad/` | Parametric geometry: `params.scad` (all dims), `enclosure.scad` (black snap-together bezel), `module.scad` (resizable mechanism), `fit_test.scad` (tolerance calibration print). |
| `splitflap/hardware/pcb/README.md` | Shift-register driver board (6 modules/board, ×11) — schematic, netlist, JLCPCB order notes. |
| `splitflap/hardware/flaps/charset.json` | Canonical 48-glyph flap order (A–Z, 0–9, punctuation, `$ £ € ¥`); firmware + web app both derive from it. |

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

# Hammerspoon (mic-watcher: auto pause/resume media around dictation)
brew install --cask hammerspoon
brew install media-control
ln -s "$PWD/hammerspoon"                                   ~/.hammerspoon

# cmux + OpenCode config
mkdir -p ~/.config/cmux ~/.config/opencode
ln -s "$PWD/cmux/settings.json"                            ~/.config/cmux/settings.json
ln -s "$PWD/opencode/opencode.json"                        ~/.config/opencode/opencode.json

# cmux workspace organizer CLI — self-installing:
# symlinks itself into ~/.local/bin (override with ORGANIZE_BIN_DIR), makes sure
# that dir is on PATH, symlinks cmux/palette.conf to
# ~/.config/organize-workspaces/palette.conf, and appends the auto-run snippet
# to ~/.zshrc. Idempotent.
# Refuses to clobber a different organize-workspaces already holding the name
# (pass --force to repoint it), leaves an existing palette.conf of your own
# alone, and warns if another copy shadows it on PATH.
./cmux/organize-workspaces install

# Themes — Cursor/VS Code Blackout (links into both editors)
./themes/cursor/scripts/install.sh

# presenterm Blackout theme (macOS: presenterm uses App Support unless XDG_CONFIG_HOME is set)
mkdir -p "$HOME/Library/Application Support/presenterm/themes"
ln -s "$PWD/presenterm/themes/blackout.yaml"               "$HOME/Library/Application Support/presenterm/themes/blackout.yaml"

# Auto-push continuous backup (installs + loads the LaunchAgent for this repo)
./auto-push/install.sh
```
