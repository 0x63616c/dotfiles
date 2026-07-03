#!/usr/bin/env bash
set -euo pipefail

# Provision an app for the shared-match signing flow: drop fastlane config into
# the repo and mint a provisioning profile for the bundle id into the central
# certificates repo, reusing the ONE shared distribution cert. No new cert is
# minted. Idempotent. Run from the app repo root.
#
# Usage: setup-app.sh ios <bundle_id> <app_name>
#
# (The macOS notarize path is not yet reworked for this flow — iOS/TestFlight only.)

PLATFORM="${1:?platform required: ios}"
BUNDLE_ID="${2:?bundle id required, e.g. co.worldwidewebb.myapp}"
APP_NAME="${3:?app name required}"
VAULT="Homelab"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$PLATFORM" = "ios" ] || { echo "FATAL: this flow supports 'ios' only (match/TestFlight)." >&2; exit 1; }

# --- ASC key + match secrets from 1Password -> env for fastlane -------------
export ASC_VAULT="$VAULT"
source "$SKILL_DIR/scripts/lib/asc-key.sh"
echo "==> ASC key:    op://$VAULT/$(asc_resolve)"

export ASC_ISSUER_ID="$(asc_issuer_id)"
export ASC_KEY_ID="$(asc_key_id)"
export ASC_KEY_CONTENT="$(asc_p8_base64)"
export MATCH_PASSWORD="$(match_password)"
export MATCH_GIT_URL="$(match_git_url)"
if ! MGA="$(match_git_auth)"; then
  echo "FATAL: match git auth missing in 1Password. Run save-match-git-auth.sh first." >&2; exit 1
fi
export MATCH_GIT_BASIC_AUTHORIZATION="$MGA"
echo "==> match repo: $MATCH_GIT_URL"

[ -n "$ASC_ISSUER_ID" ] && [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_KEY_CONTENT" ] \
  || { echo "FATAL: ASC key incomplete in 1Password. Run save-asc-key.sh first." >&2; exit 1; }
[ -n "$MATCH_PASSWORD" ] || { echo "FATAL: match password missing in 1Password." >&2; exit 1; }

# Apple ID (non-secret) → used as the internal TestFlight tester, and as
# FASTLANE_USER for app-record creation when a session is also present.
if AID="$(apple_id)" && [ -n "$AID" ]; then
  export TESTFLIGHT_TESTER="$AID"
fi
# Optional Apple ID session → lets setup_ios create the App Store Connect app
# record headlessly (Apple's API can't). Absent/expired → the lane warns instead.
if [ -n "${AID:-}" ] && FS="$(fastlane_session)" && [ -n "$FS" ]; then
  export FASTLANE_USER="$AID" FASTLANE_SESSION="$FS"
  echo "==> Apple ID session present (will create the app record if missing)"
else
  echo "==> No Apple ID session in 1Password — app record must already exist, or"
  echo "    run save-apple-session.sh to automate its creation."
fi

# --- Drop fastlane config into the repo if missing --------------------------
mkdir -p fastlane
[ -f fastlane/Fastfile ]  || cp "$SKILL_DIR/templates/Fastfile" fastlane/Fastfile
[ -f fastlane/Matchfile ] || cp "$SKILL_DIR/templates/Matchfile" fastlane/Matchfile
[ -f Gemfile ]            || cp "$SKILL_DIR/templates/Gemfile" Gemfile
command -v bundle >/dev/null || { echo "FATAL: bundler not found (gem install bundler)" >&2; exit 1; }
bundle install --quiet

# --- Register the app + mint its profile (reuses the shared cert) -----------
export BUNDLE_ID APP_NAME
echo "==> fastlane ios setup_ios ($BUNDLE_ID)"
bundle exec fastlane ios setup_ios

# Internal TestFlight group + self-invite, so every build appears with no clicks.
echo "==> fastlane ios setup_testflight ($BUNDLE_ID)"
bundle exec fastlane ios setup_testflight

echo "==> done. Profile minted (cert reused) + internal TestFlight ready for $BUNDLE_ID."
echo "    Next: sync-secrets.sh <owner/repo> $BUNDLE_ID <team_id>"
