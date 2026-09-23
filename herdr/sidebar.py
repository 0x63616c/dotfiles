#!/usr/bin/env python3
"""A small, live quota readout for a Herdr split pane."""

import argparse
import datetime as dt
import json
import os
import re
import select
import subprocess
import sys
import termios
import time
import tty


PLUGIN_ID = "calum.plan-usage"
PANE_TITLE = "Plan usage"
WIDTH = 30
RESET = "\033[0m"


def styled(code, value):
    return f"\033[{code}m{value}{RESET}"


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
    lines = []
    for key, title in (("claude", "CLAUDE"), ("codex", "CODEX")):
        p = providers.get(key)
        if lines:
            lines.append("")
        lines.append(styled("1;97", f" {title}") + (styled("2", f" · {p['plan']}") if p and p.get("plan") else ""))
        if not p:
            lines.append(styled("33", "  Unavailable"))
            continue
        status = p.get("state", {}).get("status", "unknown")
        if status == "auth_required":
            lines.extend([styled("33", "  Auth required"), styled("2", "  run: quota-axi"),
                          styled("2", "    --allow-keychain-prompt")])
            continue
        windows = p.get("windows") or []
        if status != "fresh":
            lines.append(styled("33", f"  {status.replace('_', ' ').title()} data"))
        if not windows:
            lines.append(styled("33", "  No quota windows" if status == "fresh" else "  Quota unavailable"))
        for window in windows:
            label = str(window.get("label") or window.get("id") or "quota")[:10]
            remaining = window.get("percentRemaining")
            amount = f"{remaining:g}% left" if isinstance(remaining, (int, float)) else "unknown"
            # Above 50% is comfortable; 20-50% cautions; below 20% warns.
            color = "33"
            if isinstance(remaining, (int, float)):
                color = "32" if remaining > 50 else "33" if remaining >= 20 else "31"
            elapsed = window.get("pace", {}).get("elapsedPercent")
            through = f" / {elapsed:.0f}% through" if isinstance(elapsed, (int, float)) else ""
            lines.extend([styled("2", f"  {label}: ") + styled(color, amount) + styled("2", through),
                          styled("2", f"  {reset_text(window.get('resetsAt'))}")])
    lines.extend(["", styled("2", f"Updated {dt.datetime.now():%H:%M} · r refresh")])
    return "\n".join(lines)


def fetch():
    try:
        result = subprocess.run(
            ["quota-axi", "--provider", "claude,codex", "--json", "--full"],
            capture_output=True, text=True, check=True, timeout=15,
        )
        return render(json.loads(result.stdout))
    except (OSError, subprocess.SubprocessError, ValueError):
        return styled("33", "quota-axi unavailable") + "\n" + styled("2", "Check installation or login")


def self_test():
    output = render({"providers": [
        {"provider": "claude", "windows": [], "state": {"status": "auth_required"}},
        {"provider": "codex", "windows": [
            {"label": "day", "percentRemaining": 42, "resetsAt": "2026-09-26T14:43:59Z",
             "pace": {"elapsedPercent": 60.4}},
            {"label": "week", "percentRemaining": 90, "resetsAt": None},
            {"label": "low", "percentRemaining": 10, "resetsAt": None},
        ], "state": {"status": "stale"}},
    ]})
    plain = re.sub(r"\033\[[0-9;]*m", "", output)
    assert plain.startswith(" CLAUDE\n") and "PLAN USAGE" not in plain
    assert "Auth required" in plain and "Stale data" in plain
    assert "day: 42% left / 60% through" in plain  # elapsedPercent rounds to nearest whole percent
    assert "week: 90% left" in plain and "week: 90% left / " not in plain
    assert "reset unknown" in plain
    assert "\033[33m42% left\033[0m" in output
    assert "60% through" in output
    assert "\033[32m90% left\033[0m" in output
    assert "\033[31m10% left\033[0m" in output


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
