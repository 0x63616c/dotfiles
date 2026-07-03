#!/usr/bin/env bash
# Install the dotfiles auto-push LaunchAgent: every 5 min (and once at load/login),
# auto-commit any local changes in THIS repo and push to its upstream branch. Survives
# reboot — the LaunchAgent lives in ~/Library/LaunchAgents and reloads at each login.
# Idempotent — re-run any time. Mirrors git/install.sh's launchd pattern.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/auto-push.sh"

# The repo to keep pushed = the repo this installer lives in.
REPO="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

# Resolve git's dir at install time so launchd's minimal PATH can find it (+ ssh in /usr/bin).
need() { command -v "$1" >/dev/null 2>&1 || { echo "  MISSING: $1 (install it first)"; exit 1; }; }
need git
GIT_DIR_BIN="$(dirname "$(command -v git)")"
RUN_PATH="${GIT_DIR_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"

# Bake the GUI ssh-agent socket in if macOS exposes one, so an ssh remote can auth from
# launchd. (Keychain-stored key passphrases work without it; this just helps agent setups.)
SSH_SOCK="$(launchctl getenv SSH_AUTH_SOCK 2>/dev/null || true)"
if [ -n "$SSH_SOCK" ]; then
  SSH_ENV="    <key>SSH_AUTH_SOCK</key>
    <string>${SSH_SOCK}</string>
"
else
  SSH_ENV=""
fi

LA_DIR="$HOME/Library/LaunchAgents"
PLIST="$LA_DIR/com.calum.dotfiles-autopush.plist"
mkdir -p "$LA_DIR" "$HOME/.local/state/autopush"

# Render the plist (use a temp file for __SSH_ENV__ since it spans multiple lines).
python3 - "$SCRIPT_DIR/launchd/com.calum.dotfiles-autopush.plist.template" "$PLIST" \
  "$SCRIPT_DIR/auto-push.sh" "$REPO" "$HOME" "$RUN_PATH" "$SSH_ENV" <<'PY'
import sys
tpl, out, script, repo, home, path, ssh_env = sys.argv[1:8]
s = open(tpl).read()
for k, v in {"__SCRIPT__": script, "__REPO__": repo, "__HOME__": home,
             "__PATH__": path, "__SSH_ENV__": ssh_env}.items():
    s = s.replace(k, v)
open(out, "w").write(s)
PY

launchctl bootout "gui/$(id -u)/com.calum.dotfiles-autopush" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
  && echo "  loaded LaunchAgent com.calum.dotfiles-autopush (every 300s, RunAtLoad)" \
  || echo "  (could not bootstrap; load manually: launchctl bootstrap gui/$(id -u) $PLIST)"

echo "Done. Auto-pushing $REPO every 5 min (and at each login)."
echo "Logs: ~/.local/state/autopush/{log,err}."
echo "Uninstall: launchctl bootout gui/$(id -u)/com.calum.dotfiles-autopush && rm $PLIST"
