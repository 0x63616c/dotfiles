#!/usr/bin/env bash
# Patch KiCad's "input" navigation settings into its live config. Can't symlink
# kicad_common.json outright -- KiCad rewrites the whole file on every exit, so a
# symlink just gets replaced with a plain file the next time KiCad quits, and it
# would also drag every other unrelated setting (window layout, recent files, ...)
# into this repo. This patches only the keys in input-settings.json instead, in
# place, leaving everything else -- including changes made in-app since -- alone.
set -euo pipefail

if [ "$(uname)" = "Darwin" ]; then
  CONFIG_ROOT="$HOME/Library/Preferences/kicad"
else
  CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/kicad"
fi

# Settings live under a per-version folder (e.g. 10.0), so a KiCad upgrade means a
# fresh folder with defaults; always patch the newest one that actually exists.
VERSION_DIR="$(find "$CONFIG_ROOT" -maxdepth 1 -type d -name '[0-9]*.[0-9]*' 2>/dev/null | sort -V | tail -1)"
if [ -z "$VERSION_DIR" ]; then
  echo "no KiCad config found under $CONFIG_ROOT -- open KiCad once first" >&2
  exit 1
fi

CONFIG_FILE="$VERSION_DIR/kicad_common.json"

if pgrep -x kicad >/dev/null 2>&1; then
  echo "KiCad is running -- quit it first, or it'll overwrite this file on exit" >&2
  exit 1
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp)"
jq --slurpfile patch "$SRC/input-settings.json" '.input += $patch[0]' "$CONFIG_FILE" > "$TMP"
mv "$TMP" "$CONFIG_FILE"
echo "patched $CONFIG_FILE"
