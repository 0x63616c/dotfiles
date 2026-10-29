# Subscription usage — OpenCode V2

Codex and Claude Code quota usage in OpenCode's **right-hand session sidebar**, below Context.
The plugin also replaces the built-in **Context** section, keeping its existing
token count, percent-used and USD-spend behavior (including compaction and undo).
**Context** and **AI Subscriptions** headings are bold and underlined. Codex
appears first; provider names are bold without underlines, with subscription tiers
right-aligned beside them. Quota labels such as *5h*, *Week* and *Fable* are italicized.
Bars fill the available row width, with the reset countdown flush right.
The percentages show **used / time elapsed**: `2% / 3%` means 2% of the quota
used, 3% of that quota window elapsed (97% of the time remains). The slash and
elapsed percentage stay muted gray; only the used percentage and bar are coloured. Yellow means
usage is ahead of elapsed time (or quota is 70%+ used), red means at least twice
that pace (or quota is 90%+ used); stale readings stay muted. This compares average consumption with a
linear budget, not a guarantee of future usage. Unknown durations/resets show
only percent used, rather than guessing a time percentage. Old cached Week/5h
windows and scoped models sharing a weekly reset can recover the fixed duration
without another API request. Claude's per-model
weekly quotas appear when present. Codex window labels come from the API: its
primary window is not always five hours. Uses the current OpenCode theme.
Codex also shows an italic **Resets available** heading with the count on the
right, followed by one numbered line per reset (earliest expiry first):
`1 - Expires 22 Oct 2026`, `2 - Expires 29 Oct 2026`. Unknown dates say
`Expiry unavailable`; dates always include the year. This is read-only: no reset
is redeemed. Known expirations decrement a cached count as they pass. Inventory
failures retain the last count and its own age instead of inventing zero.
Subscription renewal/expiry is not fetched: that needs separate ChatGPT web/billing
authentication, not the existing Codex usage login.

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
  HTTPS usage/inventory endpoints. The plugin never saves credentials or redeems shared
  refresh tokens. Open Claude Code or Codex if the sidebar requests a login
  refresh; the CLI owns renewing its credentials.
- Makes at most **one refresh cycle per provider/login every 120 seconds across this
  device**, regardless of how many OpenCode terminals or sidebars are open.
  Instances check the local cache every 15 seconds; a brief atomic SQLite transaction
  reserves the next allowed request time, then releases the database before fetching.
  There are **no persistent refresh locks, PID owners or waiting loops**: other
  terminals immediately show cached data (or `Refresh pending` until the next local read).
  Claude makes one usage GET; Codex makes one usage GET
  and one best-effort reset-inventory GET in that same reservation. Inventory 429s have
  a separately persisted cooldown, so they do not block ordinary quota updates.
  There is no separate daemon or scheduled job.
- Click **↻** to read the shared state and fetch if its device-wide
  budget is due. Manual refresh and opening/restarting another TUI **do not bypass
  the shared polling interval or cooldown**.
- API `Retry-After` is respected. Repeated 429s back off **5 → 10 → 20 → 30 minutes**
  (or longer if the server requests it), returning to five minutes after a success.
  Without a cached reading, rate-limit errors include an inline countdown, e.g.
  `Rate Limited (Retrying in 1m)`. With a reading, the error stays out of the UI and
  a small gray `Updated 12m ago` note shows its age instead — no stale badge.
  The retry countdown is time until our next attempt, not a guarantee that
  Anthropic's limit will reset. Deadlines cover transport **and response bodies**:
  usage requests get ten seconds, optional inventory four seconds, and a whole
  fetch cycle twenty seconds. The monitor also bounds credential/cache/loading work
  to sixty seconds. Timeout/cancellation rejects even if an operation ignores abort.
- Cache and cooldowns persist in
  `${XDG_CACHE_HOME:-~/.cache}/opencode/subscription-usage/usage.sqlite` (directory
  mode 0700, database 0600). Stores readings, errors, retry times and a one-way login
  fingerprint, **never credentials**. Accounts/profiles are isolated. Interrupted,
  killed or frozen attempts retain their reserved polling budget but cannot block
  the next due attempt. A per-attempt ID only fences writes: late results cannot
  overwrite newer readings or cooldowns. Legacy owner records do not block refreshes.
  If the shared cache cannot be opened, no independent network poll is started.
- Network failures keep the last reading, with muted colours and a quiet age note;
  readings older than five minutes also get that note. Authentication failures
  clear the reading. Missing/unsupported data says unavailable rather than 0%.
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
cache, request-time reservations and fenced writes. Tests include simultaneous OS
processes, live legacy owners, killed/frozen attempts, late completions, abort-ignoring
transports, stalled response bodies and responsive bar/countdown layout, using fixtures and fake credentials; they
do not access real logins or make network requests.
The usage endpoints are the ones used by the clients, not a stable public API:

- Claude: `https://api.anthropic.com/api/oauth/usage` (`anthropic-beta: oauth-2025-04-20`).
- Codex: `https://chatgpt.com/backend-api/wham/usage` (`ChatGPT-Account-Id`).
- Codex banked resets: `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
  (same account header, `OpenAI-Beta: codex-1`, read-only GET).

API-shape reference: CodexBar's [Claude OAuth fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
and [Codex OAuth notes](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md).
