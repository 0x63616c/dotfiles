# ci-notify

macOS desktop notifications for GitHub Actions CI, via a polling LaunchAgent.

Tells you, at a glance, when `main` ships (and **which services** built) or **what broke** — clicking the notification opens the run.

## How it works

GitHub can't push to your Mac, and its notifications API returns nothing for CI on
your *own* pushes (`reason=ci_activity` stays empty). So this **polls** `gh run list`
every 60s (GitHub's advertised `X-Poll-Interval`) for the newest **completed**,
non-cancelled run on the watched branch. When that run id changes vs the cursor in
`~/.local/state/ci-notify/seen`, it posts one notification (terminal-notifier,
grouped so a new one replaces the old).

The CI workflow's **job names are the services** — `build-{web,api,storybook,bosun}`:

- `success` → that image built & shipped → listed in "shipped — …"
- `skipped` → unchanged
- any `failure`/`timed_out` job → its name is the "CI failed — …" reason

> "shipped" not "deployed" on purpose: a green `deploy` job means the bosun webhook
> was accepted (image pushed to GHCR), not that the swarm service is healthy on
> homelab. True deploy-health would be a second poll against bosun, not GitHub.

Cancelled runs (fast successive pushes supersede each other) are **never** shown.

## Install / uninstall

```bash
ci-notify/install.sh                       # idempotent; resolves tool paths for the plist
launchctl bootout gui/$(id -u)/com.calum.ci-notify   # uninstall
```

Requires `gh` (logged in), `jq`, `terminal-notifier` on PATH. Auth uses your `gh`
keyring login — **no secret in the plist**.

## Config (env, optional)

| Var | Default | Meaning |
|---|---|---|
| `CI_NOTIFY_REPO`   | `0x63616c/control-center` | `owner/repo` to watch |
| `CI_NOTIFY_BRANCH` | `main` | branch to watch |
| `CI_NOTIFY_STATE`  | `~/.local/state/ci-notify` | cursor + log dir |

To watch more repos, run `ci-notify.sh` once per repo (separate state dir) or extend
the script to loop a repo list. Set env defaults in the plist's `EnvironmentVariables`.

## Files

| Path | Role |
|---|---|
| `ci-notify.sh` | the poll + notify script (fail-open) |
| `launchd/com.calum.ci-notify.plist.template` | LaunchAgent template (`__SCRIPT__`/`__HOME__`/`__PATH__`) |
| `install.sh` | renders the plist with machine paths + bootstraps it |
| `~/.local/state/ci-notify/{seen,log,err}` | cursor + logs (not tracked) |
