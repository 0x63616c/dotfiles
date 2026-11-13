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

Shell aliases live in [`home/dot_config/zsh/personal.zsh`](home/dot_config/zsh/personal.zsh); `code` opens Cursor on the personal Mac.
After applying changes, open a new shell or run `source ~/.zshrc`.

[`home/dot_config/rex/init.lua`](home/dot_config/rex/init.lua) declares the
`homelab-macbook` remote as `ssh://coding@homelab-macbook.local` using your
existing SSH key for CLI commands such as `rex -S homelab-macbook ls`. That
`.local` address works on the home LAN. Reload an already running local Rex
server with `rex config reload` after applying. Rex currently keeps the Mac
app’s host list separate. prefsync restores that GUI entry through
[`rex-host-prefs`](home/dot_local/bin/executable_rex-host-prefs), which merges
only the homelab entry. Its snapshot stores an enabled flag; host/session IDs
and other remote hosts stay local. Open Rex once on a fresh Mac, then run
`prefsync apply com.superlogical.rex`. Restoring a missing entry quits and
reopens the app; existing remote terminals keep running on the MacBook.

Rex shortcuts edited in Settings are captured by prefsync into
[`home/prefs/rex-shortcuts.json`](home/prefs/rex-shortcuts.json). On a fresh Mac,
open Rex once, then run `prefsync apply rex-shortcuts` to restore them. Applying
changed shortcuts briefly quits and reopens Rex; matching settings are left alone.

## Shell profiles

`home/dot_zshrc.tmpl` renders a small loader: shared `~/.config/zsh/common.zsh`,
then `personal.zsh` or `coding.zsh`. Put shared history/completion/prompt behavior
in common; put aliases, plugin paths and role-specific integrations in the profile.
Do not duplicate shared settings or grow a chain of hostname conditionals.
The shared `reload` alias re-sources `~/.zshrc` and its active profile.

`chezmoi init` persists `[data].profile` (`personal` or `coding`) in the local
chezmoi config. An explicit profile wins; the initial default is `coding` for the
`coding` account and `personal` otherwise. Existing personal configs without that
key retain the same default. To initialize the coding account deliberately:

```sh
chezmoi init 0x63616c --promptString 'Shell profile=coding'
chezmoi diff
chezmoi apply
```

The coding profile is an allow-list in `home/.chezmoiignore.tmpl`: only zsh,
Starship, Claude settings and Claude guidance deploy. Every chezmoi script,
personal preference, Rex client config, SSH identity and Git signing config is
excluded. A normal apply/update is safe to run as coding; do not bootstrap the
personal profile there. Later updates are explicit `chezmoi update` calls.

On the homelab, WWW's `projects/homelab/modules/coding.nix` owns Nix zsh, Claude,
chezmoi and permanent coding tools. The coding plugin file uses the stable Nix
system profile; the personal one uses Homebrew. Starship always shows the hostname
on coding, including Rex terminals that were not opened through an SSH shell.

`home/private_dot_claude/CLAUDE.md` is coding-only package/configuration guidance.
`modify_settings.json.tmpl` merges just the coding account's
`env.DISABLE_AUTOUPDATER=1`, preserving local Claude settings and Rex hooks.
Do not add credentials, session/history files, project trust or `~/.claude.json`.
The personal Mac's Claude configuration is not managed by this profile change.
Provider login and GitHub credentials are provisioned separately on coding;
never copy the personal SSH private key or assume signing is available remotely.

Before changing a profile or its allow-list, run `tests/render-test.sh`: it renders
both roles and checks that coding cannot run personal scripts or receive private
configuration. Add another small shared file only when common.zsh becomes unwieldy;
keep its source order explicit in the loader.
