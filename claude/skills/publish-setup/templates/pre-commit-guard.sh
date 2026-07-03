#!/usr/bin/env bash
# Blocking pre-commit guard: refuses to commit Apple signing material.
# Installed by publish-setup into .git/hooks/pre-commit (or appended to it).
set -euo pipefail

staged="$(git diff --cached --name-only --diff-filter=ACM)"
[ -n "$staged" ] || exit 0

fail() { echo "BLOCKED: $1" >&2; echo "Signing material must live in 1Password, never in git." >&2; exit 1; }

# 1. Forbidden file types by name.
echo "$staged" | grep -Eiq '\.(p8|p12|mobileprovision|cer|certSigningRequest|keychain-db)$' \
  && fail "staged a signing file ($(echo "$staged" | grep -Ei '\.(p8|p12|mobileprovision|cer)$' | head -1))"

# 2. Forbidden content in staged text.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in *.lock|*.svg|*.png|*.jpg|*.pdf) continue ;; esac
  if git show ":$f" 2>/dev/null | grep -Eq 'BEGIN (RSA |EC )?PRIVATE KEY'; then
    fail "private key block in $f"
  fi
done <<< "$staged"

exit 0
