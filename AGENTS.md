# dotfiles — repo rules

This is Calum's dotfiles repo. Three standing rules for working here:

## 1. "Save X" → commit AND push automatically

When Calum asks to **save** something into this repo (a config, dotfile, skill, hook, etc.), don't stop at writing the file. Commit it and `git push` to `main` in the same turn, without being asked again. Saving means it lands on the remote.

## 2. Always document additions/updates in the README

Any time a new file/dir is added or an existing one changes meaning, update `README.md` in the same change:

- New thing → add it to the relevant `## Contents` table and the `## Install` block.
- Changed thing → update its row so the description stays accurate.

The README is the index of what this repo carries; it must never drift from reality.

## 3. Scheduled jobs are Hammerspoon data, not new launchd plists

Hammerspoon is the scheduler for this machine. **Never hand-write a new `.plist`** to run something on a timer.

A new recurring job is a row in the job registry — `hammerspoon/jobs.lua` (create it if it doesn't exist yet) — and nothing else:

```lua
jobs.register({
  id    = "some-job",          -- also the label shown in the Hyper+J panel
  every = 600,                 -- seconds; or `at = "12:00"` for a daily slot
  run   = { "/path/to/script", "--flag" },
})
```

Rules that follow from that:

- **The heavy lifting stays in its own script** (bash, or whatever suits). The registry schedules and reports; it does not reimplement the work in Lua.
- **Schedules must survive a reload.** `hs.timer.doEvery` restarts its countdown every time the config reloads, and `reload.lua` reloads on every `.lua` save — so a naive interval job can be starved forever. Persist a per-job `lastRun` timestamp and decide on load whether a run is overdue. Same mechanism gives catch-up after sleep.
- **Long-running work must not be a child of Hammerspoon.** `hs.reload()` kills in-flight `hs.task` children, so anything that runs for minutes needs to be detached or left to launchd. `restic` is the standing exception and keeps its plist for this reason.
- Deleting a job means deleting its registry row, its script, and its README entry together.

# Setup

3D Printer = P2S bambu

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
