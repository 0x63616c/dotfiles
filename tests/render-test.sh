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

# op shim (1Password read cache for Claude Code) deploys executable and parses.
[ -x "$dest/.local/bin/op" ] || { echo "FAIL: ~/.local/bin/op not executable" >&2; exit 1; }
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$dest/.local/bin/op"; fi
sh -n "$dest/.local/bin/op"

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
HOME="$dest" REX_BIN_DIR="/tmp/Rex Bin" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; eval reload; test "${PATH%%:*}" = "$REX_BIN_DIR"'
grep -q -- "cursor --classic" "$dest/.local/bin/code" && [ -x "$dest/.local/bin/code" ] || { echo "FAIL: ~/.local/bin/code must run cursor --classic" >&2; exit 1; }

# Claude profiles: ~/.claude-personal and ~/.claude-vov side by side, ~/.claude a link to personal; each profile has
# its own settings.json (a modify_ script owning a few keys), plugins and skills; claude (and c) picks vov inside
# ~/coding/vov and its worktrees only, and the zshrc export defaults everything else to personal.
[ "$(readlink "$dest/.claude")" = .claude-personal ] || { echo "FAIL: ~/.claude is not a link to .claude-personal" >&2; exit 1; }
[ "$(readlink "$dest/.claude-vov/keybindings.json")" = ../.claude-personal/keybindings.json ] || { echo "FAIL: vov keybindings not linked to personal" >&2; exit 1; }
for p in personal vov; do
  for d in plugins skills; do [ -d "$dest/.claude-$p/$d" ] && [ ! -L "$dest/.claude-$p/$d" ] || { echo "FAIL: .claude-$p/$d is not its own directory" >&2; exit 1; }; done
  [ -f "$dest/.claude-$p/CLAUDE.md" ] && [ ! -L "$dest/.claude-$p/CLAUDE.md" ] || { echo "FAIL: .claude-$p/CLAUDE.md missing" >&2; exit 1; }
done
cmp -s "$dest/.claude-personal/CLAUDE.md" "$dest/.claude-vov/CLAUDE.md" || { echo "FAIL: profiles' CLAUDE.md differ" >&2; exit 1; }
for p in personal vov; do chezmoi execute-template -S "$repo" < "$repo/home/dot_claude-$p/modify_settings.json.tmpl" > "$dest/modify-$p.py"; done
python3 - "$dest" "$repo" <<'PY' || { echo "FAIL: Claude settings.json layers" >&2; exit 1; }
import json, subprocess, sys
dest, repo = sys.argv[1], sys.argv[2]
run = lambda p, s: subprocess.run([sys.executable, f"{dest}/modify-{p}.py"], input=s, capture_output=True, text=True)
market = json.load(open(f"{repo}/claude-plugins/.claude-plugin/marketplace.json"))
listed = {p["name"] for p in market["plugins"]}
for p, other in [("personal", "vov"), ("vov", "personal")]:
    fresh = json.load(open(f"{dest}/.claude-{p}/settings.json"))  # fresh Mac: built from nothing
    assert fresh["cleanupPeriodDays"] == 3650
    assert fresh["statusLine"]["command"].endswith("/.local/bin/claude-statusline"), fresh["statusLine"]
    assert fresh["extraKnownMarketplaces"]["dotfiles"]["source"]["path"].endswith("/claude-plugins")
    on = fresh["enabledPlugins"]
    assert on[f"{p}@dotfiles"] and on["shared@dotfiles"] and f"{other}@dotfiles" not in on, on
    assert {k.split("@")[0] for k in on if k.endswith("@dotfiles")} <= listed, "enabled plugin not in marketplace.json"
    # Existing file: other keys, other marketplaces and other plugins kept; the other profile's layer switched off.
    old = {"model": "opus", "cleanupPeriodDays": 30, "enabledPlugins": {"x@y": False, f"{other}@dotfiles": True},
           "extraKnownMarketplaces": {"m": {"source": {"source": "github", "repo": "a/b"}}}}
    out = run(p, json.dumps(old, indent=2))
    assert out.returncode == 0, out
    got = json.loads(out.stdout)
    assert got["model"] == "opus" and got["cleanupPeriodDays"] == 3650 and "m" in got["extraKnownMarketplaces"]
    assert got["enabledPlugins"]["x@y"] is False and f"{other}@dotfiles" not in got["enabledPlugins"], got
    assert run(p, out.stdout).stdout == out.stdout  # already patched: byte-for-byte unchanged
    assert run(p, "not json").returncode != 0
PY
# Status line and the session-start profile line name the profile from the config dir, following links.
mkdir -p "$dest/.claude-vov"
sample='{"workspace":{"current_dir":"/"},"model":{"display_name":"M"}}'
for p in personal vov; do
  line="$(printf '%s' "$sample" | HOME="$dest" CLAUDE_CONFIG_DIR="$dest/.claude-$p" sh "$dest/.local/bin/claude-statusline" | head -1)"
  case "$line" in *"[$p]"*) ;; *) echo "FAIL: status line for $p: $line" >&2; exit 1 ;; esac
  out="$(HOME="$dest" CLAUDE_CONFIG_DIR="$dest/.claude-$p" sh "$repo/claude-plugins/shared/hooks/profile.sh")"
  case "$out" in "Claude profile: $p "*) ;; *) echo "FAIL: profile hook for $p: $out" >&2; exit 1 ;; esac
done
# No profile (unset, or ~/.claude even though it links to personal): flagged, never named.
for cfg in "" "$dest/.claude"; do
  line="$(printf '%s' "$sample" | HOME="$dest" CLAUDE_CONFIG_DIR="$cfg" sh "$dest/.local/bin/claude-statusline" | head -1)"
  case "$line" in *"[no profile]"*) ;; *) echo "FAIL: status line without a profile ($cfg): $line" >&2; exit 1 ;; esac
  out="$(HOME="$dest" CLAUDE_CONFIG_DIR="$cfg" sh "$repo/claude-plugins/shared/hooks/profile.sh")"
  case "$out" in "Claude profile: none "*) ;; *) echo "FAIL: profile hook without a profile ($cfg): $out" >&2; exit 1 ;; esac
done
# Run the hook exactly as Claude does: hooks.json's command through /bin/sh, with the plugin root set.
hook="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][0]["command"])' "$repo/claude-plugins/shared/hooks/hooks.json")"
out="$(HOME="$dest" CLAUDE_CONFIG_DIR="$dest/.claude-vov" CLAUDE_PLUGIN_ROOT="$repo/claude-plugins/shared" /bin/sh -c "$hook")"
case "$out" in "Claude profile: vov "*) ;; *) echo "FAIL: SessionStart hook command as Claude runs it: $out" >&2; exit 1 ;; esac
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$dest/.local/bin/claude-statusline" "$repo/claude-plugins/shared/hooks/profile.sh"; fi
for f in "$repo"/claude-plugins/.claude-plugin/marketplace.json "$repo"/claude-plugins/*/.claude-plugin/plugin.json "$repo"/claude-plugins/*/hooks/hooks.json; do
  python3 -m json.tool "$f" >/dev/null || { echo "FAIL: $f is not valid JSON" >&2; exit 1; }
done
mkdir -p "$dest/stub" "$dest/coding/vov/sub" "$dest/coding/vov-worktrees/feat" "$dest/coding/vovish"
printf '#!/bin/sh\necho "${CLAUDE_CONFIG_DIR:-default}"\n' >"$dest/stub/claude"
chmod +x "$dest/stub/claude"
HOME="$dest" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; path=("$HOME/stub" $path); vov="$HOME/.claude-vov"
  cd "$HOME/coding/vov" && test "$(claude)" = "$vov" && test "$(eval c)" = "$vov" || exit 1
  cd "$HOME/coding/vov/sub" && test "$(claude)" = "$vov" || exit 1
  cd "$HOME/coding/vov-worktrees/feat" && test "$(claude)" = "$vov" || exit 1
  cd "$HOME/coding/vovish" && test "$(claude)" = "$HOME/.claude-personal" && test "$(eval c)" = "$HOME/.claude-personal" || exit 1
  cd "$HOME" && test "$(claude)" = "$HOME/.claude-personal"' || { echo "FAIL: claude profile routing" >&2; exit 1; }
env -u CLAUDE_CONFIG_DIR HOME="$dest" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; test "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-personal"' \
  || { echo "FAIL: zshrc does not default CLAUDE_CONFIG_DIR to personal" >&2; exit 1; }
CLAUDE_CONFIG_DIR=/x HOME="$dest" TERM=xterm-256color zsh -fic 'source "$HOME/.zshrc"; test "$CLAUDE_CONFIG_DIR" = /x' \
  || { echo "FAIL: zshrc overrides an already-set CLAUDE_CONFIG_DIR" >&2; exit 1; }
echo "render test OK ($domains domains)"
