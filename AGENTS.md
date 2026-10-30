# AGENTS.md: Calum's Mac setup (chezmoi)

Public repo `0x63616c/dotfiles` (so the plain chezmoi one-liner works; **never commit secrets**). It manages Calum's MacBook Pro (Apple Silicon, zsh) with chezmoi. Agents operate it; Calum does not maintain it by hand. `CLAUDE.md` contains only `@AGENTS.md` (keep exactly). The previous repo is `0x63616c/dotfiles-old`: read-only reference; port pieces only when Calum chooses.


## The loop (follow strictly, in order)
1. Edit the **source** (`chezmoi cd` or `~/.local/share/chezmoi`). Never edit deployed files in `$HOME` directly. If an app changed its own file, use `chezmoi re-add`/`chezmoi merge` deliberately.
2. `chezmoi doctor`: fix anything red.
3. `chezmoi diff`: read it.
4. `chezmoi apply --dry-run -v`: confirm the plan. Scripts do NOT run in dry-run, so read the scripts you changed.
5. `chezmoi apply -v`.
6. `chezmoi verify --exclude=scripts`: deployed files match the source.
7. `python3 -m unittest discover -s tests`, `prefsync doctor`, `brew bundle check --file ~/.config/brewfile/Brewfile`, plus app checks (`prefsync status`, fresh `zsh -i -c 'echo ok'`). Report what you checked.
8. Before every commit: `tests/render-test.sh` (renders everything to a temp dir, validates the LaunchAgent, shellchecks every script) and `ruff check` + `ruff format --check` on `home/dot_local/bin/executable_prefsync tests`.
9. Commit (gitleaks hook runs) and push to `main`. Auto-commit/auto-push stay off.

## Rules
- **No secrets in the repo.** Reference 1Password with `op://vault/item/field` (read at apply time via `onepasswordRead` / `op read`). API keys for MCP live in the macOS Keychain. Never paste tokens, keys, or full app plists.
- **Apps that rewrite their own config** (OpenCode `cli.json`, Claude `settings.json`, KiCad, etc.): use `modify_` scripts that patch only the keys we own; do not commit whole files.
- **Preferences go through `prefsync`**, never ad-hoc `defaults write` scripts and never hand-copied plists. To add an app or system area: `prefsync add <domain>` (see below).
- **Brewfile and preference snapshots** are applied by `run_onchange_` scripts under `home/.chezmoiscripts/` so they re-run only when their content changes. Add apps to the Brewfile instead of installing by hand; manually installed apps get "brewified" later.
- Deliberately excluded: Mole (Vorssaint replaces it), Alfred (uninstalled), MacTap, 1Password Installer.
- Don't delete or migrate anything from the old repo without Calum choosing it.
- Keep scripts idempotent and loud on failure (non-zero exit with a clear message).

## Settings sync (prefsync): operating it

Calum changes settings in the apps/System Settings; the LaunchAgent captures them into `home/prefs/` and commits locally (`prefs(<domain>): key old→new, ...`, author = GitHub noreply). **Nothing is pushed automatically: you review and push.**

**Before pushing, review the captured diffs** (the repo is public):
1. `git log --stat origin/main..HEAD` then `git diff origin/main -- home/prefs` and read every value. Look for paths, names, emails, phone numbers, device or network names, tokens. `prefsync diff` also lists keys the safety nets auto-denied.
2. If something private/volatile slipped in: add a deny glob to that domain in `home/prefs/manifest.toml`, run `prefsync capture --force <domain>`, and rewrite the unpushed commit(s) (`git rebase -i origin/main`; the history is unpushed so this is fine). If it was already pushed, tell Calum.
3. gitleaks runs on every commit (hook); a failed hook leaves the snapshot uncommitted and logs an error (`prefsync doctor` warns). Fix and `prefsync capture`.
4. Push: `git push origin main` from the Mac (SSH via the 1Password agent).

**Add a domain:** `prefsync add <domain> [--restart app:Name | killall:Proc | cmd:...] [--deny GLOB]` (domain list: `defaults domains | tr ',' '\n'`). It edits the manifest, takes the first snapshot, and runs `chezmoi apply` so the watcher includes it. Then review the plist, add deny globs, commit. NSGlobalDomain is allow-listed (keyboard/appearance); add keys to its `allow` list.

**Vorssaint (export_cmd/import_cmd domain):** captured from `Vorssaint --export-settings` (works with the app quit, does not touch its plist) and applied with `--import-settings`. The importer refuses while the app runs and *replaces* every setting it knows (missing = reset), so `prefsync apply` quits the app, imports the app's own full export with only the changed keys overlaid, then restores any key the import touched by accident and deletes the defaults it wrote out. It reopens the app only if it was running. `defaults_keys` (`screenshotSaveFolder`) are not in the export and go through `defaults`. Never run the Vorssaint binary bare or with `--help`: that launches a second GUI instance. Vorssaint updates that add settings or change defaults show up as captured commits (the snapshot pins defaults); review them like any other.

**Wispr Flow (json_file domain `wispr-flow`):** Wispr's account sync does not cover its keyboard shortcuts or most app preferences; they live in `~/Library/Application Support/Wispr Flow/config.json` under `prefs.user`, next to device IDs, session data, account identity and caches. prefsync syncs an exact allow-list of `prefs.user` keys (shortcuts, dictation/polish/style, sounds, focus mode, notetaker and app preferences) into `home/prefs/wispr-flow.json`; `deny_paths` strips counters/timestamps nested inside them, and the email/UUID/username safety nets still apply. Never add identity, account, subscription, ID, timestamp, counter, onboarding/"seen" or device keys to its allow list. Apply quits Wispr Flow (it rewrites the whole file from memory), backs config.json up to `~/.local/state/prefsync/backups/wispr-flow/` (0600, last 10), merges only the snapshot keys (dicts merge, nothing else touched, JSON validated, indentation and mode kept) and reopens it if it was running. If config.json does not exist yet (fresh Mac), apply skips: open Wispr Flow once and sign in, then `prefsync apply wispr-flow`.

**Debug:** `prefsync doctor` (agent loaded, WatchPaths match the manifest, git identity, gitleaks, per-domain export, recent errors), `prefsync status` / `prefsync diff`, `tail -f ~/Library/Logs/prefsync.log` (new keys, captures, commits, errors; rotated 3x256 KB), `launchctl print gui/$(id -u)/dev.0x63616c.prefsync`, agent stderr in `~/Library/Logs/prefsync.launchd.log`. State (last-synced base copies, seen keys, lock) lives in `~/.local/state/prefsync/`; deleting a domain's `base/<domain>.plist` makes the next `prefsync apply` re-baseline it.

**Rules:** capture never overwrites an unapplied pulled snapshot (three-way by key); apply merges and never deletes live keys; the shrink guard refuses a capture that loses more than half the keys (`--force` to override); a domain is only captured after being applied on that Mac. To change a value from the repo side, edit the snapshot value and `chezmoi apply`. Dock layout and Finder per-folder view state are deliberately not synced (bookmark data with local paths). Text replacements (contain a phone number) are not synced.
