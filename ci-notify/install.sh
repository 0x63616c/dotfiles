#!/usr/bin/env bash
# Install the ci-notify LaunchAgent: poll GitHub Actions for the watched repo and
# post a macOS notification when the newest completed run on the branch changes.
# Idempotent — re-run any time. Mirrors git/install.sh's launchd pattern.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/ci-notify.sh"

# Resolve tool dirs at install time so PATH is correct on this machine
# (terminal-notifier lives in a version-pinned gem dir that moves on ruby upgrades).
need() { command -v "$1" >/dev/null 2>&1 || { echo "  MISSING: $1 (install it first)"; exit 1; }; }
need gh; need jq; need terminal-notifier
PATH_DIRS="$(for b in gh jq terminal-notifier; do dirname "$(command -v "$b")"; done | sort -u | tr '\n' ':')"
RUN_PATH="${PATH_DIRS}/usr/bin:/bin:/usr/sbin:/sbin"

# Register the stub CI.app so notifications post under their OWN identity ("CI"),
# giving them a separate Notification Center stack from terminal-notifier commits.
APP_SRC="$SCRIPT_DIR/CI.app"
APP_DST="$HOME/Applications/CI.app"
chmod +x "$APP_SRC/Contents/MacOS/ci"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"; cp -R "$APP_SRC" "$APP_DST"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$APP_DST" && echo "  registered CI.app (sender com.calum.ci-notify)"

LA_DIR="$HOME/Library/LaunchAgents"
PLIST="$LA_DIR/com.calum.ci-notify.plist"
mkdir -p "$LA_DIR" "$HOME/.local/state/ci-notify"

sed -e "s#__SCRIPT__#$SCRIPT_DIR/ci-notify.sh#g" \
    -e "s#__HOME__#$HOME#g" \
    -e "s#__PATH__#$RUN_PATH#g" \
    "$SCRIPT_DIR/launchd/com.calum.ci-notify.plist.template" > "$PLIST"

launchctl bootout "gui/$(id -u)/com.calum.ci-notify" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
  && echo "  loaded LaunchAgent com.calum.ci-notify (every 60s)" \
  || echo "  (could not bootstrap; load manually: launchctl bootstrap gui/$(id -u) $PLIST)"

echo "Done. Watching ${CI_NOTIFY_REPO:-0x63616c/control-center} @ ${CI_NOTIFY_BRANCH:-main}."
echo "First run seeds the cursor silently; subsequent completed runs notify."
echo "Logs: ~/.local/state/ci-notify/{log,err}.  Uninstall: launchctl bootout gui/$(id -u)/com.calum.ci-notify"
