#!/usr/bin/env bash
# pre-session lifecycle hook — runs ONCE before every `claude`/`c`/`cc` launch,
# before the actual Claude session starts. Symlinked to ~/.claude/hooks/pre-session.sh.
#
# Receives the same args the launch was invoked with ("$@").
# Runs best-effort: its exit code does NOT block the session from starting.
# Put whatever you want to happen before any session here.

# Example — make sure a local service is up before every session:
#   curl -sf http://localhost:8080/health >/dev/null 2>&1 || \
#     (cd ~/tools/ccflare && bun run start >/tmp/ccflare.log 2>&1 &)

:
