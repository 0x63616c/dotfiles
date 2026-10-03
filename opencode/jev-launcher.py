#!/usr/bin/env python3
"""Launch Jev over stdio using an environment key or macOS Keychain, never argv."""

import os
import shutil
import subprocess
import sys

SERVICE = "opencode-jev-openrouter"
ACCOUNT = "openrouter"


def load_key(environment):
    key = environment.get("OPENROUTER_API_KEY", "").strip()
    if key:
        return key
    if sys.platform != "darwin":
        return ""
    result = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", SERVICE,
         "-a", ACCOUNT, "-w"],
        capture_output=True, text=True, timeout=15,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def main():
    environment = os.environ.copy()
    try:
        key = load_key(environment)
    except (OSError, subprocess.TimeoutExpired):
        print("Jev: Keychain unavailable; unlock it and reconnect the MCP.", file=sys.stderr)
        return 1
    if sys.argv[1:] == ["--check"]:
        print("OpenRouter key available." if key else "OpenRouter key not configured.")
        return 0 if key else 1
    if sys.argv[1:]:
        print("Usage: jev-launcher.py [--check]", file=sys.stderr)
        return 2
    executable = shutil.which("jev-mcp")
    if not executable:
        print("Jev: install @jkudish/jev-mcp@0.13.0 with npm first.", file=sys.stderr)
        return 1
    environment["JEV_PROVIDER"] = "openrouter"
    environment["JEV_MCP_MODEL"] = "typesafe/jev-1.13"
    environment["OPENROUTER_API_KEY"] = key
    if not key:
        print("Jev: tools available, but live calls await the OpenRouter Keychain key.",
              file=sys.stderr)
    os.execvpe(executable, [executable], environment)


if __name__ == "__main__":
    sys.exit(main())
