# AGENTS.md: Calum's Mac setup (chezmoi)

Private repo `0x63616c/dotfiles`. It manages Calum's MacBook Pro (Apple Silicon, zsh) with chezmoi. Agents operate it; Calum does not maintain it by hand. `CLAUDE.md` is a symlink to this file. The previous repo is `0x63616c/dotfiles-old`: read-only reference; port pieces only when Calum chooses.

## Layout (chezmoi source = `~/.local/share/chezmoi`)
| Source path | Deploys to / does |
|---|---|
| `dot_zshrc`, `dot_zprofile` | `~/.zshrc`, `~/.zprofile` (zsh, no Oh My Zsh; every integration guarded) |
| `dot_config/brewfile/Brewfile` | `~/.config/brewfile/Brewfile`: the core Brewfile (formulae, casks, mas) |
| `run_onchange_after_10-brew-bundle.sh.tmpl` | runs `brew bundle` when the Brewfile hash changes |
| `run_onchange_after_20-vorssaint-defaults.sh.tmpl` | writes selected Vorssaint keys (`com.vorssaint.utils`) via `defaults write` |
| `run_once_after_05-git-hooks.sh.tmpl` | sets `core.hooksPath=.githooks` on the source repo |
| `.githooks/pre-commit` | gitleaks secret scan on staged changes |
| `.chezmoiignore` | keeps AGENTS.md / CLAUDE.md / README.md out of `$HOME` |

Bootstrap on a new Mac: install Homebrew (needs sudo), `brew install chezmoi`, then `chezmoi init --apply 0x63616c`.

## The loop (follow strictly, in order)
1. Edit the **source** (`chezmoi cd` or `~/.local/share/chezmoi`). Never edit deployed files in `$HOME` directly. If an app changed its own file, use `chezmoi re-add`/`chezmoi merge` deliberately.
2. `chezmoi diff`: read it.
3. `chezmoi apply --dry-run -v`: confirm the plan.
4. `chezmoi apply -v`.
5. Verify: open a fresh `zsh -i -c 'echo ok'`, run `defaults read`/`brew bundle check --file ~/.config/brewfile/Brewfile`, etc. Report what you checked.
6. Commit (gitleaks hook runs) and push to `main`.

## Rules
- **No secrets in the repo.** Reference 1Password with `op://vault/item/field` (read at apply time via `onepasswordRead` / `op read`). API keys for MCP live in the macOS Keychain. Never paste tokens, keys, or full app plists.
- **Apps that rewrite their own config** (OpenCode `cli.json`, Claude `settings.json`, KiCad, cmux, etc.): use `modify_` scripts that patch only the keys we own; do not commit whole files.
- **Preferences via `defaults`**: write only the specific keys you intend (see the Vorssaint script), in `run_onchange_` scripts. Never copy a `.plist`.
- **Brewfile / macOS defaults** live in `run_onchange_` scripts so they re-run only when their content changes. Add apps to the Brewfile instead of installing by hand; manually installed apps get "brewified" later.
- Deliberately excluded: Mole (Vorssaint replaces it), Alfred (uninstalled), MacTap, 1Password Installer.
- Don't delete or migrate anything from the old repo without Calum choosing it.
- Keep scripts idempotent and loud on failure (non-zero exit with a clear message).
