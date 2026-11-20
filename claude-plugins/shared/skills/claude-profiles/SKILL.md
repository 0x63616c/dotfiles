---
name: claude-profiles
description: Where Calum's Claude Code config lives across his two profiles (personal, vov) and how to change it. Use before changing any Claude Code config, in this profile or the other one: settings, plugins, mods, skills, hooks, MCP servers, the status line, or the global CLAUDE.md.
---

# Claude profiles

Two profiles, one login each:

| Profile | Config dir | Login | Runs when |
|---|---|---|---|
| personal | `~/.claude-personal` | personal account | everywhere else (`.zshrc` exports it as the default) |
| vov | `~/.claude-vov` | work account | `claude` started in `~/coding/vov` or `~/coding/vov-worktrees` (the zsh `claude()` function) |

The session-start line names this session's profile, or says there is none: `CLAUDE_CONFIG_DIR` unset or `~/.claude` reads personal's files through the `~/.claude` link but uses the default login and `~/.claude.json`, so config changed there doesn't match a real profile. Either profile's config can be changed from either session: everything lives in the dotfiles repo, `~/.local/share/chezmoi` (a link to `~/coding/dotfiles`, public on GitHub). Edit the repo, then follow its `AGENTS.md` loop.

## 1. Pick the layer

Every change belongs to exactly one layer: **shared** (both profiles), **personal**, or **vov**. Take it from the request; when the request leaves it open, ask Calum which layer before editing. Name the layer you changed in your report.

## 2. Edit the layer's home

| Change | Shared | One profile |
|---|---|---|
| Skill, hook, slash command, agent, MCP server | `claude-plugins/shared/` | `claude-plugins/personal/` or `claude-plugins/vov/` |
| Mod, or any self-contained plugin | its own folder `claude-plugins/<name>/`, listed in `claude-plugins/.claude-plugin/marketplace.json`, its `<name>@dotfiles` in `PLUGINS["shared"]` | same, in `PLUGINS["personal"]` or `PLUGINS["vov"]` |
| Plugin from another marketplace | add `name@marketplace` to `PLUGINS["shared"]` | `PLUGINS["<profile>"]` |
| Plain setting we own (retention, status line command) | `SHARED` | `PROFILE_KEYS["<profile>"]` |
| Status line output | `home/dot_local/bin/executable_claude-statusline` (one script; branch on the profile inside it) | same |
| Global agent notes (`CLAUDE.md`) | `home/.chezmoitemplates/claude-CLAUDE.md` | |

`PLUGINS`, `SHARED` and `PROFILE_KEYS` are in `home/.chezmoitemplates/claude-settings.py`, the `modify_` script both profiles' `settings.json` render from. It owns only those keys; Claude owns the rest of each `settings.json` (model, theme, permissions, hooks other tools add such as Rex's), which stays per profile and changes through `/config` or by editing that profile's file directly.

Plugin layout: skills in `skills/<name>/SKILL.md`, command hooks in `hooks/hooks.json` (paths via `${CLAUDE_PLUGIN_ROOT}`), MCP servers in `.mcp.json` at the plugin root. The repo is public: an MCP key comes from the environment (`${VAR}` in `.mcp.json`) or the Keychain, never the file.

## 3. Make it live

- Edited files inside an existing `claude-plugins/` plugin: live at the next session start, or now with `/reload-plugins` (the marketplace is read in place).
- Changed `claude-settings.py`, the status line script, `CLAUDE.md`, or added a plugin: `chezmoi apply`, then a new session in each affected profile (missing plugins install themselves at startup).
- Done when `CLAUDE_CONFIG_DIR=~/.claude-<profile> claude plugin list` shows the expected plugins enabled in each affected profile, and `chezmoi verify --exclude=scripts` passes.

## Targeting the other profile

`claude` subcommands act on `$CLAUDE_CONFIG_DIR`, so prefix the other profile's dir: `CLAUDE_CONFIG_DIR=~/.claude-vov claude plugin list`. A first argument that isn't a subcommand starts a session with it as the prompt (`claude config get x` is a prompt, not a lookup); read a setting with `jq` on that profile's `settings.json`.
