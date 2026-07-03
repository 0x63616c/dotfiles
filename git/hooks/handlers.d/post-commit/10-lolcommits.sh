#!/usr/bin/env bash
# post-commit handler: commit selfie (lolcommits). Grab a webcam frame stamped
# with commit metadata. Backgrounded with fds detached so the ~2s webcam warmup
# never blocks the commit; `|| true` so a capture failure is never a hook error.
# Because it returns immediately, the dispatcher logs it as ~0ms — the honest
# *blocking* cost of this handler.
( "$HOME/.config/lolcommits/capture.sh" </dev/null >/dev/null 2>&1 || true ) &
exit 0
