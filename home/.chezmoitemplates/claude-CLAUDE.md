# Global agent notes (both Claude profiles; source: 0x63616c/dotfiles home/.chezmoitemplates/claude-CLAUDE.md)

## 1Password CLI cache

`op` in Claude Code is a shim (`~/.local/bin/op`) that caches `op read`, `op item get/list` and `op vault get/list`
output for 30 minutes, so Calum is not asked to approve every read. Any write (`op item create/edit/delete`, ...)
through the shim wipes the cache automatically.

If a result looks stale or wrong (Calum just changed something in the 1Password app, an item you expect is missing
from a list, a value does not work), bypass the cache instead of retrying: `OP_CACHE=refresh op ...` (fetches fresh
and updates the cache), or `op cache clear` to drop everything. Never print cached secrets you do not need.

## Spelling

Write US English everywhere: chat, code, comments, commit messages, docs (`color`, `behavior`, `organize`, `center`).
