#!/usr/bin/env python3
"""Link reusable OpenCode config; keep credentials/runtime state outside the repo."""

import argparse
import json
import os
from pathlib import Path


def link(source, destination):
    if destination.is_symlink() and destination.resolve() == source.resolve():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        backup = destination.with_name(destination.name + ".before-dotfiles")
        number = 1
        while backup.exists() or backup.is_symlink():
            backup = destination.with_name(destination.name + ".before-dotfiles." + str(number))
            number += 1
        destination.rename(backup)
        print("Backed up", destination, "to", backup)
    destination.symlink_to(source, target_is_directory=source.is_dir())
    print("Linked", destination, "->", source)


def capture_cli(repo, config):
    source = config / "cli.json"
    target = repo / "opencode/cli.json"
    if source.resolve() == target.resolve():
        return
    data = json.loads(source.read_text())
    # Keep local plugin paths portable without touching any other preferences.
    replacements = {
        str(repo / "themes"): "./theme-pack",
        str(config / "plugins/statusline.tsx"): "./plugins/statusline.tsx",
    }
    for index, plugin in enumerate(data.get("plugins", [])):
        if isinstance(plugin, str):
            data["plugins"][index] = replacements.get(plugin, plugin)
        elif isinstance(plugin, dict) and "package" in plugin:
            plugin["package"] = replacements.get(plugin["package"], plugin["package"])
    target.write_text(json.dumps(data, indent=2) + "\n")
    print("Captured", source, "in", target)


def install(repo, config, capture=False):
    if capture:
        capture_cli(repo, config)
    for relative, source in (
        ("opencode.json", "opencode/opencode.json"),
        ("cli.json", "opencode/cli.json"),
        ("plugins/statusline.tsx", "opencode/plugins/statusline.tsx"),
        ("plugins/subscription-usage", "opencode/plugins/subscription-usage"),
        ("themes", "themes/opencode"),
        ("theme-pack", "themes"),
    ):
        link(repo / source, config / relative)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-cli", action="store_true",
                        help="save a detached live cli.json before restoring its symlink")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    config = Path(os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")) / "opencode"
    install(repo, config, args.capture_cli)
