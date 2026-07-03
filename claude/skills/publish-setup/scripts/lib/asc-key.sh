#!/usr/bin/env bash
# Resolve the App Store Connect API key from 1Password, tolerating how it was
# stored. The skill's own save-asc-key.sh writes item `asc-api-key` with text
# fields issuer-id/key-id/p8, but a pre-existing key (e.g. one already used by
# another repo's CI) may live under a different title, have space-labelled
# fields ("issuer id"), and carry the `.p8` as a FILE ATTACHMENT rather than a
# text field. This resolver papers over all of that so one ASC key — which is
# account-level, not per-app — is reused everywhere instead of re-downloaded.
#
# Source this, then call: asc_resolve / asc_key_id / asc_issuer_id / asc_p8.
# Override discovery with ASC_OP_ITEM=<item name or id>. Vault: ASC_VAULT.

ASC_VAULT="${ASC_VAULT:-Homelab}"
_ASC_ITEM=""
# Resolve this lib's dir to an absolute path ONCE at source time. Must work when
# sourced from zsh too (Claude Code's Bash tool runs zsh): BASH_SOURCE is empty
# there, which used to resolve _ASC_LIB_DIR to the *cwd* and silently break
# autodiscovery ("no App Store Connect API key" with a perfectly good item).
if [ -n "${BASH_VERSION:-}" ]; then
  _ASC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _ASC_LIB_DIR="$(cd "$(dirname "$(eval 'printf %s "${(%):-%x}"')")" && pwd)"
else
  _ASC_LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Print the resolved item (id or title). Resolution order:
#   1. $ASC_OP_ITEM explicit override
#   2. conventional items: `asc-api-key` (what save-asc-key.sh writes) or
#      `App Store Connect API` (the pre-existing key in the Homelab vault)
#   3. autodiscover: an API Credential item in the vault carrying a *.p8
#      (preferring titles that look like an ASC key).
asc_resolve() {
  [ -n "$_ASC_ITEM" ] && { printf '%s' "$_ASC_ITEM"; return 0; }
  local item="" title
  if [ -n "${ASC_OP_ITEM:-}" ]; then
    item="$ASC_OP_ITEM"
  else
    for title in "asc-api-key" "App Store Connect API"; do
      if op item get "$title" --vault "$ASC_VAULT" >/dev/null 2>&1; then
        item="$title"; break
      fi
    done
  fi
  if [ -z "$item" ]; then
    item="$(op item list --vault "$ASC_VAULT" --categories "API Credential" --format json 2>/dev/null \
      | ASC_VAULT="$ASC_VAULT" python3 "$_ASC_LIB_DIR/asc-pick.py" 2>/dev/null)"
  fi
  [ -n "$item" ] || { echo "FATAL: no App Store Connect API key in op://$ASC_VAULT (run save-asc-key.sh)" >&2; return 1; }
  _ASC_ITEM="$item"
  printf '%s' "$item"
}

# Read the first non-empty field among the given label variants.
_asc_field() {
  local item label v
  item="$(asc_resolve)" || return 1
  for label in "$@"; do
    v="$(op read "op://$ASC_VAULT/$item/$label" 2>/dev/null)" || true
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  echo "FATAL: none of [$*] readable on op://$ASC_VAULT/$item" >&2; return 1
}

asc_key_id()    { _asc_field "key-id" "key id" "key_id" "Key ID"; }
asc_issuer_id() { _asc_field "issuer-id" "issuer id" "issuer_id" "Issuer ID"; }

# Print the raw .p8 (PKCS#8 text). Prefers a `p8` text field; falls back to a
# *.p8 file attachment on the item.
asc_p8() {
  local item v fname
  item="$(asc_resolve)" || return 1
  v="$(op read "op://$ASC_VAULT/$item/p8" 2>/dev/null)" || true
  # "PRIVATE KEY" (no "BEGIN " prefix) so the literal doesn't trip the leak guard.
  case "$v" in *"PRIVATE KEY"*) printf '%s' "$v"; return 0 ;; esac
  fname="$(op item get "$item" --vault "$ASC_VAULT" --format json 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); f=[x["name"] for x in d.get("files",[]) if x.get("name","").endswith(".p8")]; print(f[0] if f else "")')"
  [ -n "$fname" ] || { echo "FATAL: no .p8 (text field or attachment) on op://$ASC_VAULT/$item" >&2; return 1; }
  op read "op://$ASC_VAULT/$item/$fname" 2>/dev/null
}

# Convenience: the .p8 base64-encoded (single line, env/secret safe).
asc_p8_base64() { asc_p8 | base64; }

# --- fastlane match secrets (shared signing via the certificates repo) -------
# These live on the SAME resolved item as the ASC key: `match password` is
# usually already present; the certificates-repo git auth + url are written by
# save-match-git-auth.sh. git_url falls back to the conventional repo.
MATCH_GIT_URL_DEFAULT="${MATCH_GIT_URL_DEFAULT:-https://github.com/0x63616c/certificates.git}"

match_password() { _asc_field "match-password" "match password" "MATCH_PASSWORD"; }

# Apple ID + Spaceship session for headless App Store Connect app creation (the
# one thing the API key can't do). Stored by save-apple-session.sh; the session
# expires every ~2-4 weeks. Both return non-zero/empty when absent — callers
# treat that as "no session, warn and skip app creation".
apple_id()         { _asc_field "apple-id" "apple id" "APPLE_ID" 2>/dev/null; }
fastlane_session() { _asc_field "fastlane-session" "fastlane session" "FASTLANE_SESSION" 2>/dev/null; }

# MATCH_GIT_BASIC_AUTHORIZATION = base64("user:token") for cloning the certs repo.
# Prefer an explicitly-stored value; otherwise derive it from the GitHub PAT
# already in 1Password (item GITHUB_PAT_ITEM, default "GitHub Personal Access
# Token", field GITHUB_PAT_FIELD/"token"), so nothing extra needs saving.
GITHUB_PAT_ITEM="${GITHUB_PAT_ITEM:-GitHub Personal Access Token}"
GITHUB_PAT_FIELD="${GITHUB_PAT_FIELD:-token}"
GITHUB_USER="${GITHUB_USER:-0x63616c}"
match_git_auth() {
  local item v tok
  item="$(asc_resolve)" || return 1
  for label in "match-git-auth" "match git auth" "match-git-basic-authorization"; do
    v="$(op read "op://$ASC_VAULT/$item/$label" 2>/dev/null)" || true
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  tok="$(op read "op://$ASC_VAULT/$GITHUB_PAT_ITEM/$GITHUB_PAT_FIELD" 2>/dev/null)" || true
  [ -n "$tok" ] || { echo "FATAL: no match git auth and no GitHub PAT in op://$ASC_VAULT/$GITHUB_PAT_ITEM" >&2; return 1; }
  printf '%s:%s' "$GITHUB_USER" "$tok" | base64 | tr -d '\n'
}
match_git_url() {
  local item v label
  item="$(asc_resolve)" || return 1
  for label in "match-git-url" "match git url" "MATCH_GIT_URL"; do
    v="$(op read "op://$ASC_VAULT/$item/$label" 2>/dev/null)" || true
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  printf '%s' "$MATCH_GIT_URL_DEFAULT"
}
