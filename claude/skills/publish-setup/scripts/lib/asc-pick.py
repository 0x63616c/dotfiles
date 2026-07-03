#!/usr/bin/env python3
"""Pick the best App Store Connect API-key item from `op item list` JSON on stdin.

Prefers items whose title looks like an ASC key, then verifies (via `op item get`)
that the candidate actually carries a *.p8 attachment or p8 field. Prints the
chosen item id, or nothing if none qualifies."""
import json
import os
import re
import subprocess
import sys

VAULT = os.environ.get("ASC_VAULT", "Homelab")
TITLE_HINT = re.compile(r"asc|app\s*store\s*connect", re.I)


def has_p8(item_id: str) -> bool:
    try:
        out = subprocess.run(
            ["op", "item", "get", item_id, "--vault", VAULT, "--format", "json"],
            capture_output=True, text=True, timeout=20,
        )
        if out.returncode != 0:
            return False
        d = json.loads(out.stdout)
    except Exception:
        return False
    if any(f.get("name", "").endswith(".p8") for f in d.get("files", [])):
        return True
    return any(f.get("id") == "p8" or f.get("label") == "p8" for f in d.get("fields", []))


def main() -> int:
    try:
        items = json.load(sys.stdin)
    except Exception:
        return 0
    # Title-hinted candidates first, then everything else.
    hinted = [i for i in items if TITLE_HINT.search(i.get("title", ""))]
    rest = [i for i in items if i not in hinted]
    for item in hinted + rest:
        if has_p8(item["id"]):
            print(item["id"])
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
