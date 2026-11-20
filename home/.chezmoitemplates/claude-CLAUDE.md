# Global agent notes (both Claude profiles; source: 0x63616c/dotfiles home/.chezmoitemplates/claude-CLAUDE.md)

## 1Password CLI cache

`op` in Claude Code is a shim (`~/.local/bin/op`) that caches `op read`, `op item get/list` and `op vault get/list`
output for 30 minutes, so Calum is not asked to approve every read. Any write (`op item create/edit/delete`, ...)
through the shim wipes the cache automatically.

If a result looks stale or wrong (Calum just changed something in the 1Password app, an item you expect is missing
from a list, a value does not work), bypass the cache instead of retrying: `OP_CACHE=refresh op ...` (fetches fresh
and updates the cache), or `op cache clear` to drop everything. Never print cached secrets you do not need.

## Stopping processes

Stop only processes you started, and only by PID: the one you recorded at start, your own background task, or
`lsof -ti :<your port>`. Never match by name: no `pkill`, `killall` or `pgrep ... | xargs kill`. Other agents and
Calum's apps run under the same user on this Mac, and a name pattern reaches them too.

On macOS an option placed after the pattern becomes another pattern: `pkill -f vite -U 501` also matched every
command line containing `-U`, such as `--lang=en-US`, and killed the windows of several running Electron apps.

## Spelling

Write US English everywhere: chat, code, comments, commit messages, docs (`color`, `behavior`, `organize`, `center`).
