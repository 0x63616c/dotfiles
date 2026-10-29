---
name: hammerspoon-debug
description: Use when Hammerspoon config isn't working — a hotkey, watcher, eventtap or automation does nothing, fires once then stops, or behaves as if the old config is still loaded. Covers reading the console and hs.logger history, checking Accessibility/Input Monitoring permissions, and the common silent failure modes.
---

# Debugging Hammerspoon

Hammerspoon fails **quietly**. Most "it doesn't work" reports are one of four things, and
none of them raise a visible error. Work the triage table before reading code.

## Triage first

| Symptom | Most likely cause | Check |
|---|---|---|
| Nothing at all happens; no log lines | Config never reloaded, or failed to load | `hs -c 'hs.logger.printHistory()'`; reload explicitly |
| Worked for a while, then stopped | **Garbage collection** — watcher/timer/eventtap not retained | Is the object assigned to a global / module-level var? |
| Hotkey does nothing | Shadowed by another binding, or claimed by macOS | `hs.hotkey.systemAssigned()`, `hs.hotkey.showHotkeys()` |
| Window calls return nil or no-op | Accessibility permission | `hs -c 'hs.accessibilityState()'` |
| Eventtap never fires | Input Monitoring / Accessibility, or tap not `:start()`ed | Permissions pane; check for the `:start()` |
| Old behaviour persists after editing | Never reloaded, or reload errored partway | `hs -c 'hs.reload()'` then re-check |
| Half the config works, half doesn't | Runtime error mid-load — everything after it never ran | Console / log history for the traceback |

## Read the logs

`hs.logger` history is queryable remotely — you don't need the GUI console:

```bash
hs -c 'hs.logger.printHistory()'
hs -c 'hs.inspect(hs.logger.history())'      # structured: timestamp, level, id, message
```

Turn the volume up when hunting something intermittent:

```bash
hs -c 'hs.logger.setGlobalLogLevel("verbose")'   # 0 nothing → 5 verbose
hs -c 'hs.logger.defaultLogLevel = "debug"'      # applies to loggers created after this
hs -c 'hs.logger.historySize(1000)'              # keep more scrollback
```

Remember to put it back afterwards — verbose logging on an eventtap is noisy and costs
latency.

**`hs.logger` uses dot syntax, not colon.** `log.d("x")`, `log.df("%s", v)`,
`log.setLogLevel(4)` — **not** `log:d(...)`. Calling with a colon passes the logger as the
first argument and produces confusing output or an error. This is the single most common
Hammerspoon logging bug.

Levels: `0` nothing, `1` error, `2` warning, `3` info, `4` debug, `5` verbose. Methods:
`e/ef` error, `w/wf` warn, `i/f` info, `d/df` debug, `v/vf` verbose — the `f` variants take
`string.format` arguments.

This config's logger is `hs.logger.new("micwatch", "debug")`, so mic-watcher lines are
already tagged `micwatch`.

## The GUI console

```bash
hs -c 'hs.openConsole()'    # or: menubar icon → Console
hs -C                       # mirror console print output into this terminal
```

The console is a live REPL against the running instance — same environment as `hs -c`.
Each entered line is its own scope, so `local` variables don't survive between lines.

Errors during config load print here with a Lua traceback. If something is wrong at load
time and the CLI is unresponsive, **this is the recovery route** — see below.

## Permissions

Window management and eventtaps need **Accessibility**. Eventtaps may additionally need
**Input Monitoring**. Screen-capture APIs need **Screen Recording**.

```bash
hs -c 'hs.accessibilityState()'        # false ⇒ not granted
hs -c 'hs.accessibilityState(true)'    # true ⇒ also raise the system prompt
```

System Settings → Privacy & Security → Accessibility (and Input Monitoring). Hammerspoon
already has Accessibility on this machine — it's documented as a requirement in the repo
README.

Two traps:

- After granting or re-granting a permission, **`hs.relaunch()`** (a full restart), not just
  `hs.reload()`. macOS caches the grant per-process.
- A Hammerspoon **upgrade** can invalidate the existing grant — the entry still looks ticked
  but no longer applies. Toggle it off and on again, then relaunch. Symptom: window and
  eventtap code that worked yesterday silently stops after an update.

## Silent failure: garbage collection

The most common "it stopped working" cause. Watchers, timers, eventtaps and pathwatchers are
collected if nothing holds a reference — no error, they just stop.

```bash
# Is the object still alive?
hs -c 'hs.inspect(mediaKeyTap)'
hs -c 'return mediaKeyTap:isEnabled()'
hs -c 'hs.inspect(configWatcher)'
```

`nil` means it was never retained (or the reload didn't run). Fix is in the config: assign to
a global or a module-level local, never a function-scoped one. See `hammerspoon-config`.

## Silent failure: hotkey shadowing

Duplicate combos don't error — the last one enabled wins, and disabling it silently restores
the earlier one.

```bash
hs -c 'hs.inspect(hs.hotkey.systemAssigned({"cmd","alt"}, "W"))'   # does macOS own it?
hs -c 'hs.hotkey.assignable({"cmd","alt"}, "W")'
hs -c 'hs.hotkey.showHotkeys({"cmd","shift"}, "H")'                # bind a "what's bound?" key
```

Also check the app in the foreground — an app-level shortcut can win before Hammerspoon sees
the key.

## Recovering a broken config

A syntax error in `init.lua` takes down **everything**, including `hs.ipc` — so `hs` stops
answering and the terminal is no longer a way in.

1. Find the error without executing anything. If the CLI still answers:
   ```bash
   hs -c 'local f,e = loadfile(hs.configdir.."/init.lua"); return e or "PARSE OK"'
   ```
   If it doesn't, paste the same `loadfile` line into the GUI console — `loadfile` parses
   without executing, so it's safe either way. (`luac -p` would also work but **`luac` is not
   installed on this machine**.)
2. Fix the file.
3. Reload via the **menubar icon → Reload Config** if the CLI is dead. Once the config loads
   cleanly, `hs.ipc` comes back and `hs` works again.
4. If the menubar icon itself is gone: `open -a Hammerspoon` (or kill and relaunch).

Prevention: syntax-check before every reload. It's one command.

## Probing state

```bash
hs -c 'hs.inspect(hs.window.focusedWindow())'
hs -c 'hs.inspect(hs.window.focusedWindow():frame())'
hs -c 'hs.inspect(hs.application.frontmostApplication():name())'
hs -c 'hs.inspect(micState)'                      # this config's own state table
hs -c 'hs.inspect(hs.audiodevice.defaultInputDevice():inUse())'
hs -c 'hs.inspect(hs.spoons.list())'
hs -c 'hs.help("hs.window.setFrame")'             # runtime API docs
```

`hs.inspect()` on any table is the workhorse. For accessibility-level inspection of an app's
UI tree when `hs.window`/`hs.application` can't reach a control, drop to `hs.axuielement`.

## Report findings properly

When reporting back, distinguish the three kinds of failure — they have different fixes and
conflating them wastes a round trip:

- **Permission** — code is fine, macOS is blocking it.
- **Lifecycle** — code is fine, it was collected or never reloaded.
- **Logic** — the code is actually wrong.
