# Subscription usage — OpenCode V2

Claude Code and Codex quota usage in OpenCode's **right-hand session sidebar**, below Context.
Bars show **percent used**, followed by the time until reset. Claude's per-model
weekly quotas appear when present. Codex window labels come from the API: its
primary window is not always five hours. Uses the current OpenCode theme.

## Install

From the dotfiles repository root:

```sh
mkdir -p ~/.config/opencode/plugins
ln -s "$PWD/opencode/plugins/subscription-usage" ~/.config/opencode/plugins/subscription-usage
```

The tracked `opencode/cli.json` already enables `./plugins/subscription-usage`.
For another config, add that path to `plugins` in `~/.config/opencode/cli.json`.
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
- Refreshes on load and every **120 seconds**. Click **↻**, use **`/usage-refresh`**,
  or choose **Refresh Claude / Codex usage** in the command palette. Overlapping
  refreshes are coalesced and API `Retry-After` is respected, including manual
  requests. Requests time out after ten seconds.
- Network failures keep the last reading visibly **stale**; authentication
  failures clear it. Missing/unsupported data says unavailable rather than 0%.
  Unloading cancels requests and clears timers. Polling runs only inside the TUI.

Optional polling interval in `cli.json` (minimum 60 seconds):

```json
{
  "plugins": [{
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
`usage.ts` owns credential reads, API parsing, and cancellable polling. Tests use
fixtures and fake credentials; they do not access real logins or make requests.
The usage endpoints are the ones used by the clients, not a stable public API:

- Claude: `https://api.anthropic.com/api/oauth/usage` (`anthropic-beta: oauth-2025-04-20`).
- Codex: `https://chatgpt.com/backend-api/wham/usage` (`ChatGPT-Account-Id`).

API-shape reference: CodexBar's [Claude OAuth fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
and [Codex OAuth notes](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md).
