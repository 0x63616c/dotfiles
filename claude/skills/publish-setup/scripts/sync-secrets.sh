#!/usr/bin/env bash
set -euo pipefail

# Sync signing config from 1Password (source of truth) into a repo's GitHub
# Actions secrets + variables (the copy CI reads). Re-run after rotating a token.
#
# Usage: sync-secrets.sh <owner/repo> <bundle_id> [team_id] [ios_project] [initial_build_number]
#   ios_project defaults to ios/App/App.xcodeproj (Capacitor layout).

REPO="${1:?usage: sync-secrets.sh <owner/repo> <bundle_id> [team_id] [ios_project] [initial_build_number]}"
BUNDLE_ID="${2:?bundle id required}"
TEAM_ID="${3:-}"
IOS_PROJECT="${4:-ios/App/App.xcodeproj}"
INITIAL_BUILD_NUMBER="${5:-0}"
VAULT="Homelab"
export ASC_VAULT="$VAULT"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/asc-key.sh"

command -v gh >/dev/null || { echo "FATAL: gh not found" >&2; exit 1; }
gh repo view "$REPO" >/dev/null 2>&1 || { echo "FATAL: cannot see repo $REPO" >&2; exit 1; }

set_secret() { gh secret   set "$1" --repo "$REPO" --body "$2" >/dev/null && echo "  secret $1"; }
set_var()    { gh variable set "$1" --repo "$REPO" --body "$2" >/dev/null && echo "  var    $1"; }

echo "==> ASC key: op://$VAULT/$(asc_resolve)"
echo "==> syncing secrets to $REPO"
# ASC API key (account-level). Key content base64-encoded (single-line safe).
set_secret ASC_KEY_ID      "$(asc_key_id)"
set_secret ASC_ISSUER_ID   "$(asc_issuer_id)"
set_secret ASC_KEY_CONTENT "$(asc_p8_base64)"
# fastlane match (shared distribution cert in the certificates repo).
set_secret MATCH_PASSWORD                 "$(match_password)"
set_secret MATCH_GIT_URL                  "$(match_git_url)"
set_secret MATCH_GIT_BASIC_AUTHORIZATION  "$(match_git_auth)"

echo "==> syncing variables to $REPO"
set_var BUNDLE_ID            "$BUNDLE_ID"
[ -n "$TEAM_ID" ] && set_var APPLE_TEAM_ID "$TEAM_ID"
set_var IOS_PROJECT          "$IOS_PROJECT"
set_var IOS_SCHEME           "App"
set_var INITIAL_BUILD_NUMBER "$INITIAL_BUILD_NUMBER"

echo "==> done. Push a tag (vX.Y.Z) to trigger a release."
