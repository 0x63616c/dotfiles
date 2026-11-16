#!/bin/sh
# Render test (AGENTS.md step 8): the whole source state renders, templates produce valid files, scripts parse.
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
agent = dest / "Library/LaunchAgents/dev.0x63616c.claude-warmup.plist"
p = plistlib.loads(agent.read_bytes())
assert p["Label"] == "dev.0x63616c.claude-warmup"
assert p["StartCalendarInterval"] == {"Minute": 0}
assert p["RunAtLoad"] is False
assert p["ProgramArguments"][-1].endswith("/.local/bin/claude-warmup")
assert (dest / ".local/bin/claude-warmup").stat().st_mode & 0o111
PY
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$dest/.local/bin/claude-warmup"; fi
sh -n "$dest/.local/bin/claude-warmup"

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
for file in "$dest/.zshrc" "$dest/.zprofile"; do zsh -n "$file"; done
[ ! -e "$dest/.config/zsh" ] || { echo "FAIL: shell config must live in .zshrc only" >&2; exit 1; }
HOME="$dest" REX_BIN_DIR="/tmp/Rex Bin" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; test "$(alias code)" = "code=cursor"; eval reload; test "${PATH%%:*}" = "$REX_BIN_DIR"'

# Claude accounts: the work profile shares config with the default one by symlink, and claude (and c) picks the work
# profile inside ~/coding/vov and its worktrees only.
for name in settings.json keybindings.json skills plugins; do
  [ "$(readlink "$dest/.claude-work/$name")" = "../.claude/$name" ] || { echo "FAIL: .claude-work/$name is not a symlink to the default profile" >&2; exit 1; }
done
[ -d "$dest/.claude/plugins" ] && [ -d "$dest/.claude/skills" ] || { echo "FAIL: shared Claude directories not created" >&2; exit 1; }
mkdir -p "$dest/stub" "$dest/coding/vov/sub" "$dest/coding/vov-worktrees/feat" "$dest/coding/vovish"
printf '#!/bin/sh\necho "${CLAUDE_CONFIG_DIR:-default}"\n' >"$dest/stub/claude"
chmod +x "$dest/stub/claude"
HOME="$dest" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; path=("$HOME/stub" $path); work="$HOME/.claude-work"
  cd "$HOME/coding/vov" && test "$(claude)" = "$work" && test "$(eval c)" = "$work" || exit 1
  cd "$HOME/coding/vov/sub" && test "$(claude)" = "$work" || exit 1
  cd "$HOME/coding/vov-worktrees/feat" && test "$(claude)" = "$work" || exit 1
  cd "$HOME/coding/vovish" && test "$(claude)" = default && test "$(eval c)" = default || exit 1
  cd "$HOME" && test "$(claude)" = default' || { echo "FAIL: claude profile routing" >&2; exit 1; }
echo "render test OK ($domains domains)"
