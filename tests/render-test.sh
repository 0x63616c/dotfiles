#!/bin/sh
# Render test (AGENTS.md step 8): the whole source state renders, templates produce valid files, scripts parse.
# Usage: tests/render-test.sh   (run from anywhere)
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
dest="$(mktemp -d)"
coding_dest="$(mktemp -d)"
coding_config="$(mktemp)"
trap 'rm -rf "$dest" "$coding_dest" "$coding_config"' EXIT

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

python3 - "$dest" <<'PY'
import pathlib, plistlib, sys
dest = pathlib.Path(sys.argv[1])
agent = dest / "Library/LaunchAgents/dev.0x63616c.worktree-cleanup.plist"
p = plistlib.loads(agent.read_bytes())
assert p["Label"] == "dev.0x63616c.worktree-cleanup"
assert p["StartCalendarInterval"] == {"Minute": 0}
assert p["RunAtLoad"] is True
assert p["ProgramArguments"][-1] == "--apply"
assert (dest / ".local/bin/worktree-cleanup").stat().st_mode & 0o111
PY

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
# Coding renders through a real persisted profile, with personal scripts still
# included in the source. Its allow-list must keep a plain apply shell-only.
chezmoi init -S "$repo" -D "$coding_dest" -c "$coding_config" --config-format toml --no-tty --promptDefaults \
  --promptString 'Shell profile=coding' >/dev/null
mkdir -p "$coding_dest/.claude"
printf '%s\n' '{"theme":"dark","hooks":{"SessionStart":[]},"env":{"KEEP":"yes"}}' \
  > "$coding_dest/.claude/settings.json"
chezmoi apply -S "$repo" -D "$coding_dest" -c "$coding_config" --config-format toml --exclude=scripts >/dev/null
python3 - "$coding_dest" "$coding_config" <<'PYTEST'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
assert 'profile = "coding"' in pathlib.Path(sys.argv[2]).read_text()
assert "[hooks." not in pathlib.Path(sys.argv[2]).read_text()
assert 'coding.zsh' in (root / ".zshrc").read_text()
assert "shellenv" not in (root / ".zprofile").read_text()
assert "ssh_only = false" in (root / ".config/starship.toml").read_text()
assert 'require("keys")' in (root / ".config/rex/init.lua").read_text()
assert 'rex.host' not in (root / ".config/rex/init.lua").read_text()
settings = json.loads((root / ".claude/settings.json").read_text())
assert settings == {"theme": "dark", "hooks": {"SessionStart": []},
                    "env": {"KEEP": "yes", "DISABLE_AUTOUPDATER": "1"}}
allowed = {".zshrc", ".zprofile", ".config/starship.toml", ".claude/settings.json", ".claude/CLAUDE.md", ".config/rex/init.lua", ".config/rex/keys.lua"}
for file in root.rglob("*"):
    if file.is_file():
        path = file.relative_to(root).as_posix()
        assert path in allowed or path.startswith(".config/zsh/"), path
PYTEST
# Verify scripts are ignored as well as absent from the file render above.
chezmoi managed -S "$repo" -D "$coding_dest" -c "$coding_config" --config-format toml \
  > "$coding_dest/managed.txt"
if grep -q 'chezmoiscripts' "$coding_dest/managed.txt"; then
  echo "FAIL: coding includes personal scripts" >&2; exit 1
fi
for file in "$dest/.zshrc" "$dest/.zprofile" "$dest"/.config/zsh/*.zsh \
  "$coding_dest/.zshrc" "$coding_dest/.zprofile"; do zsh -n "$file"; done
HOME="$dest" REX_BIN_DIR="/tmp/Rex Bin" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; test "$(alias code)" = "code=cursor"; eval reload; test "${PATH%%:*}" = "$REX_BIN_DIR"'
HOME="$coding_dest" REX_BIN_DIR="/tmp/Rex Bin" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; eval reload; test "${PATH%%:*}" = "$REX_BIN_DIR"'
echo "render test OK ($domains domains; personal and coding profiles)"
