#!/bin/sh
# Coding-only (selected by .chezmoiignore): Rex owns its generated skill/hook;
# chezmoi owns only this invocation and the separate Claude env settings merge.
# Run on every apply to repair drift without copying generated skills into Git.
set -eu
command -v rex >/dev/null 2>&1 || { echo 'Rex must be installed through the homelab Nix configuration.' >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo 'Claude must be installed through the homelab Nix configuration.' >&2; exit 1; }
exec rex skill setup --agent claude --autostart=false
