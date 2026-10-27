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
6. Applies macOS app settings (Vorssaint), and enables the repo's gitleaks pre-commit hook.

Every step is safe to re-run.

## Layout

```
.
├── .chezmoiroot                 # "home": chezmoi only reads ./home
├── AGENTS.md  CLAUDE.md         # agent instructions (CLAUDE.md just imports AGENTS.md)
├── README.md
├── .githooks/pre-commit         # gitleaks scan on staged changes
└── home/                        # the chezmoi source state
    ├── .chezmoi.toml.tmpl       # per-machine config (name, email, hostname, secrets)
    ├── .chezmoiscripts/
    │   ├── run_before_00-ensure-homebrew.sh
    │   ├── run_onchange_before_10-brew-bundle.sh.tmpl
    │   ├── run_once_after_05-git-hooks.sh.tmpl
    │   └── run_onchange_after_20-vorssaint-defaults.sh.tmpl
    ├── dot_config/brewfile/Brewfile
    ├── dot_zprofile
    └── dot_zshrc
```

## Day to day

```sh
chezmoi update   # pull the latest from GitHub and apply it
chezmoi apply    # apply the local source (after editing it)
chezmoi diff     # preview what apply would change
```

Edit the source (`chezmoi cd`), never the deployed files in `$HOME`.

## Secrets

No secrets are stored in this repo. Anything sensitive is read from 1Password at apply time. Sign in to 1Password (app, then `op` CLI integration) on the Mac, set `secrets = true` (re-run `chezmoi init` and answer yes), then run `chezmoi apply` again.

## Agents

This repo is operated by an AI agent. Read [AGENTS.md](AGENTS.md) for the rules and the verify loop before changing anything.
