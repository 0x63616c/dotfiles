# Setup and troubleshooting

## What is installed

- Open Computer Use npm package **0.3.6**, stdio server `open-computer-use mcp`.
- Jev MCP npm package **@jkudish/jev-mcp 0.13.0**, Node.js **22+**, 12 text-judgment tools.
- OpenCode **V2** config uses `mcp.servers`, not the V1 examples in Jev's README.
- Global instructions: `opencode/AGENTS.md` → `~/.config/opencode/AGENTS.md`.
- This skill → `~/.config/opencode/skills/computer-control-jev`.
- Launcher → `~/.config/opencode/jev-launcher.py`, respecting `XDG_CONFIG_HOME`.

From the dotfiles checkout:

```sh
npm install -g open-computer-use@0.3.6 @jkudish/jev-mcp@0.13.0
/usr/bin/python3 -B opencode/install.py
sw_vers -productVersion
open-computer-use doctor
swift opencode/setup-jev-key.swift
opencode mcp list
```

Open Computer Use requires macOS 14+ plus Accessibility and Screen Recording.
Only recommend permission fixes on a compatible macOS version. If an app lookup
fails, inspect `list_apps` and use its exact name or bundle ID.

Paste with ⌘V in the masked native prompt; its Edit menu enables standard shortcuts.
It writes to macOS Keychain directly through Security.framework:
service `opencode-jev-openrouter`, account `openrouter`. Cancellation leaves the
entry unchanged; saving updates that entry and trusts `/usr/bin/security` to read
this one item for background use (not all Keychain items). Never enter a key into chat, config,
Git, command arguments or a screenshots-based transfer. The prompt makes no API
request. The launcher captures Keychain output internally and never prints it.
An inherited `OPENROUTER_API_KEY` takes precedence for non-macOS/temporary use.

Jev is forced to provider `openrouter` and model `typesafe/jev-1.13` regardless of
other inherited provider keys. No separate TypeSafe account is needed. Runtime
process environment still contains the key; Keychain avoids plaintext files and
argv, not access by another process already able to inspect this user's processes.
The trusted utility can also be invoked by other local processes running as this
user; this is not per-agent isolation. Do not grant access to every application.

## Verify separately

1. `python3 opencode/jev-launcher.py --check` reports **only** availability, never
   the key. Unlock/approve Keychain access if macOS asks.
   For a key saved before launcher trust was configured, run
   `swift opencode/setup-jev-key.swift --authorize-launcher`: approve the local
   dialog to update only this item's access list without retrieving/repasting the key.
2. Reconnect `jev` via `/mcps` after saving/changing a key. Environment is read on
   process startup; a still-running server cannot see a new Keychain entry.
3. `opencode mcp list` verifies connection/tool discovery, **not** provider billing
   or a successful Jev inference. Without a key the server advertises its tools,
   but live calls fail; say "awaiting key", not "working".
4. Make one small `jev_decide` or `jev_verify` call using synthetic, non-sensitive
   evidence. This spends a small amount of OpenRouter credit. Check the returned
   provider/model and verdict; report errors rather than hiding them. Usage is
   not necessarily a dollar cost. Do not claim a price without reported billing.
5. A fresh `get_app_state` confirms desktop access; an action plus observed result
   confirms control. The shopping-list creation in Notes was the initial live
   desktop test, not proof that Jev was consulted.

## Common failures

- **Missing tools:** check global config/symlinks and `/mcps`; reconnect or start a
  fresh session for a new tool catalog. Do not invent paths or assume deferred
  tool-search functions exist when the current catalog does not advertise them.
- **No key / 401:** save the correct OpenRouter key privately and reconnect.
- **402 / exhausted credit:** let the user resolve billing; do not purchase credit.
- **403 / model unavailable:** check OpenRouter access/model slug; no silent switch
  to another provider or paid model.
- **Denied GUI action:** do not bypass the denial via shell/CLI/AppleScript. Check
  actual permissions and pending requests before naming any unseen prompt.
- **Stale element:** inspect again and target a fresh index, rather than repeat a
  destructive click or guessing a coordinate.
- **Uncertain Jev result:** gather new evidence or ask. A classifier is not a
  permission gate and cannot validate something that was never observed.

Upstream: https://github.com/iFurySt/open-codex-computer-use and
https://github.com/jkudish/jev-mcp. For OpenCode configuration/discovery consult
https://opencode.ai/v2/docs/mcp-servers and https://opencode.ai/v2/docs/skills.
