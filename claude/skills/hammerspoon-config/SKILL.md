---
name: hammerspoon-config
description: Use when writing or editing Hammerspoon Lua config — hotkeys, window management, watchers, eventtaps, menubar items, timers, or any macOS automation in init.lua. Triggers on "in Hammerspoon", hs.hotkey/hs.window/hs.eventtap/hs.task/hs.timer, or editing hammerspoon/init.lua (~/.hammerspoon).
---

# Writing Hammerspoon config

Hammerspoon is a bridge between macOS and a Lua interpreter. It does nothing out of the box —
everything comes from the config. Here `init.lua` is a ~40-line bootstrap that installs the
`hs.ipc` CLI and then auto-loads every other top-level `.lua` in `~/.hammerspoon` as a feature
module (`dictation.lua`, `hyper.lua`, `reload.lua`). **Write new features as their own module
file** — dropping the file in is all that's needed; there is no list to register it in.

## Where the config lives on this machine

**`~/.hammerspoon` is a symlink to `hammerspoon/` in the dotfiles repo**
(`/Users/calum/code/github.com/0x63616c/dotfiles/hammerspoon`). Verified 2026-09-20.

That means:

- Editing `hammerspoon/init.lua` in the repo **is** editing the live config. There is no copy
  or sync step. Never write to `~/.hammerspoon/init.lua` as if it were a separate file — you'd
  be editing the repo without realising, and leaving a dirty worktree.
- `hs.configdir` reports `/Users/calum/.hammerspoon` (the symlink path, not the resolved one).
- Because it's a tracked repo file, changes must follow the repo's rules: README entry for
  anything new, and "save" means commit **and** push.

Confirm the symlink before assuming it, on an unfamiliar machine:

```bash
readlink ~/.hammerspoon
```

## Edits are inert until a reload

Saving a file changes nothing by itself. The config is only executed at load.

This config installs the standard `hs.pathwatcher` auto-reload (see `reload.lua`),
so saving a `.lua` file under the config dir triggers `hs.reload()` within a second or so.
**Don't rely on it silently** — it's a convenience, not a verification. After an edit, reload
explicitly and check the result:

```bash
hs -c 'hs.reload()'
```

See the `hammerspoon-cli` skill for the full test-before-commit loop, and
`hammerspoon-debug` when something doesn't fire.

`hs.reload()` **destroys the Lua state and builds a fresh one**. Every global, timer, watcher
and eventtap is torn down and recreated by re-running `init.lua` and every module it loads.
Anything you created ad-hoc via the console or `hs -c` is gone. Anything not re-established by
the config does not survive.
Use `hs.shutdownCallback` if something needs cleaning up before the state is destroyed.

## The single biggest footgun: garbage collection

**Watchers, timers, eventtaps and pathwatchers are garbage-collected if nothing references
them, and they stop working silently.** No error, no log line — the automation just quietly
dies, often minutes later when the GC next runs.

So they must be held in a variable that outlives the setup function: a global, or a
module-level local.

```lua
-- WRONG: collected, stops firing at an unpredictable point
hs.pathwatcher.new(hs.configdir, reloadConfig):start()
local t = hs.timer.doEvery(60, check)   -- local inside a function = same problem

-- RIGHT: held at module level / global
configWatcher = hs.pathwatcher.new(hs.configdir, reloadConfig):start()
```

This is why Calum's modules have bare globals — `micState`, `micDevice`, `mediaKeyTap` in
`dictation.lua`, `configWatcher` in `reload.lua`, `hyperShortcuts` in `hyper.lua`. That is
**deliberate retention, not sloppiness**. Don't "tidy" them into `local`s inside functions.
A module-level `local` at the top of a file is fine and is the better style for new code;
a `local` inside a function is not. Note the globals are shared across modules — there is one
Lua state, not one per file — so a global in `hyper.lua` is readable from anywhere.

Symptom to recognise: "it worked for a bit then stopped" → almost always this.

## House style (match the existing file)

Read `hammerspoon/dictation.lua` before adding to the config — it's the fullest worked example
of the house style. The conventions there:

- **A comment header explaining *why*, not what.** The existing one documents the whole design
  rationale and the known limits. Match that depth for any non-obvious behaviour — especially
  anything learned the hard way (the `--no-artwork` flag exists because large `hs.task` output
  blocked the pipe; that comment is doing real work).
- **`hs.logger` per module**, named after the module: `local log = hs.logger.new("dictation", "debug")`, then
  `log.d(...)` / `log.df(...)`.
- **Async `hs.task` with callbacks**, not blocking `hs.execute`.
- **Absolute paths to binaries** (`/opt/homebrew/bin/media-control`).
- **`pcall` around anything that can throw** on bad input — `pcall(hs.json.decode, stdout)`.
- **A session counter** (`micState.session`) to discard callbacks that arrive after state has
  moved on. Reuse that pattern for any async work that can be superseded.
- Section dividers: `-- Name ------------------------------------------------------------`
- Two-space indent, no semicolons.

**A new feature is a new file.** `init.lua` is a bootstrap that `require`s every other
top-level `.lua` in the config dir automatically (alphabetically, each in a `pcall`), so
dropping in `windows.lua` is all it takes — there is no list to register it in. Don't append
new features to an existing module unless they genuinely belong to it.

Two consequences worth holding onto:

- **Load order is alphabetical, so modules must not depend on it.** Anything that reads another
  module's state — the `hyperShortcuts` registry, say — must read it at *display/callback* time,
  not at load time, or it will race whichever module happens to sort later.
- **A `_` prefix skips a file**, so `_scratch.lua` won't auto-load.

## Adding a Hyper shortcut

Hyper is Ctrl+Shift+Alt+Cmd, held by the Caps key in the QMK firmware. **Never bind it with
`hs.hotkey.bind` directly.** Go through `hyper.bind`, from any module:

```lua
local hyper = require("hyper")

hyper.bind("x", "Screenshot library", function()
  screenshotsLibrary.open()
end)
```

Registering and binding are the same call on purpose: `hyper.bind` appends `{key, label}` to
the `hyper.shortcuts` registry, and the hold-to-reveal cheatsheet (hold Hyper 0.5s) builds
itself from that registry at display time. So a new shortcut shows up on the card with no
other wiring — and, equally, there is no way to add one that *doesn't*. The label is asserted
non-empty and will error at load if you omit it; that's deliberate, not something to work
around.

`require("hyper")` resolves on demand and caches, so it works from any module regardless of
`init.lua`'s alphabetical load order.

## Shelling out: hs.task vs hs.execute

| | `hs.task.new(path, cb, args)` | `hs.execute(cmd[, with_user_env])` |
|---|---|---|
| Blocking | No — callback | **Yes, blocks all of Hammerspoon** |
| Args | Array, no shell quoting bugs | A shell string |
| PATH | You give an absolute path | **Does not get your login PATH** unless `with_user_env=true` (which is slow) |
| Use for | Anything that isn't instant | Quick one-liners in the console |

Default to `hs.task`. A blocking `hs.execute` freezes every hotkey and watcher for its
duration. Remember `:start()` — a task that's constructed but never started does nothing.

Large output can block the task's pipe; if a command has a `--quiet`/`--no-<heavy-thing>`
flag, use it.

## Hotkeys

```lua
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "W", function() hs.alert.show("hi") end)
```

- `bind()` creates **and enables**. `new()` creates disabled — pair with `:enable()`.
- **Duplicate combos shadow silently**, last-enabled wins, LIFO. Disabling or deleting the
  newer one restores the older. No error is raised, so a clash looks like "my hotkey does
  nothing".
- `hs.hotkey.assignable(mods, key)` and `hs.hotkey.systemAssigned(mods, key)` tell you whether
  macOS already claims a combo. Informational only — they don't guarantee Hammerspoon can or
  can't take it.
- `hs.hotkey.showHotkeys(mods, key)` binds a key that displays all active hotkeys — useful for
  auditing what's bound.
- For modes/layers use `hs.hotkey.modal`.
- Note: this config currently binds **no** hotkeys. Adding the first one means picking a
  leader combo — ask Calum rather than inventing one, and check it isn't system-assigned.

## Windows

Requires **Accessibility** permission (already granted for Hammerspoon; see
`hammerspoon-debug` if window calls return nil or do nothing).

```lua
local win = hs.window.focusedWindow()
if not win then return end              -- always nil-check; there may be no focused window
local f = win:frame()
f.w = f.w / 2
win:setFrame(f)
win:moveToUnit('[0,0,0.5,1]')           -- or: fractions of the screen
```

- `hs.window.animationDuration` defaults to `0.2`; set to `0` for instant, scripted moves.
- `hs.window.setFrameCorrectness = true` fixes unreliable placement at the Dock edge and
  between screens — costs a round-trip, so enable only if you hit the problem.
- `hs.window.allWindows()` is **current-Space only** and slow when polled; it also returns
  odd non-windows (Chrome status bars). For anything repeated, or anything cross-Space, use
  `hs.window.filter`.
- `win:screen()`, `screen:frame()` (usable area, excludes Dock/menu bar) vs
  `screen:fullFrame()` (the whole display).

## Eventtaps

```lua
mediaKeyTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
  -- return false to pass the event through; true to swallow it
  return false
end):start()
```

- Must be retained (see GC above) and `:start()`ed.
- Needs Accessibility, and may separately prompt for **Input Monitoring**.
- **Return `false`** unless you genuinely mean to consume the event — returning `true` from a
  broad tap can swallow real user input system-wide.
- A slow callback here degrades the whole machine's input latency. Keep it cheap; hand real
  work to `hs.timer.doAfter(0, ...)` or a task.
- `hs.eventtap.event.types.keyDown` taps are the heavyweight option — prefer `hs.hotkey` for
  discrete shortcuts.

## Persisting state

`hs.settings.set(key, value)` / `hs.settings.get(key)` survives reloads and restarts
(simple Lua types only). Globals do not survive a reload. Don't hand-roll a JSON file for
small state.

## Before you finish

1. Syntax-check — a parse error takes down the **entire** config, including `hs.ipc`, which
   kills the `hs` CLI and leaves the GUI as your only recovery route:
   ```bash
   hs -c 'local f, err = loadfile(hs.configdir .. "/init.lua"); return err or "PARSE OK"'
   ```
   (`luac` is not installed on this machine — use the above.)
2. Reload, and verify the new behaviour actually fires (`hammerspoon-cli`).
3. If the change adds a feature or alters what `init.lua` does, update its README row —
   the repo rule is that the README never drifts.

A fuller module/function reference is in `API-CHEATSHEET.md` next to this file.
