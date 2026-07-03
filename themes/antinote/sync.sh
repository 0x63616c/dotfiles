#!/usr/bin/env bash
# Copy antinote themes into the sandboxed Antinote container.
# Sandbox blocks symlinks out of the container, so we copy real files.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/Library/Containers/com.chabomakers.Antinote/Data/Documents/Themes"

mkdir -p "$DEST"
for f in "$SRC"/*.json; do
  [ "$(basename "$f")" = "example.json" ] && continue
  cp "$f" "$DEST/"
  echo "synced $(basename "$f")"
done
