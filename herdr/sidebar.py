#!/usr/bin/env python3
"""A small, live quota readout for a Herdr split pane."""

import argparse
import datetime as dt
import json
import os
import select
import subprocess
import sys
import termios
import time
import tty


PLUGIN_ID = "calum.plan-usage"
PANE_TITLE = "Plan usage"
WIDTH = 30


def herdr(*args):
    # The lab wrapper is used only by isolated integration checks.
    lab = os.environ.get("FM_HERDR_LAB_SESSION")
    if lab:
        command = [os.environ["FM_HERDR_LAB_HELPER"], "run", lab, *args]
    else:
        command = [os.environ.get("HERDR_BIN_PATH", "herdr"), *args]
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def open_pane():
    snapshot = herdr("api", "snapshot")["result"]["snapshot"]
    target = snapshot.get("focused_pane_id")
    if not target:
        return  # No workspace exists yet; a later action can open it.
    tab_id = next(p["tab_id"] for p in snapshot["panes"] if p["pane_id"] == target)
    panes = herdr("pane", "list")["result"]["panes"]
    existing = next((p for p in panes if p.get("label") == PANE_TITLE and p["tab_id"] == tab_id), None)
    if existing:
        herdr("pane", "send-keys", existing["pane_id"], "r")
        return

    opened = herdr(
        "plugin", "pane", "open", "--plugin", PLUGIN_ID,
        "--entrypoint", "usage", "--placement", "split",
        "--target-pane", target, "--direction", "right", "--no-focus",
    )
    pane_id = opened["result"]["plugin_pane"]["pane"]["pane_id"]
    herdr("pane", "swap", "--source-pane", pane_id, "--target-pane", target)
    layout = herdr("pane", "layout", "--pane", pane_id)["result"]["layout"]
    width = next(p["rect"]["width"] for p in layout["panes"] if p["pane_id"] == pane_id)
    if width > WIDTH:
        herdr("pane", "resize", "--pane", pane_id, "--direction", "left",
              "--amount", str((width - WIDTH) / layout["area"]["width"]))
    herdr("pane", "focus", "--pane", pane_id, "--direction", "right")


def reset_text(value):
    if not value:
        return "reset unknown"
    try:
        when = dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone()
        return f"resets {when:%b} {when.day} {when:%H:%M}"
    except ValueError:
        return "reset unknown"


def render(data):
    providers = {p.get("provider"): p for p in data.get("providers", [])}
    lines = ["PLAN USAGE", "─" * 24]
    for key, title in (("claude", "CLAUDE"), ("codex", "CODEX")):
        p = providers.get(key)
        lines.extend(["", title + (f" · {p['plan']}" if p and p.get("plan") else "")])
        if not p:
            lines.append("  Unavailable")
            continue
        status = p.get("state", {}).get("status", "unknown")
        if status == "auth_required":
            lines.extend(["  Auth required", "  run: quota-axi", "    --allow-keychain-prompt"])
            continue
        windows = p.get("windows") or []
        if status != "fresh":
            lines.append(f"  {status.replace('_', ' ').title()} data")
        if not windows:
            lines.append("  No quota windows" if status == "fresh" else "  Quota unavailable")
        for window in windows:
            label = str(window.get("label") or window.get("id") or "quota")[:10]
            remaining = window.get("percentRemaining")
            amount = f"{remaining:g}% left" if isinstance(remaining, (int, float)) else "unknown"
            lines.extend([f"  {label}: {amount}", f"  {reset_text(window.get('resetsAt'))}"])
    lines.extend(["", f"Updated {dt.datetime.now():%H:%M} · r refresh"])
    return "\n".join(lines)


def fetch():
    try:
        result = subprocess.run(
            ["quota-axi", "--provider", "claude,codex", "--json"],
            capture_output=True, text=True, check=True, timeout=15,
        )
        return render(json.loads(result.stdout))
    except (OSError, subprocess.SubprocessError, ValueError):
        return "PLAN USAGE\n\nquota-axi unavailable\nCheck installation or login"


def self_test():
    output = render({"providers": [
        {"provider": "claude", "windows": [], "state": {"status": "auth_required"}},
        {"provider": "codex", "windows": [
            {"label": "day", "percentRemaining": 42, "resetsAt": "2026-09-26T14:43:59Z"},
            {"label": "week", "percentRemaining": 90, "resetsAt": None},
        ], "state": {"status": "stale"}},
    ]})
    assert "Auth required" in output
    assert "Stale data" in output and "day: 42% left" in output
    assert "week: 90% left" in output and "reset unknown" in output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--open", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.open:
        open_pane()
    elif args.once:
        print(fetch())
    elif args.check:
        self_test()
    else:
        old_tty = termios.tcgetattr(sys.stdin)
        try:
            tty.setcbreak(sys.stdin)
            while True:
                sys.stdout.write("\033[H\033[2J" + fetch() + "\n")
                sys.stdout.flush()
                readable, _, _ = select.select([sys.stdin], [], [], 45)
                if readable:
                    sys.stdin.read(1)
        finally:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)


if __name__ == "__main__":
    main()
