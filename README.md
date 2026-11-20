# dotfiles

Calum's Mac, managed with [chezmoi](https://www.chezmoi.io). Agent-operated: see [AGENTS.md](AGENTS.md).

## Install (fresh Mac)

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply 0x63616c
```

That one line sets up the whole machine. In order, it:

1. Downloads chezmoi and clones this repo into `~/.local/share/chezmoi`.
2. Asks your name and email once (defaults are filled in; press Enter to accept).
3. Installs Homebrew if missing. This asks for your password **once** and also installs the Xcode Command Line Tools.
4. Runs `brew bundle` on [`home/dot_config/brewfile/Brewfile`](home/dot_config/brewfile/Brewfile): every CLI tool and app, including chezmoi itself, so Homebrew takes over updating it.
5. Deploys the dotfiles (zsh, git, SSH, starship and mise config, the Brewfile, `prefsync`).
6. Applies synced macOS settings (see [Settings sync](#settings-sync)), installs the settings watcher, and enables the repo's gitleaks pre-commit hook.

Every step is safe to re-run.


## Day to day

```sh
chezmoi update   # pull the latest from GitHub and apply it
chezmoi apply    # apply the local source (after editing it)
chezmoi diff     # preview what apply would change
```

Edit the source (`chezmoi cd`), never the deployed files in `$HOME`.

## Settings sync

Change settings the normal way (System Settings, Vorssaint, Finder, Dock, trackpad). Within seconds they land in this repo as a local commit; on a new Mac `chezmoi apply` puts them back. Mail's app-icon notification badge is the one preference applied by hand (below).

How it works:

- **One manifest**, [`home/prefs/manifest.toml`](home/prefs/manifest.toml), lists the preference domains (Vorssaint, symbolic hotkeys such as the Spotlight shortcut, Dock, Finder, keyboard/appearance, trackpad, screenshots) with globs of keys to leave out.
- **`prefsync`** (a stdlib-only Python script, deployed to `~/.local/bin/prefsync`) reads the live preferences with `defaults export`, drops volatile or private keys (window frames, recents, timestamps, device names, anything with an email, phone number, UUID or your username; `$HOME` is stored as `@HOME@`), and writes a sorted snapshot to `home/prefs/<domain>.plist`. Finder Go to Folder history, the last connected server, and its nested window state are excluded; reusable view preferences are retained. It commits locally with a message listing the changed keys. It never pushes.
- **Vorssaint uses its own settings backup** (3.4.3+): prefsync reads it with `Vorssaint --export-settings` and restores it with `--import-settings`, quitting Vorssaint for the import and reopening it if it was running. The snapshot is every setting Vorssaint backs up, defaults included, with JSON values key-sorted so diffs stay stable. The screenshot folder is not in Vorssaint's backup, so that one key still goes through `defaults`. Any manifest domain can do this with `export_cmd`/`import_cmd`.
- **A LaunchAgent** (`dev.0x63616c.prefsync`, generated from the manifest, loaded by chezmoi) runs `prefsync capture` whenever a watched preferences file changes, plus once an hour as a safety net. macOS shows a one-time "Background Items Added" notice.
- **Before every chezmoi run** a hook captures first, so applying the repo can never overwrite a change you just made.
- **Applying merges** the snapshot over the live settings (keys not in the snapshot are left alone) and restarts the Dock, Finder or app only if something actually changed. A change pulled from git and a change made on the Mac are both kept (three-way, per key).
- **Safe on a fresh Mac:** a domain is only captured after it has been applied on that Mac, so a new Mac's defaults never overwrite the repo.

**Mail's app-icon badge is manual.** It is off (`com.apple.mail`, Notifications → "Badge application icon") and macOS does not expose that toggle as a preference domain, so `chezmoi apply` leaves it alone. On a new Mac, open Mail's notification settings and turn off only that control if it is on:

```sh
open "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.apple.mail"
```

It is already off on the current Mac. Banners, sounds, previews, accounts, and other apps stay as they are. The record is [`home/prefs/manual.toml`](home/prefs/manual.toml).

Add an app: `prefsync add <bundle-or-domain> [--restart app:Name]` (find the domain with `defaults domains | tr ',' '\n' | grep -i name`). It adds the manifest entry, captures it, and runs `chezmoi apply` to extend the watcher. Then read the new `home/prefs/<domain>.plist` before pushing (public repo).

Check on it: `prefsync status`, `prefsync diff`, `prefsync doctor`, and `~/Library/Logs/prefsync.log`.

## Worktree cleanup

`worktree-cleanup` previews completed `codex/` worktrees for `world-wide-webb`;
`worktree-cleanup --apply` removes eligible worktrees using `wtp`.
The chezmoi-managed LaunchAgent runs on the hour and on load. Merged worktrees
and their local branches are removed without an age delay.
A matching PR merged into `main` proves squash merges; commits already
in freshly fetched `origin/main` also qualify. Unmerged worktrees are removed
after 24 hours observed clean, inactive and at the exact same commit as their
GitHub branch; their local and remote branches are kept. Changes, activity or loss
of remote confirmation reset that timer. An open PR does not block this recoverable
worktree-only cleanup. Local changes, untracked files, locks and active process
working directories are preserved. Ignored environment, database and media files also block removal;
other ignored files, including disposable build caches, are removed with the tree.
Use `git worktree lock --reason 'retain' <path>` to retain a worktree explicitly.
Process checks are best effort: a program can start after the final check, and
programs using files from another working directory are not detected.

The job is scoped to `~/.worktrees/world-wide-webb`; it never removes the main
checkout. Logs rotate in `~/Library/Logs/worktree-cleanup.log`; per-worktree
decisions are in `~/.local/state/worktree-cleanup/last-report.json`. GitHub or
Git failures stop the run without guessing merge state. A file lock prevents
overlapping runs. To stop scheduling, run
`launchctl bootout gui/$(id -u)/dev.0x63616c.worktree-cleanup`.

## Secrets

No secrets are stored in this repo. Anything sensitive is read from 1Password at apply time. Sign in to 1Password (app, then `op` CLI integration) on the Mac, set `secrets = true` (re-run `chezmoi init` and answer yes), then run `chezmoi apply` again.

## Agents

This repo is operated by an AI agent. Read [AGENTS.md](AGENTS.md) for the rules and the verify loop before changing anything.

## Rex and shell aliases

Shell aliases live in [`home/dot_zshrc`](home/dot_zshrc). `code` opens Cursor everywhere (not only in zsh): `~/.local/bin/code` runs `cursor --classic` (the classic editor window, not the Agent Window).
After applying changes, open a new shell or run `source ~/.zshrc`.

Rex shortcuts live in [`home/dot_config/rex/keys.lua`](home/dot_config/rex/keys.lua),
required by [`init.lua`](home/dot_config/rex/init.lua). ⌘K opens the command
palette, ⇧⌘K switches sessions, and the old ⇧⌘P palette shortcut is removed.
Edit Lua for these bindings; app-recorded shortcuts take precedence and can mask it.
Run `rex config reload` after applying. This reload leaves running terminals intact.

Rex's Geist Mono font and vertical sidebar layout are app preferences synced through
prefsync's `com.superlogical.rex` domain.

## Shell

All zsh config lives in one file, `home/dot_zshrc`: aliases, history and
completion, tool integrations, then Homebrew plugins (syntax-highlighting last)
and the Rex PATH guard at the very end. Guard every integration with
`command -v` so a missing tool never breaks the shell. Do not grow a chain of
hostname conditionals. The `reload` alias re-sources `~/.zshrc`.
Run `tests/render-test.sh` after changing shell files.

### Claude accounts

Claude Code has two profiles, each with its own login, side by side:

- `~/.claude-personal` is personal.
- `~/.claude-vov` is the vov profile, on the work account.

The `claude()` function in `home/dot_zshrc` sets `CLAUDE_CONFIG_DIR` to vov
inside `~/coding/vov` and `~/coding/vov-worktrees`, and to personal everywhere
else; the `c` aliases go through it. `.zshrc` also exports personal as the
default (only when nothing set it already, so a shell inside a vov session stays
on vov), which Cursor and scripts pick up. `~/.claude` is a link to
`~/.claude-personal` for anything that sets nothing at all.

Config comes in three layers: shared, personal and vov.

- **Plugins** (skills, hooks, commands, agents, MCP servers, mods) live in
  `claude-plugins/`, a plugin marketplace (`dotfiles`) Claude reads in place:
  edits are live at the next session start or after `/reload-plugins`, with no
  reinstall. `shared` is on in both profiles, `personal` and `vov` in theirs;
  a self-contained mod such as `simple-view` is its own plugin.
- **Settings:** each profile has its own `settings.json`, which Claude owns.
  `home/.chezmoitemplates/claude-settings.py` (rendered into each profile's
  `modify_settings.json.tmpl`) owns only a few keys: which plugins are on per
  layer, the marketplace, the status line command, and transcript retention
  (`cleanupPeriodDays`: 10 years instead of 30 days).
- **Global agent notes:** `home/.chezmoitemplates/claude-CLAUDE.md`, written
  into both profiles. vov's `keybindings.json` links to personal's.

Logins, `.claude.json` (user-scope MCP servers and per-project state),
sessions, history and memory are per profile.

Each session starts with a line naming its profile (the `shared` plugin's
SessionStart hook), and the `shared:claude-profiles` skill tells agents which
layer a change belongs to and where it goes. Read that skill before changing
Claude config.

The status line (`home/dot_local/bin/executable_claude-statusline`) starts with
the profile: `[personal]` dim, `[vov]` (any other `~/.claude-NAME`) highlighted.

The claude-warmup agent pings both profiles every hour (personal, then vov;
a profile whose directory is missing is skipped), so both 5-hour usage windows
restart as soon as they end. Each run logs one line per profile to
`~/Library/Logs/claude-warmup.log`.

On a new Mac, log in once per profile: run `claude` anywhere for personal and
`claude` in `~/coding/vov` for work. `claude auth status` shows which account a
profile is on (prefix `CLAUDE_CONFIG_DIR=~/.claude-vov` for vov). The first
session in each profile installs the `dotfiles` plugins by itself.
`run_once_before_20-claude-profiles.sh.tmpl` moved the old layout (`~/.claude`
as personal, vov linked into it) to this one; it does nothing on a fresh Mac.

### 1Password reads in Claude

Every `op` call from an agent's Bash tool is a new process with no terminal, so
1Password asks for approval almost every time. `home/dot_local/bin/executable_op`
is a shim on PATH ahead of Homebrew's `op`. Outside Claude Code (`CLAUDECODE`
unset) it execs the real `op` untouched. Inside, it caches the stdout of
successful `op read`, `op item get|list` and `op vault get|list` for 30 minutes
in the per-user temp dir (`getconf DARWIN_USER_TEMP_DIR`/op-cache, 0700,
plaintext, cleared on reboot). This is a deliberate trade: for 30 minutes any
process running as Calum can read a cached secret without a prompt.

TOTP (`--otp`, `otp`/`totp` fields), `--out-file`, stdin input and commands
starting with a global flag are never cached. Any command not known to be
read-only (create, edit, delete, move, ...) wipes the cache first. Agents bypass
it with `OP_CACHE=refresh op ...` (fresh fetch, re-cache), `OP_CACHE=off`
(no cache at all) or `op cache clear`; the global `CLAUDE.md` tells them when.

