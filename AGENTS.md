# AGENTS.md: Calum's Mac setup (chezmoi)

Public repo `0x63616c/dotfiles` (so the plain chezmoi one-liner works; **never commit secrets**). It manages Calum's MacBook Pro (Apple Silicon, zsh) with chezmoi. Agents operate it; Calum does not maintain it by hand. `CLAUDE.md` contains only `@AGENTS.md` (keep exactly). The previous repo is `0x63616c/dotfiles-old`: read-only reference; port pieces only when Calum chooses.


## The loop (follow strictly, in order)
1. Edit the **source** (`chezmoi cd` or `~/.local/share/chezmoi`). Never edit deployed files in `$HOME` directly. If an app changed its own file, use `chezmoi re-add`/`chezmoi merge` deliberately.
2. `chezmoi doctor`: fix anything red.
3. `chezmoi diff`: read it.
4. `chezmoi apply --dry-run -v`: confirm the plan. Scripts do NOT run in dry-run, so read the scripts you changed.
5. `chezmoi apply -v`.
6. `chezmoi verify --exclude=scripts`: deployed files match the source.
7. `python3 -m unittest discover -s tests`, `prefsync doctor`, `brew bundle check --file ~/.config/brewfile/Brewfile`, plus app checks (`defaults read com.vorssaint.utils`, fresh `zsh -i -c 'echo ok'`). Report what you checked.
8. `shellcheck` the scripts and `ruff check home/dot_local/bin/executable_prefsync tests` (`tests/render-test.sh` renders and shellchecks the `.tmpl` scripts too).
9. Render test, before every commit: `tests/render-test.sh` (renders everything to a temp dir, validates the LaunchAgent, runs shellcheck).
10. Commit (gitleaks hook runs) and push to `main`. Auto-commit/auto-push stay off.

## Rules
- **No secrets in the repo.** Reference 1Password with `op://vault/item/field` (read at apply time via `onepasswordRead` / `op read`). API keys for MCP live in the macOS Keychain. Never paste tokens, keys, or full app plists.
- **Apps that rewrite their own config** (OpenCode `cli.json`, Claude `settings.json`, KiCad, cmux, etc.): use `modify_` scripts that patch only the keys we own; do not commit whole files.
- **Preferences go through `prefsync`**, never ad-hoc `defaults write` scripts and never hand-copied plists. To add an app or system area: `prefsync add <domain>` (see below).
- **Brewfile / macOS defaults** are applied by `run_onchange_` scripts under `home/.chezmoiscripts/` so they re-run only when their content changes. Add apps to the Brewfile instead of installing by hand; manually installed apps get "brewified" later.
- Deliberately excluded: Mole (Vorssaint replaces it), Alfred (uninstalled), MacTap, 1Password Installer.
- Don't delete or migrate anything from the old repo without Calum choosing it.
- Keep scripts idempotent and loud on failure (non-zero exit with a clear message).

## Settings sync (prefsync): operating it

Calum changes settings in the apps/System Settings; the LaunchAgent captures them into `home/prefs/` and commits locally (`prefs(<domain>): key old→new, ...`, author = GitHub noreply). **Nothing is pushed automatically: you review and push.**

**Before pushing, review the captured diffs** (the repo is public):
1. `git log --stat origin/main..HEAD` then `git diff origin/main -- home/prefs` and read every value. Look for paths, names, emails, phone numbers, device or network names, tokens. `prefsync diff` also lists keys the safety nets auto-denied.
2. If something private/volatile slipped in: add a deny glob to that domain in `home/prefs/manifest.toml`, run `prefsync capture --force <domain>`, and rewrite the unpushed commit(s) (`git rebase -i origin/main`; the history is unpushed so this is fine). If it was already pushed, tell Calum.
3. gitleaks runs on every commit (hook); a failed hook leaves the snapshot uncommitted and logs an error (`prefsync doctor` warns). Fix and `prefsync capture`.
4. Push: `git push origin main` (Mac git has no GitHub credentials: pull the commits to the box clone and push with `gh` from the box).

**Add a domain:** `prefsync add <domain> [--restart app:Name | killall:Proc | cmd:...] [--deny GLOB]` (domain list: `defaults domains | tr ',' '\n'`). It edits the manifest, takes the first snapshot, and runs `chezmoi apply` so the watcher includes it. Then review the plist, add deny globs, commit. NSGlobalDomain is allow-listed (keyboard/appearance); add keys to its `allow` list.

**Debug:** `prefsync doctor` (agent loaded, WatchPaths match the manifest, git identity, gitleaks, per-domain export, recent errors), `prefsync status` / `prefsync diff`, `tail -f ~/Library/Logs/prefsync.log` (new keys, captures, commits, errors; rotated 3x256 KB), `launchctl print gui/$(id -u)/dev.0x63616c.prefsync`, agent stderr in `~/Library/Logs/prefsync.launchd.log`. State (last-synced base copies, seen keys, lock) lives in `~/.local/state/prefsync/`; deleting a domain's `base/<domain>.plist` makes the next `prefsync apply` re-baseline it.

**Rules:** capture never overwrites an unapplied pulled snapshot (three-way by key); apply merges and never deletes live keys; the shrink guard refuses a capture that loses more than half the keys (`--force` to override); a domain is only captured after being applied on that Mac. To change a value from the repo side, edit the snapshot value and `chezmoi apply`. Dock layout and Finder per-folder view state are deliberately not synced (bookmark data with local paths). Text replacements (contain a phone number) are not synced.
