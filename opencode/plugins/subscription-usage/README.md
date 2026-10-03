# Subscription usage — OpenCode V2

Codex and Claude Code quota usage in OpenCode's **right-hand session sidebar**, below Context.
The plugin also replaces the built-in **Context** section, keeping its existing
token count, percent-used and USD-spend behavior (including compaction and undo).
Context, Subscription Usage, Codex and Claude Code headings are bold and
underlined. Codex appears first; subscription tiers are right-aligned beside the
provider names. Quota labels such as *5h*, *Week* and *Fable* are italicized.
Bars show **percent used**, followed by the time until reset. Claude's per-model
weekly quotas appear when present. Codex window labels come from the API: its
primary window is not always five hours. Uses the current OpenCode theme.

## Install

From the dotfiles repository root:

```sh
mkdir -p ~/.config/opencode/plugins
ln -s "$PWD/opencode/plugins/subscription-usage" ~/.config/opencode/plugins/subscription-usage
```

The tracked `opencode/cli.json` already enables `./plugins/subscription-usage`
and disables `opencode.sidebar.context` to prevent a duplicate Context section.
For another config, add both `"-opencode.sidebar.context"` and
`"./plugins/subscription-usage"` to `plugins` in `~/.config/opencode/cli.json`.
OpenCode supplies the runtime dependencies; no build step is needed. Restart the
TUI if it was already running. The sidebar needs `session.sidebar: "auto"` and
enough terminal width to be visible.

## Accounts and refresh

- **Claude Code:** reads `Claude Code-credentials` from macOS Keychain, falling
  back to `~/.claude/.credentials.json`. `CLAUDE_CONFIG_DIR` selects the file in
  that directory instead of the default account's Keychain entry.
- **Codex:** reads `${CODEX_HOME:-~/.codex}/auth.json`, including the selected
  ChatGPT account ID. Requires a ChatGPT subscription login, not an API key.
- Tokens are read anew each refresh and sent only to the corresponding provider's
  HTTPS usage endpoint. The plugin never saves credentials or redeems shared
  refresh tokens. Open Claude Code or Codex if the sidebar requests a login
  refresh; the CLI owns renewing its credentials.
- Makes at most **one request per provider/login every 120 seconds across this
  device**, regardless of how many OpenCode terminals or sidebars are open.
  Instances check the local cache every 15 seconds; an atomic SQLite claim allows
  only one process to fetch. There is no separate daemon or scheduled job.
- Click **↻**, use **`/usage-refresh`**, or choose **Refresh Claude / Codex usage**
  in the command palette to read the shared state and fetch if its device-wide
  budget is due. Manual refresh and opening/restarting another TUI **do not bypass
  the shared polling interval or cooldown**.
- API `Retry-After` is respected. Repeated 429s back off **5 → 10 → 20 → 30 minutes**
  (or longer if the server requests it), returning to five minutes after a success.
  Rate-limit errors include an inline countdown, e.g.
  `Rate Limited (Retrying in 1m)`. This is time until our next attempt, not a
  guarantee that Anthropic's limit will reset. Requests time out after ten seconds.
- Cache and cooldowns persist in
  `${XDG_CACHE_HOME:-~/.cache}/opencode/subscription-usage/usage.sqlite` (directory
  mode 0700, database 0600). Stores readings, errors, retry times and a one-way login
  fingerprint, **never credentials**. Accounts/profiles are isolated. Dead owners
  are detected by PID; interrupted attempts retain their reserved polling budget.
  If the shared cache cannot be opened, no independent network poll is started.
- Network failures keep the last reading visibly **stale**; authentication
  failures clear it. Missing/unsupported data says unavailable rather than 0%.
  Unloading cancels requests and clears timers. Polling runs only inside the TUI.

Optional polling interval in `cli.json` (minimum 60 seconds):

```json
{
  "plugins": ["-opencode.sidebar.context", {
    "package": "./plugins/subscription-usage",
    "options": { "refreshSeconds": 120 }
  }]
}
```

## Development

```sh
cd opencode/plugins/subscription-usage
bun install
bun run check
bun test
```

`tui.tsx` uses the V2 `@opencode/plugin/tui` API and `sidebar.content` slot.
`context.ts` mirrors the built-in OpenCode 2.0.22 context-usage calculation;
its tests cover latest-response selection, cache/reasoning tokens, model limits,
compaction and undo boundaries.
`usage.ts` owns credential reads, API parsing, and cancellable local monitoring.
`device.ts` uses OpenCode's Bun runtime and built-in SQLite for the device-wide
cache, request budget and cross-process ownership. Tests include simultaneous OS
processes and killed-owner recovery, using fixtures and fake credentials; they
do not access real logins or make network requests.
The usage endpoints are the ones used by the clients, not a stable public API:

- Claude: `https://api.anthropic.com/api/oauth/usage` (`anthropic-beta: oauth-2025-04-20`).
- Codex: `https://chatgpt.com/backend-api/wham/usage` (`ChatGPT-Account-Id`).

API-shape reference: CodexBar's [Claude OAuth fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
and [Codex OAuth notes](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md).
