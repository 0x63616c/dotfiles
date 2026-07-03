#!/usr/bin/env bash
set -euo pipefail

# OPTIONAL override. By default match_git_auth (lib/asc-key.sh) already derives
# MATCH_GIT_BASIC_AUTHORIZATION = base64("username:token") from the GitHub PAT
# already in 1Password — so you normally do NOT need this script. Run it only to
# pin a dedicated/different token for cloning the private certificates repo.
# It stores the value on the same item that holds the ASC key + match password.
# Secret capture happens here in the terminal, never in the Claude chat.

VAULT="Homelab"
export ASC_VAULT="$VAULT"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/asc-key.sh"

ITEM="$(asc_resolve)" || { echo "FATAL: no ASC item to attach match auth to (run save-asc-key.sh first)" >&2; exit 1; }
DEFAULT_URL="https://github.com/0x63616c/certificates.git"

echo "fastlane match git authorization setup."
echo "This is for read access to the private certificates repo that match uses."
echo "Use a GitHub Personal Access Token with 'repo' scope (classic) or read access"
echo "to the certificates repo (fine-grained)."
echo

read -rp "certificates repo git URL [$DEFAULT_URL]: " GIT_URL
GIT_URL="${GIT_URL:-$DEFAULT_URL}"
read -rp "GitHub username: " GH_USER
read -rsp "GitHub token (hidden): " GH_TOKEN; echo

[ -n "$GH_USER" ]  || { echo "FATAL: empty username" >&2; exit 1; }
[ -n "$GH_TOKEN" ] || { echo "FATAL: empty token" >&2; exit 1; }

# MATCH_GIT_BASIC_AUTHORIZATION = base64 of "username:token" (no trailing newline).
AUTH_B64="$(printf '%s:%s' "$GH_USER" "$GH_TOKEN" | base64 | tr -d '\n')"

op item edit "$ITEM" --vault "$VAULT" \
  "match-git-url[text]=$GIT_URL" \
  "match-git-auth[password]=$AUTH_B64" >/dev/null

# Invalidate the op-shim read cache for the new refs (REQUIRED after a write).
EVEE_OP_DIR="${OP_CACHE_DIR:-$HOME/.local/share/evee-op}"
if [ -d "$EVEE_OP_DIR" ]; then
  for REF in "op://$VAULT/$ITEM/match-git-url" "op://$VAULT/$ITEM/match-git-auth"; do
    KEY_HASH=$(printf '%s' "$REF" | shasum -a 256 | cut -d' ' -f1)
    rm -f "$EVEE_OP_DIR/$KEY_HASH"
  done
fi

echo "Verifying..."
match_git_url >/dev/null && match_git_auth >/dev/null \
  && echo "  ok - stored on op://$VAULT/$ITEM (match-git-url, match-git-auth)"
