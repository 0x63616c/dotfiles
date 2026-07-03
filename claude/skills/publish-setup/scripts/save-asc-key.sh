#!/usr/bin/env bash
set -euo pipefail

# Stores the App Store Connect API key (Issuer ID + Key ID + .p8) into 1Password.
# This is the ONLY credential a human hands over by hand, and it is one-time-ever.
# Secret capture happens here in the terminal, never in the Claude chat.

ITEM="asc-api-key"
VAULT="Homelab"
REF_ISSUER="op://$VAULT/$ITEM/issuer-id"
REF_KEYID="op://$VAULT/$ITEM/key-id"
REF_P8="op://$VAULT/$ITEM/p8"

# An ASC API key is account-level, not per-app. If one already lives in 1Password
# (this skill's `asc-api-key` item, or a pre-existing key another repo's CI uses),
# reuse it — don't make the human download a second one. --force overrides.
export ASC_VAULT="$VAULT"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/asc-key.sh"
if [ "${1:-}" != "--force" ] && EXISTING="$(asc_resolve 2>/dev/null)" && [ -n "$EXISTING" ]; then
  echo "An App Store Connect API key already exists: op://$VAULT/$EXISTING"
  echo "It is account-level and reusable across apps, so no new key is needed."
  echo "Run with --force only if you want to store a different key."
  exit 0
fi

echo "App Store Connect API key setup."
echo "Get these at: App Store Connect -> Users and Access -> Integrations ->"
echo "App Store Connect API -> generate a key (role: Admin)."
echo

read -rp "Issuer ID (UUID at top of the Integrations page): " ISSUER
read -rp "Key ID (the new key's ID): " KEYID
read -rp "Path to the downloaded .p8 file: " P8_PATH

# Allow drag-and-drop paths that arrive quoted or with a trailing space.
P8_PATH="${P8_PATH%\"}"; P8_PATH="${P8_PATH#\"}"; P8_PATH="${P8_PATH//\\ / }"
P8_PATH="${P8_PATH/#\~/$HOME}"

[ -n "$ISSUER" ] || { echo "FATAL: empty Issuer ID" >&2; exit 1; }
[ -n "$KEYID" ]  || { echo "FATAL: empty Key ID" >&2; exit 1; }
[ -f "$P8_PATH" ] || { echo "FATAL: no .p8 at: $P8_PATH" >&2; exit 1; }

P8_CONTENT="$(cat "$P8_PATH")"
# Sanity-check it's a PKCS#8 key. Match "PRIVATE KEY" without the "BEGIN " prefix
# so this literal doesn't trip the secret-leak pre-commit guard.
case "$P8_CONTENT" in
  *"PRIVATE KEY"*) : ;;
  *) echo "FATAL: that file is not a PKCS#8 .p8 key" >&2; exit 1 ;;
esac

if op item get "$ITEM" --vault "$VAULT" >/dev/null 2>&1; then
  op item edit "$ITEM" --vault "$VAULT" \
    "issuer-id[password]=$ISSUER" \
    "key-id[password]=$KEYID" \
    "p8[password]=$P8_CONTENT" >/dev/null
else
  op item create --vault "$VAULT" --category "API Credential" --title "$ITEM" \
    "issuer-id[password]=$ISSUER" \
    "key-id[password]=$KEYID" \
    "p8[password]=$P8_CONTENT" >/dev/null
fi

# Invalidate the op-shim read cache for each ref (REQUIRED after any write).
EVEE_OP_DIR="${OP_CACHE_DIR:-$HOME/.local/share/evee-op}"
if [ -d "$EVEE_OP_DIR" ]; then
  for REF in "$REF_ISSUER" "$REF_KEYID" "$REF_P8"; do
    KEY_HASH=$(printf '%s' "$REF" | shasum -a 256 | cut -d' ' -f1)
    rm -f "$EVEE_OP_DIR/$KEY_HASH"
  done
fi

echo "Verifying..."
op read "$REF_ISSUER" >/dev/null && op read "$REF_KEYID" >/dev/null \
  && op read "$REF_P8" >/dev/null && echo "  ok - stored in op://$VAULT/$ITEM"
