#!/usr/bin/env bash
# Link the theme into Cursor and/or VS Code, wherever they're installed.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"  # <repo>/cursor
NAME="blackout-theme"
installed=0
for dir in "$HOME/.cursor/extensions" "$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions"; do
  [ -d "$dir" ] || continue
  DEST="$dir/$NAME"
  rm -rf "$DEST"
  if ln -s "$SRC" "$DEST" 2>/dev/null; then
    echo "Linked -> $DEST"
  else
    cp -R "$SRC" "$DEST"
    echo "Copied -> $DEST (symlink unavailable)"
  fi
  installed=1
done
if [ "$installed" = 0 ]; then
  echo "No Cursor or VS Code extensions folder found." >&2
  exit 1
fi
echo "Reload the window, then pick 'Blackout' in the theme picker (Cmd+K Cmd+T)."
