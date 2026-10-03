#!/usr/bin/python3
"""Remember cmux sidebar colours by full directory path, without a daemon."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile


CMUX = "/Applications/cmux.app/Contents/Resources/bin/cmux"
STATE = Path.home() / ".local/state/cmux/directory-colors.json"


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


def path_for(row):
    # Deliberately no basename/realpath matching: two clones called dotfiles
    # are separate preferences. Match the same directory the sidebar displays.
    return row.get("current_directory") or ""


def apply(event, colors, rows, send):
    """Update a directory preference and converge its live native colours.

    Null is a remembered default, not an absent preference. Keep it so stale
    session-restored workspace overrides cannot resurrect a reset colour.
    """
    name = event.get("name")
    if name == "workspace.action":
        payload = event.get("payload", {})
        result = payload.get("result", {})
        params = payload.get("params", {})
        action = result.get("action") or params.get("action")
        if action not in ("set_color", "clear_color"):
            return False
        target_id = event.get("workspace_id") or result.get("workspace_id")
        target = next((r for r in rows if r["id"] == target_id), None)
        if not target or not path_for(target):
            return False
        color = result.get("color") if action == "set_color" else None
        # An older action can finish its handler after a newer click. The live
        # originating row must still agree with this event before accepting it.
        if target.get("custom_color") != color:
            return False
        colors[path_for(target)] = color
    elif name not in (None, "workspace.created", "workspace.selected", "config.reloaded"):
        return False

    for row in rows:
        directory = path_for(row)
        if directory not in colors or row.get("custom_color") == colors[directory]:
            continue
        color = colors[directory]
        params = {"workspace_id": row["id"], "action": "clear_color" if color is None else "set_color"}
        if color is not None:
            params["color"] = color
        send("workspace.action", **params)
    return True


def save(colors, path):
    # Replace atomically; a crash must not truncate the saved preferences.
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as file:
            json.dump(colors, file, indent=2, sort_keys=True)
            file.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    raw = os.environ.get("CMUX_AUTOMATION_EVENT_JSON") or os.environ.get("CMUX_AUTOMATION_EVENT")
    event = json.loads(raw) if raw else {}
    # Ignore unrelated workspace actions before taking a lock or querying cmux.
    if event.get("name") == "workspace.action":
        payload = event.get("payload", {})
        action = payload.get("result", {}).get("action") or payload.get("params", {}).get("action")
        if action not in ("set_color", "clear_color"):
            return
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with STATE.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        colors = json.loads(STATE.read_text()) if STATE.exists() else {}
        previous = colors.copy()
        apply(event, colors, workspaces(), rpc)
        if colors != previous:
            save(colors, STATE)


if __name__ == "__main__":
    main()
