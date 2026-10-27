# AGENTS.md: Calum's Mac setup (chezmoi)

Public repo `0x63616c/dotfiles` (so the plain chezmoi one-liner works; **never commit secrets**). It manages Calum's MacBook Pro (Apple Silicon, zsh) with chezmoi. Agents operate it; Calum does not maintain it by hand. `CLAUDE.md` contains only `@AGENTS.md` (keep exactly). The previous repo is `0x63616c/dotfiles-old`: read-only reference; port pieces only when Calum chooses.

## Layout
The repo root holds docs and tooling; `.chezmoiroot` is `home`, so chezmoi's source state is `home/` (nothing at the root is deployed to `$HOME`). Source dir on the Mac: `~/.local/share/chezmoi`.

| Path | Deploys to / does |
|---|---|
| `.chezmoiroot` | contains `home` |
| `home/.chezmoi.toml.tmpl` | per-machine config: name, email (GitHub noreply default), hostname, `secrets` flag; autoCommit/autoPush off |
| `home/dot_zshrc`, `home/dot_zprofile` | `~/.zshrc`, `~/.zprofile` (zsh, no Oh My Zsh; every integration guarded) |
| `home/dot_config/brewfile/Brewfile` | `~/.config/brewfile/Brewfile`: core Brewfile (formulae, casks, mas) |
| `home/.chezmoiscripts/run_before_00-ensure-homebrew.sh` | installs Homebrew + Xcode CLT if missing (sudo password once) |
| `home/.chezmoiscripts/run_onchange_before_10-brew-bundle.sh.tmpl` | `brew bundle` from the SOURCE Brewfile (it deploys after before-scripts) when its hash changes |
| `home/.chezmoiscripts/run_once_after_05-git-hooks.sh.tmpl` | sets `core.hooksPath=.githooks` on the repo |
| `home/.chezmoiscripts/run_onchange_after_20-vorssaint-defaults.sh.tmpl` | writes selected Vorssaint keys (`com.vorssaint.utils`) via `defaults write` |
| `.githooks/pre-commit` | gitleaks secret scan on staged changes |

Bootstrap on a new Mac (one line): `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply 0x63616c`. Scripts are numbered; apps install (before) then settings apply (after). All scripts are idempotent, `set -eu`.

## The loop (follow strictly, in order)
1. Edit the **source** (`chezmoi cd` or `~/.local/share/chezmoi`). Never edit deployed files in `$HOME` directly. If an app changed its own file, use `chezmoi re-add`/`chezmoi merge` deliberately.
2. `chezmoi doctor`: fix anything red.
3. `chezmoi diff`: read it.
4. `chezmoi apply --dry-run -v`: confirm the plan. Scripts do NOT run in dry-run, so read the scripts you changed.
5. `chezmoi apply -v`.
6. `chezmoi verify --exclude=scripts`: deployed files match the source.
7. `brew bundle check --file ~/.config/brewfile/Brewfile`, plus app checks (`defaults read com.vorssaint.utils`, fresh `zsh -i -c 'echo ok'`). Report what you checked.
8. `shellcheck` the scripts (render `.tmpl` ones first: `chezmoi execute-template < f | shellcheck -s sh -`).
9. Render test, before every commit: `chezmoi apply -S <repo> -D $(mktemp -d) --exclude=scripts`.
10. Commit (gitleaks hook runs) and push to `main`. Auto-commit/auto-push stay off.

## Rules
- **No secrets in the repo.** Reference 1Password with `op://vault/item/field` (read at apply time via `onepasswordRead` / `op read`). API keys for MCP live in the macOS Keychain. Never paste tokens, keys, or full app plists.
- **Apps that rewrite their own config** (OpenCode `cli.json`, Claude `settings.json`, KiCad, cmux, etc.): use `modify_` scripts that patch only the keys we own; do not commit whole files.
- **Preferences via `defaults`**: write only the specific keys you intend (see the Vorssaint script), in `run_onchange_` scripts. Never copy a `.plist`.
- **Brewfile / macOS defaults** are applied by `run_onchange_` scripts under `home/.chezmoiscripts/` so they re-run only when their content changes. Add apps to the Brewfile instead of installing by hand; manually installed apps get "brewified" later.
- Deliberately excluded: Mole (Vorssaint replaces it), Alfred (uninstalled), MacTap, 1Password Installer.
- Don't delete or migrate anything from the old repo without Calum choosing it.
- Keep scripts idempotent and loud on failure (non-zero exit with a clear message).
