# Hammerspoon API cheat-sheet

Condensed from the official index at <https://www.hammerspoon.org/docs/>. Full docs for any
module: `https://www.hammerspoon.org/docs/<module>.html`, or at runtime `hs.help("hs.window")`.

Hammerspoon version on this machine: **1.1.1** (check with `hs -c 'hs.processInfo.version'`).

## Core — `hs`

| Function | Notes |
|---|---|
| `hs.reload()` | Fresh Lua state. Everything not in `init.lua` is lost. |
| `hs.relaunch()` | Full app quit + restart. Needed after some permission changes. |
| `hs.configdir` | `/Users/calum/.hammerspoon` (a symlink into the dotfiles repo). |
| `hs.execute(cmd[, with_user_env])` | **Blocking.** No login PATH unless the 2nd arg is true. |
| `hs.openConsole([focus])` | Open the console window. |
| `hs.printf(fmt, ...)` | Formatted print to console. |
| `hs.inspect(v)` | Human-readable dump of a table — essential for probing. |
| `hs.accessibilityState([prompt])` | Is Accessibility granted; `true` opens the prompt. |
| `hs.shutdownCallback` | Function run before the Lua state is destroyed. Cleanup hook. |
| `hs.loadSpoon(name[, global])` | Load a Spoon → `spoon.Name`. |
| `hs.autoLaunch([state])`, `hs.dockIcon([state])`, `hs.menuIcon([state])`, `hs.consoleOnTop([state])` | App behaviour toggles. |
| `hs.allowAppleScript([state])` | Off by default. |
| `hs.help(id)` | Runtime API docs. |

## Windows & applications

- **`hs.window`** — `focusedWindow()`, `allWindows()` (current Space only, slow), `frame()` /
  `setFrame()`, `setFrameWithWorkarounds()`, `moveToUnit('[x,y,w,h]')`, `maximize()`,
  `moveToScreen()`, `screen()`, `application()`, `title()`, `focus()`, `close()`.
  Globals: `hs.window.animationDuration` (0.2), `hs.window.setFrameCorrectness` (false).
- **`hs.window.filter`** — the supported way to query windows repeatedly or across Spaces, and
  to subscribe to window events (`windowCreated`, `windowFocused`, `windowDestroyed`).
  Prefer over polling `allWindows()`.
- **`hs.window.switcher`** — cmd-tab replacement. **`hs.window.highlight`** — highlight focus.
- **`hs.application`** — `get(name)`, `launchOrFocus(name)`, `runningApplications()`,
  `frontmostApplication()`, `:allWindows()`, `:findMenuItem({"Develop","..."})`,
  `:selectMenuItem({...})`, `:kill()`, `:hide()`.
- **`hs.application.watcher`** — `new(cb)` then `:start()`; events `launched`, `terminated`,
  `activated`, `deactivated`, `hidden`, `unhidden`.
- **`hs.appfinder`** — `appFromName()`, `windowFromWindowTitle()`.
- **`hs.grid`**, **`hs.layout`**, **`hs.expose`**, **`hs.hints`**, **`hs.spaces`** (+
  `hs.spaces.watcher`), **`hs.screen`** (+ `hs.screen.watcher` for display layout changes).

## Input

- **`hs.hotkey`** — `bind(mods, key[, msg], pressedFn[, releasedFn, repeatFn])`, `new(...)`,
  `:enable()`, `:disable()`, `:delete()`, `assignable()`, `systemAssigned()`, `showHotkeys()`.
  Duplicate combos shadow, LIFO, silently.
- **`hs.hotkey.modal`** — `new(mods, key)`, `:enter()`, `:exit()`, `:bind(...)`, and the
  `entered`/`exited` callbacks. For vim-style layers.
- **`hs.eventtap`** — `new({types}, fn):start()`; `fn` returns `false` to pass through, `true`
  to swallow. `hs.eventtap.event.types.*` (`keyDown`, `flagsChanged`, `systemDefined`,
  `leftMouseDown`, `scrollWheel`, …). `event:systemKey()` decodes media keys.
  `hs.eventtap.keyStroke(mods, key)` and `hs.eventtap.keyStrokes(str)` synthesise input.
- **`hs.keycodes`** — key-string ↔ keycode, `hs.keycodes.currentSourceID()` for layout.
- **`hs.mouse`** — pointer position, `hs.mouse.absolutePosition()`.

## Timing

- **`hs.timer`** — `doAfter(sec, fn)`, `doEvery(sec, fn)`, `doAt(time, [repeat], fn)`,
  `waitUntil(pred, fn)`, `usleep(µs)`. Objects must be **retained** and `:start()`ed
  (`doAfter`/`doEvery` start themselves, but still need a reference to avoid GC).
- **`hs.timer.delayed`** — coalesces bursty async events into one call. Use for debouncing a
  watcher that fires repeatedly (e.g. a pathwatcher during a multi-file save).

## Shelling out & data

- **`hs.task`** — `new(path, doneFn[, streamFn], args)`, `:start()`, `:setInput()`,
  `:terminate()`, `:waitUntilExit()`. `doneFn(exitCode, stdout, stderr)`. Absolute paths only.
- **`hs.json`** — `encode(t[, pretty])`, `decode(str)` (**throws** on bad input — wrap in
  `pcall`), `read(path)`, `write(t, path)`.
- **`hs.osascript`** / **`hs.applescript`** / **`hs.javascript`** — OSA bridges.
- **`hs.http`** — `get/post/asyncGet/asyncPost`. **`hs.httpserver`**, **`hs.websocket`**.
- **`hs.fnutils`** — `map`, `filter`, `each`, `find`, `contains`, `concat`, `partial`.
- **`hs.settings`** — `set/get/clear/getKeys`. Persists across reloads and restarts.
- **`hs.pasteboard`** (+ `.watcher`), **`hs.fs`** (+ `.volume`, `.xattr`), **`hs.plist`**,
  **`hs.sqlite3`**, **`hs.base64`**, **`hs.hash`**, **`hs.geometry`**, **`hs.math`**.

## Watchers (all need retaining + `:start()`)

| Module | Watches |
|---|---|
| `hs.pathwatcher` | Files/dirs recursively. `new(path, fn)` → `fn(files, flagTables)`. |
| `hs.application.watcher` | App launch/terminate/activate. |
| `hs.audiodevice.watcher` | Audio hardware changes (`dIn `, `dev#`, …) — note the trailing space in `"dIn "`. |
| `hs.caffeinate.watcher` | Sleep/wake, screen lock, screensaver, session switch. |
| `hs.screen.watcher` | Display layout changes. |
| `hs.wifi.watcher` | SSID change. |
| `hs.usb.watcher` | Device attach/detach. |
| `hs.battery.watcher` | Power source / charge. |
| `hs.spaces.watcher` | Mission Control Space change. |
| `hs.uielement.watcher` | Per-element accessibility events. |
| `hs.distributednotifications` | `NSDistributedNotificationCenter`. |

Per-device audio watchers are separate from the global one:
`dev:watcherCallback(fn); dev:watcherStart()` (as in this config's mic watcher).

## UI & feedback

- **`hs.alert`** — `show(msg[, duration])`, `closeAll()`. Transient on-screen text.
- **`hs.notify`** — Notification Centre entries; `new(fn, {title=, informativeText=}):send()`.
- **`hs.menubar`** — `new()`, `:setTitle()`, `:setIcon()`, `:setMenu(table|fn)`. Retain it.
- **`hs.chooser`** — searchable picker UI. **`hs.dialog`** — alerts/panels/file pickers.
- **`hs.canvas`** — drawing (supersedes the deprecated `hs.drawing`).
- **`hs.webview`**, **`hs.image`**, **`hs.styledtext`**, **`hs.sound`**, **`hs.speech`**.

## Debugging

- **`hs.logger`** — `new(id[, level])`; **dot syntax**: `log.d/df/i/f/w/wf/e/ef/v/vf`.
  Levels 0–5 = nothing/error/warning/info/debug/verbose.
  `hs.logger.history()`, `printHistory()`, `setGlobalLogLevel()`, `defaultLogLevel`.
- **`hs.console`** — console window control, history, colours.
- **`hs.ipc`** — the `hs` CLI. `cliInstall(path)`, `cliStatus()`, `cliUninstall()`.
- **`hs.axuielement`** — raw accessibility tree; the escape hatch when `hs.window`/
  `hs.application` can't reach a control. `hs.axuielement.observer` for events.
- **`hs.crash`**, **`hs.doc`**, **`hs.doc.hsdocs`** (local docs web server).

## Other notable

`hs.caffeinate` (prevent sleep, lock screen), `hs.brightness`, `hs.audiodevice`,
`hs.spotify` / `hs.itunes` / `hs.deezer` / `hs.vox`, `hs.urlevent` (`bind(name, fn)` for
`hammerspoon://` URLs + default-browser handling), `hs.shortcuts` (run Shortcuts.app
shortcuts), `hs.sharing`, `hs.location`, `hs.host`, `hs.network` (+ `.ping`,
`.reachability`), `hs.midi`, `hs.streamdeck`, `hs.razer`, `hs.serial`, `hs.watchable`.
