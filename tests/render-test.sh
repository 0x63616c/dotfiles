#!/bin/sh
# Render test (AGENTS.md step 9): the whole source state renders, templates produce valid files, scripts parse.
# Usage: tests/render-test.sh   (run from anywhere)
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT

chezmoi apply -S "$repo" -D "$dest" --exclude=scripts >/dev/null
agent="$dest/Library/LaunchAgents/dev.0x63616c.prefsync.plist"
[ -f "$agent" ] || { echo "FAIL: LaunchAgent not rendered" >&2; exit 1; }
[ -x "$dest/.local/bin/prefsync" ] || { echo "FAIL: prefsync not deployed executable" >&2; exit 1; }
[ ! -e "$dest/prefs" ] || { echo "FAIL: prefs/ must not be deployed" >&2; exit 1; }
[ -f "$dest/.config/starship.toml" ] || { echo "FAIL: starship.toml not deployed" >&2; exit 1; }

# One WatchPaths entry per manifest domain, StartInterval safety net present.
domains="$(grep -c '^\[\[domain\]\]' "$repo/home/prefs/manifest.toml")"
watch="$(python3 - "$agent" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["Label"] == "dev.0x63616c.prefsync", p["Label"]
assert p["StartInterval"] == 3600 and p["ThrottleInterval"] == 5
print(len(p["WatchPaths"]))
PY
)"
[ "$watch" = "$domains" ] || { echo "FAIL: $watch WatchPaths vs $domains manifest domains" >&2; exit 1; }
if command -v plutil >/dev/null 2>&1; then plutil -lint "$agent" >/dev/null; fi

# Scripts render and parse; shellcheck if available.
for t in "$repo"/home/.chezmoiscripts/*.tmpl; do
  out="$(mktemp)"
  chezmoi execute-template -S "$repo" < "$t" > "$out"
  sh -n "$out" || { echo "FAIL: $t renders to invalid sh" >&2; exit 1; }
  if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$out"; fi
  rm -f "$out"
done
for t in "$repo"/home/.chezmoiscripts/*.sh; do
  sh -n "$t"
  if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$t"; fi
done
echo "render test OK ($domains domains)"
