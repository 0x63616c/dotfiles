#!/usr/bin/python3
"""Save directory colour requests before reconciling cmux's workspace colours."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile


CMUX = "/Applications/cmux.app/Contents/Resources/bin/cmux"
CONFIG = Path.home() / ".config/cmux/directory-colors.json"
LOCK = Path.home() / ".local/state/cmux/directory-colors.lock"


def rpc(method, **params):
    result = subprocess.run(
        [CMUX, "rpc", method, json.dumps(params)],
        check=True, capture_output=True, text=True, timeout=10,
    )
    return json.loads(result.stdout)


def workspaces():
    rows = []
    for window in rpc("window.list")["windows"]:
        rows.extend(rpc("workspace.list", window_id=window["id"])["workspaces"])
    return rows


def path_key(directory, home=None):
    """Keep full-path identity, but make paths under HOME portable across users."""
    if not directory or not os.path.isabs(directory):
        return None
    directory = os.path.normpath(directory)
    home = os.path.normpath(str(home or Path.home()))
    if directory == home:
        return "~"
    if directory.startswith(home + "/"):
        return "~" + directory[len(home):]
    return directory


def read_config(path):
    colors = json.loads(path.read_text())
    if not isinstance(colors, dict):
        raise ValueError("directory-colors.json must be a path-to-colour object")
    for directory, color in colors.items():
        if not (directory == "~" or directory.startswith(("~/", "/"))):
            raise ValueError("Colour paths must start with ~/ or /: " + directory)
        if not isinstance(color, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
            raise ValueError("Colours must be #RRGGBB: " + directory)
    return {directory: color.upper() for directory, color in colors.items()}


def set_override(colors, rows, workspace_id, color):
    target = next((r for r in rows if r["id"].lower() == workspace_id.lower()), None)
    if not target:
        raise ValueError("Workspace no longer exists: " + workspace_id)
    key = path_key(target.get("current_directory"))
    if key is None:
        raise ValueError("Workspace has no absolute directory")
    if color == "default":
        colors.pop(key, None)
    else:
        color = "#" + color.lstrip("#")
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
            raise ValueError("Colour must be RRGGBB or default")
        colors[key] = color.upper()
    return key


def reconcile(colors, rows, send):
    # The directory config is authoritative. Missing entries mean the hashed
    # default, so reset also clears stale native session-restored overrides.
    # Never infer a saved preference from a native workspace colour: in-process
    # sidebar clicks don't emit workspace.action, and old restore handlers can
    # otherwise undo a new choice before it is recorded.
    for row in rows:
        key = path_key(row.get("current_directory"))
        if key is None:
            continue
        color = colors.get(key)
        current = row.get("custom_color")
        if (current.upper() if current else None) == color:
            continue
        params = {"workspace_id": row["id"], "action": "clear_color" if color is None else "set_color"}
        if color is not None:
            params["color"] = color
        send("workspace.action", **params)


def save(colors, path):
    # Resolve BEFORE replacing: atomic writes through a symlink must update the
    # tracked target, not replace ~/.config/cmux/directory-colors.json itself.
    path = path.resolve(strict=True)
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as file:
            os.fchmod(file.fileno(), mode)
            json.dump(colors, file, indent=2, sort_keys=True)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", help="Workspace UUID whose directory to change")
    parser.add_argument("--color", help="RRGGBB or default")
    args = parser.parse_args(argv)
    if bool(args.workspace) != bool(args.color):
        parser.error("--workspace and --color must be supplied together")
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with LOCK.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        colors = read_config(CONFIG)
        rows = workspaces()
        if args.workspace:
            previous = colors.copy()
            set_override(colors, rows, args.workspace, args.color)
            if colors != previous:
                save(colors, CONFIG)
        # Persist first. Even a failed RPC cannot lose a click, and another
        # lifecycle handler can only reapply the new saved preference.
        reconcile(colors, rows, rpc)


if __name__ == "__main__":
    main()
