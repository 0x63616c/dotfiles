#!/usr/bin/env python3
# chezmoi modify_ script for ~/.claude-{{ .profile }}/settings.json, rendered from home/.chezmoitemplates/claude-settings.py.
# Claude Code rewrites settings.json itself (/config, /model, "always allow", other tools' hooks), so this owns only the
# keys below and passes every other key through untouched. See README: Claude accounts.
import json
import os
import sys

PROFILE = "{{ .profile }}"
HOME = "{{ .home }}"
# Resolved: ~/.local/share/chezmoi is a link, and Claude stores the resolved path when it adds the marketplace.
PLUGIN_DIR = os.path.realpath("{{ .repo }}/claude-plugins")
MARKETPLACE = "dotfiles"  # claude-plugins/ in this repo, read in place (edits need no reinstall)

# Plugins on in every profile, then per profile. "<plugin>@dotfiles" lives in claude-plugins/; the rest are installed
# from their own marketplace. A dotfiles plugin missing from a profile's list is switched off there.
PLUGINS = {
    "shared": [
        "shared@dotfiles",
        "simple-view@dotfiles",
        "mattpocock-skills@claude-plugins-official",
        "rust-analyzer-lsp@claude-plugins-official",
        "swift-lsp@claude-plugins-official",
    ],
    "personal": ["personal@dotfiles"],
    "vov": ["vov@dotfiles"],
}

# Plain keys, same in every profile.
SHARED = {
    "cleanupPeriodDays": 3650,  # keep session transcripts 10 years (default 30 days)
    "statusLine": {"type": "command", "command": HOME + "/.local/bin/claude-statusline", "refreshInterval": 30},
}
# Per-profile plain keys, layered over SHARED.
PROFILE_KEYS = {"personal": {}, "vov": {}}

MARKETPLACES = {
    MARKETPLACE: {"source": {"source": "directory", "path": PLUGIN_DIR}},
}


def patch(data):
    data.update(SHARED)
    data.update(PROFILE_KEYS[PROFILE])
    data["extraKnownMarketplaces"] = {**(data.get("extraKnownMarketplaces") or {}), **MARKETPLACES}
    wanted = PLUGINS["shared"] + PLUGINS[PROFILE]
    plugins = {k: v for k, v in (data.get("enabledPlugins") or {}).items() if not k.endswith("@" + MARKETPLACE)}
    data["enabledPlugins"] = {**plugins, **dict.fromkeys(wanted, True)}
    return data


src = sys.stdin.read()
try:
    data = json.loads(src) if src.strip() else {}
except json.JSONDecodeError as e:
    sys.exit(f"claude-settings ({PROFILE}): settings.json is not valid JSON ({e}); fix it before chezmoi apply")
if not isinstance(data, dict):
    sys.exit(f"claude-settings ({PROFILE}): settings.json is not a JSON object")

before = json.dumps(data, sort_keys=True)
patched = patch(data)
if json.dumps(patched, sort_keys=True) == before:
    sys.stdout.write(src)  # already correct: leave the file byte-for-byte as Claude wrote it
else:
    sys.stdout.write(json.dumps(patched, indent=2, ensure_ascii=False) + "\n")
