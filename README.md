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
5. Deploys the dotfiles (`~/.zshrc`, `~/.zprofile`, `~/.config/brewfile/Brewfile`).
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

Change settings the normal way (System Settings, Vorssaint, Finder, Dock, trackpad). Within seconds they land in this repo as a local commit; on a new Mac `chezmoi apply` puts them back. Nothing to track by hand.

How it works:

- **One manifest**, [`home/prefs/manifest.toml`](home/prefs/manifest.toml), lists the preference domains (Vorssaint, symbolic hotkeys such as the Spotlight shortcut, Dock, Finder, keyboard/appearance, trackpad, screenshots) with globs of keys to leave out.
- **`prefsync`** (a stdlib-only Python script, deployed to `~/.local/bin/prefsync`) reads the live preferences with `defaults export`, drops volatile or private keys (window frames, recents, timestamps, device names, anything with an email, phone number, UUID or your username; `$HOME` is stored as `@HOME@`), and writes a sorted snapshot to `home/prefs/<domain>.plist`. It commits locally with a message listing the changed keys. It never pushes.
- **Vorssaint uses its own settings backup** (3.4.3+): prefsync reads it with `Vorssaint --export-settings` and restores it with `--import-settings`, quitting Vorssaint for the import and reopening it if it was running. The snapshot is every setting Vorssaint backs up, defaults included, with JSON values key-sorted so diffs stay stable. The screenshot folder is not in Vorssaint's backup, so that one key still goes through `defaults`. Any manifest domain can do this with `export_cmd`/`import_cmd`.
- **A LaunchAgent** (`dev.0x63616c.prefsync`, generated from the manifest, loaded by chezmoi) runs `prefsync capture` whenever a watched preferences file changes, plus once an hour as a safety net. macOS shows a one-time "Background Items Added" notice.
- **Before every chezmoi run** a hook captures first, so applying the repo can never overwrite a change you just made.
- **Applying merges** the snapshot over the live settings (keys not in the snapshot are left alone) and restarts the Dock, Finder or app only if something actually changed. A change pulled from git and a change made on the Mac are both kept (three-way, per key).
- **Safe on a fresh Mac:** a domain is only captured after it has been applied on that Mac, so a new Mac's defaults never overwrite the repo.

Add an app: `prefsync add <bundle-or-domain> [--restart app:Name]` (find the domain with `defaults domains | tr ',' '\n' | grep -i name`). It adds the manifest entry, captures it, and runs `chezmoi apply` to extend the watcher. Then read the new `home/prefs/<domain>.plist` before pushing (public repo).

Check on it: `prefsync status`, `prefsync diff`, `prefsync doctor`, and `~/Library/Logs/prefsync.log`.

## Secrets

No secrets are stored in this repo. Anything sensitive is read from 1Password at apply time. Sign in to 1Password (app, then `op` CLI integration) on the Mac, set `secrets = true` (re-run `chezmoi init` and answer yes), then run `chezmoi apply` again.

## Agents

This repo is operated by an AI agent. Read [AGENTS.md](AGENTS.md) for the rules and the verify loop before changing anything.
