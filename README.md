# dotfiles

My dotfiles, configs, and other bits worth sharing across machines.

## Contents

### `worktrees/`

Cron-style cleanup for `wtp`-managed git worktrees (used across `~/code/github.com/0x63616c/*` repos). Claude Code's `EnterWorktree({path})` — the form `wtp`'s own workflow requires, since only `wtp add` runs its post_create hooks — never registers the session as the worktree's "owner", so `ExitWorktree` always refuses to remove it. Left unattended, worktrees under `~/.worktrees/<repo>/` never get cleaned up.

| Path | What it does |
|---|---|
| `worktrees/prune-worktrees.sh` | Scans `~/.worktrees/<repo>/**` (any depth, so branch names with slashes work) for worktrees that are both git-clean and whose branch counts as merged into `origin/<default-branch>`, and removes those (worktree + local branch). "Merged" is tested three ways, in order: tip is a literal ancestor of the default branch; every commit has an equivalent patch-id upstream (`git cherry`); or `gh` reports a merged PR for the branch. The last two exist because squash-merged PRs rewrite history, so their tips are never ancestors of main — without them nothing is ever pruned. Anything dirty or genuinely unmerged is skipped and logged — never touches the main checkout. Dry-run by default (prints "WOULD REMOVE"); pass `--apply` to actually delete. Symlinked onto `PATH` as `prune-worktrees`. |
| `worktrees/com.calum.prune-worktrees.plist` | launchd agent running `prune-worktrees --apply` every 15 min (`StartInterval=900`) plus once at login. Each worktree costs ~1G (almost entirely `node_modules`), so the tighter interval keeps accrual bounded; a pass takes ~40s. Sets `PATH` explicitly — launchd's default excludes Homebrew, so `gh` wouldn't resolve and every squash-merged branch was treated as unmerged. Symlinked to `~/Library/LaunchAgents/`; log at `~/.cache/prune-worktrees/launchd.log`. |

### cmux + OpenCode

cmux file-managed settings and OpenCode's cmux plugin list are tracked here.

| Path | What it does |
|---|---|
| `cmux/cmux.json` | Symlink target for `~/.config/cmux/cmux.json` — cmux's current primary config (shortcuts, sidebars, notifications, terminal). Keys absent from the file fall back to cmux's schema defaults, so the notification block is intentionally not present (all defaults). cmux can also write `terminal.resumeCommands` here (session-restore entries, machine-specific `cwd` + agent session IDs) — only OpenCode panes register them, so it stays quiet with Claude Code; delete stale ones rather than committing them. |
| `cmux/settings.json` | Legacy `~/.config/cmux/settings.json` config, superseded by `cmux/cmux.json`. Kept for reference only; not symlinked. |
| `cmux/organize-workspaces` | CLI (symlinked onto PATH) that groups the current cmux window's workspaces by their enclosing git repo — one collapsible group per repo, named after the lowercase repo basename, each with a colour + SF Symbol icon from the palette config (see `cmux/palette.conf`), falling back to a stable name-hash, and every member workspace tinted to its group's colour + its description set to the git branch it's on. Repos are ordered alphabetically; nested sub-folders resolve to their repo; workspaces not in any git repo land in an `other…` group forced last — which only appears when there's a genuine non-git workspace. Empty groups (only their throwaway anchor left, no real workspaces) are deleted. Pinned groups are left floating on top (cmux owns that). Reuses existing groups and skips any rename/colour/icon/description/tint that's already correct, then applies the whole sidebar order in a single atomic `reorder-workspaces` — so re-runs don't shuffle — and prints a coloured tree of the result. `--dry-run` prints the plan; `--window <ref>` targets another window. Every `run` first waits for cmux's RPC socket to answer (up to ~15s) — on shell start the daemon isn't accepting yet, so the first call would otherwise die with `Failed to write to socket (Broken pipe)` — then self-logs its full output (banner + cmux calls + resulting tree) to `$XDG_STATE_HOME/organize-workspaces/run.log` (override with `ORGANIZE_LOG_FILE`, trimmed to the last 2000 lines) — so a backgrounded auto-run whose output goes to `/dev/null` is still inspectable; `organize-workspaces logs [-f] [-n <n>]` tails it. `organize-workspaces install` wires the whole thing up itself — symlinks the script into `~/.local/bin` (override with `ORGANIZE_BIN_DIR`), ensures that dir is on `PATH`, and (re)writes the auto-run snippet in `~/.zshrc` so it runs on every shell opened inside a cmux workspace; the snippet logs a breadcrumb each shell start (including a "NOT on PATH; skipped" line if the command can't be found), so you can tell whether it actually fired. `install` is idempotent and self-healing (refreshes a stale block in place), refuses to overwrite a different file/symlink already holding the name (`--force` repoints it), and warns if another copy shadows it on `PATH`. |
| `cmux/palette.conf` | Curated colour + icon per repo for `organize-workspaces`, symlinked to `~/.config/organize-workspaces/palette.conf` by its `install`. One `<name>  <#RRGGBB\|->  [sf-symbol]` line per repo, whitespace-separated; `-` or an omitted field means "hash this column instead", so a colour can be pinned without pinning an icon. `#` at line start or after the three fields is a comment. Names match lowercase. Any repo absent from this file gets a colour + icon deterministically hashed from its name — stable across runs, so nothing needs listing here unless you dislike what it drew. `organize-workspaces test <name>` prints the resolved pair and whether each half came from this file or the hash. |
| `opencode/opencode.json` | Symlink target for `~/.config/opencode/opencode.json`. Currently schema-only — the cmux OpenCode restore/feed plugins it used to load were removed (`cmux hooks opencode uninstall`); re-add them with `cmux hooks opencode install`. |

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

### `claude/`

[Claude Code](https://claude.com/claude-code) setup. Symlink these into `~/.claude/`.

| Path | What it does |
|---|---|
| `skills/codebase-audit/` | Skill for whole-repo health audits (naming drift, DRY, stale docs, dead code, scale readiness) with a fixed scoreboard report format; repo-scoped counterpart to per-diff code review. |
| `skills/publish-setup/` | Skill for bootstrapping iOS app publishing (Fastlane match, ASC key, secrets sync). |
| `skills/saving-a-memory/` | Skill for where/how to save memories (global `~/.claude/CLAUDE.md` by default; never project-local from a worktree). |
| `skills/writing-goals/` | Skill for composing `/goal` conditions that are tight, transcript-verifiable, and dodge-proof. |
| `skills/using-presenterm/` | Skill for authoring [presenterm](https://github.com/mfontanini/presenterm) terminal slideshows, including the house style (blackout theme, front-matter title slide, implicit slide ends). |
| `statusline-command.sh` | Tokyo Night statusline for Claude Code: left clock `[5:30pm]`, model + effort `(medium)`, cwd (OSC-8 link to the GitHub remote), git branch + dirty flag, `origin/main` short SHA with `(-N, age)` when local `main` is ahead/unpushed (N commits + age of origin/main's tip), and trailing `[Ctx: n%, Tkns: n // 5h: n%, Wk: y%]` (context-window % and session token count, then 5h/weekly rate-limit usage from stdin's `rate_limits`, Pro/Max only — each part, and the whole `//`-prefixed half, omitted when its data is absent; `//` is orange). Wire via `statusLine.command` in `settings.json`. |
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

### git

| Path | What it does |
|---|---|
| `git/gcamai` | `gcam` (`git commit --all --message`) with the message written for you. Feeds `git diff HEAD` (stat + `-U0` body, budgeted per changed file at 12 KB ÷ file count, floor 400 B each, so one huge file can't starve the paths after it alphabetically) plus the last 10 commit subjects to the Codex CLI — `gpt-5.3-codex-spark`, read-only sandbox, `model_reasoning_effort=low`, tools forbidden — and commits whatever single Conventional Commits subject comes back (~3–6s). Deliberately shallow: a decent one-liner fast beats a perfect one slow. While it thinks, a human-speed typing animation cycles phrases behind a live `(5s)` elapsed counter. Logs every run (codex output, context, chosen message) to `$XDG_STATE_HOME/gcamai/`, newest also at `latest.log`. Env: `GCAMAI_DRY=1` print the message without committing, `GCAMAI_DEBUG=1` skip the animation and print the log path, `GCAMAI_MODEL` / `GCAMAI_DIFF_BYTES` to override. |

### `restic/`

Daily encrypted backup of this MacBook to the Synology NAS (`hometb`) over Tailscale. Before this existed the machine had no backup of any kind — `tmutil destinationinfo` said "No destinations configured", 375G on a disk 91% full, one copy of everything. Deliberately **not** Time Machine: TM can only target an SMB share root (so it can't live under `Backups/Devices/`) and it corrupts its sparsebundle over anything flakier than a LAN. restic is encrypted client-side, deduplicated, and works over SFTP from anywhere on the tailnet.

| Path | What it does |
|---|---|
| `restic/restic-backup.sh` | The whole system, mode-dispatched: `backup` (snapshot + `forget`, daily), `maintain` (`prune` + `check`, weekly), `verify` (deep data check), `status` (repo stats), `progress` (live progress of a running backup, read off the --json stream so it never touches the repo and cannot block on the repo lock). Symlinked onto `PATH` as `restic-backup`. Preflight gates before every run — NAS SSH port reachable (a TCP test, not `tailscale ping`: the tailscale layer answers happily while DSM's sshd is down, and then restic hangs instead of skipping), AC power or battery >40%, and a `mkdir`-based lock with stale-PID reclaim so a multi-hour `prune` can't have a `backup` stack up behind it. Every outcome — success, failure, and each distinct skip reason — posts to ntfy. Runs restic under `taskpolicy -b` (background QoS throttles disk I/O as well as CPU, unlike `nice`), backs up `/Users/calum` with `-x` so it can't wander into the `/Volumes/*` SMB mounts or the OrbStack NFS mount, and passes the SSH key via restic's own `sftp.args` rather than adding a `Host` block to `~/.ssh/config`. Retention is `--keep-last 3 --keep-daily 14 --keep-weekly 8 --keep-monthly 24 --keep-yearly -1 --keep-tag keep` (~50 snapshots, unlimited yearlies, and anything tagged `keep` pinned forever). `forget` runs daily because it's metadata-only and takes seconds; `prune` is weekly because it repacks data over SFTP and takes hours. |
| `restic/restic-excludes.txt` | The `--exclude-file`, with the measured size and justification against each line — only things a package manager, compiler, or app can rebuild. ~119G of caches, package stores, and git worktrees. Three entries are load-bearing and non-obvious: `~/Library/CloudStorage` holds macOS File Provider mounts (CloudMounter maps the NAS's own `Homelab` share here), and **`-x` cannot exclude these** — File Provider mounts never appear in `mount` and report the same `st_dev` as the home directory, so there is no boundary for `--one-file-system` to stop at. The first backup run walked into it and estimated 9.06 TB to process instead of 128 GB, reading the NAS over the network in order to write it back to the NAS; `Photos Library.photoslibrary` is excluded because iCloud Photos "Optimise Mac Storage" is on and `originals/` holds **57 MB of a 31 GB library** — backing it up would store a database and thumbnails and recover no photographs; and `~/.recovery` is excluded because it holds the rendered recovery sheet, which would otherwise put both repo passwords inside the repo they unlock. `~/Library/Photos` is deliberately **kept** despite the name — it's the Syndication library ("Shared with You" media), real content, not cache. |
| `restic/com.calum.restic-backup.plist` | launchd agent, daily at 12:00. Noon rather than overnight because a laptop is asleep at 03:00, so a night schedule really means "runs when you next open the lid" — precisely when you want the machine responsive. `StartCalendarInterval` (not `StartInterval`) still fires a missed run on wake, so sleep and travel don't leave silent gaps. Invokes `/bin/bash <script>` rather than the script directly because macOS attributes Full Disk Access to the executable launchd spawns — **without FDA restic silently skips `~/Library`, `~/Documents` and `~/Desktop` and still exits 0**, producing green backups that are missing the data you care about. Sets `PATH` explicitly (Homebrew for `restic`, `/usr/sbin` for `taskpolicy`); the `prune-worktrees` agent lost a day of runs to launchd's default `PATH` excluding Homebrew. |
| `restic/com.calum.restic-maintain.plist` | launchd agent, Sundays 12:30. `prune` + `check`; in the first week of each month it also runs `check --read-data-subset=<month>/12`. The `n/t` form is a *deterministic* partition of the pack files, so rotating the month through it verifies every byte in the repo exactly once a year — the `x%` form restic also accepts picks packs at random and guarantees no coverage. Plain `check` only validates structure and never opens a pack, so this is the only thing that catches bitrot. |
| `restic/recovery-sheet.template.html` | Placeholders-only template (this repo is public) for the printable offline recovery sheet — repo URL, both passwords, restore commands, and blanks to hand-write the 1Password Emergency Kit and Secret Key. Rendered at install time to `~/.recovery/`, which is on the exclude list. Exists because the repo password is the single point of failure: keep it only on the Mac being backed up and the backup is unopenable in exactly the disaster it was built for. |

Secrets live outside this repo (`~/.config/restic/`, mode 600) — no SOPS, because the age key would sit unprotected in the same home directory as the file it encrypts, which is complexity without security. The repo carries a **second** password via `restic key add` that is never stored on this Mac, so a stolen laptop can be locked out with `restic key remove` without touching the data.

Known gaps, in priority order: photo originals exist only in iCloud and need Immich or `osxphotos` pulling them down; there is no bare-metal restore (Time Machine, later); ntfy reports events that happen but cannot report a job that never ran, so silence still looks like success until a dead-man's switch is added; and the SSH key can delete the repo, which wants append-only `rest-server` or DSM Btrfs snapshots.

## Install

```bash
git clone https://github.com/0x63616c/dotfiles.git
cd dotfiles

# gcamai — AI-written commit subject (needs the `codex` CLI on PATH)
echo "alias gcamai='$PWD/git/gcamai'" >> ~/.aliases

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
ln -s "$PWD/cmux/cmux.json"                                ~/.config/cmux/cmux.json
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

# restic backup → Synology NAS over Tailscale
brew install restic
ln -s "$PWD/restic/restic-backup.sh"                       ~/.local/bin/restic-backup

# 1. Dedicated SSH key, no passphrase (launchd can't type one, and a passphrase
#    protects nothing an attacker with your disk doesn't already have)
ssh-keygen -t ed25519 -f ~/.ssh/id_restic_hometb -N "" -C "restic-macbook-pro"
ssh-copy-id -i ~/.ssh/id_restic_hometb.pub calumwebb@hometb.tail8c014d.ts.net
#    then in DSM, prefix that authorized_keys line with:
#      restrict,from="<this mac's tailscale IP>"

# 2. Secrets — outside this repo, which is public
mkdir -p ~/.config/restic ~/.recovery && chmod 700 ~/.config/restic ~/.recovery
(umask 077; openssl rand -base64 32 | tr -d '\n' > ~/.config/restic/hometb-password)
cat > ~/.config/restic/env <<'EOF'
# Always the MagicDNS FQDN, never bare `hometb` — that resolves to the LAN IP
# first and silently stops working the moment you leave the house.
NAS_SSH_HOST=hometb.tail8c014d.ts.net
NAS_SSH_KEY=/Users/calum/.ssh/id_restic_hometb
RESTIC_REPOSITORY='sftp:calumwebb@hometb.tail8c014d.ts.net:/volumeN/Storage/Backups/Devices/macbook-pro/restic'
NTFY_TOPIC=0x63616c-macbook-backups
EOF
chmod 600 ~/.config/restic/env

# 3. Init, plus a SECOND password that never lives on this Mac — so a stolen
#    laptop can be locked out with `restic key remove` without losing the data
restic init
restic key add

# 4. Schedule
mkdir -p ~/.cache/restic-backup
ln -s "$PWD/restic/com.calum.restic-backup.plist"          ~/Library/LaunchAgents/com.calum.restic-backup.plist
ln -s "$PWD/restic/com.calum.restic-maintain.plist"        ~/Library/LaunchAgents/com.calum.restic-maintain.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.calum.restic-backup.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.calum.restic-maintain.plist

# 5. Grant /bin/bash Full Disk Access in System Settings → Privacy & Security.
#    NOT optional and NOT self-announcing: without it restic skips ~/Library,
#    ~/Documents and ~/Desktop and still exits 0. Verify it actually took:
restic-backup backup
restic ls latest /Users/calum/Library/Messages | head   # empty ⇒ FDA is missing

# 6. Render the recovery sheet, print it, store it offsite, delete the file
```
