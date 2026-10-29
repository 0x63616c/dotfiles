---
name: hammerspoon-cli
description: Use to run Lua inside the live Hammerspoon instance from the terminal via the `hs` CLI / hs.ipc — reload the config after editing it, probe what Hammerspoon currently sees (windows, apps, screens, state), or test a snippet before committing it to init.lua.
---

# Driving Hammerspoon from the terminal (`hs` / hs.ipc)

The `hs` command sends Lua into the **already-running** Hammerspoon instance and prints the
result. It's the difference between editing the config blind and actually verifying it.

Verified working on this machine 2026-09-20:

```bash
$ hs -c 'hs.processInfo.version'
1.1.1
$ hs -c 'hs.configdir'
/Users/calum/.hammerspoon
```

## Why it works here

`hammerspoon/init.lua` starts with:

```lua
require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")
```

`hs.ipc` is **not loaded by default** — that `require` is what opens the message port, and
`cliInstall` is what puts the `hs` binary on PATH (`/opt/homebrew/bin/hs`, a symlink into
`Hammerspoon.app`). Both live in the config, which has a consequence worth internalising:

> **If `init.lua` fails to parse, `hs.ipc` never loads and the `hs` CLI stops answering.**
> A broken *feature module* is contained: `init.lua` runs `cliInstall` before the load loop and
> `pcall`s each `require`, so the CLI survives and only that module is skipped.
> You lose your remote control at exactly the moment you need it, and recovery is via the
> Hammerspoon menubar icon → Console / Reload Config, i.e. the GUI.

On a fresh machine, or if `hs` isn't found:

```bash
hs -c 'hs.ipc.cliStatus("/opt/homebrew")'     # is it installed & correct
hs -c 'hs.ipc.cliInstall("/opt/homebrew")'    # (or from the Hammerspoon console)
```

## The loop: test → write → reload → verify

Don't write speculative Lua straight into `init.lua`. Evaluate it against the live instance
first — it's faster and it can't break the config.

```bash
# 1. Probe / test the snippet against reality
hs -c 'hs.inspect(hs.window.focusedWindow():frame())'
hs -c 'hs.inspect(hs.fnutils.map(hs.screen.allScreens(), function(s) return s:name() end))'

# 2. Syntax-check before touching the live config (see below)

# 3. Write it into hammerspoon/init.lua  (the repo file IS the live config — symlinked)

# 4. Reload
hs -c 'hs.reload()'

# 5. Verify it actually took effect
hs -c 'hs.inspect(configWatcher)'          # e.g. the new object exists
hs -c 'hs.logger.printHistory()'           # and nothing errored on load
```

Step 5 is not optional. A reload that throws leaves you with a **partially loaded** config:
everything before the error ran, everything after it didn't.

## Syntax-check before reloading

A parse error takes down the whole config plus the CLI. Check first — it costs nothing:

```bash
hs -c 'local f, err = loadfile(hs.configdir .. "/init.lua"); return err or "PARSE OK"'
```

`loadfile` only parses — it does **not** execute — so this is safe to run against the live
instance. It catches syntax errors, not runtime ones. Verified working 2026-09-20.

Use this rather than `luac -p`: **`luac` is not installed on this machine** (no system Lua),
and Hammerspoon's own interpreter is the authoritative parser anyway.

## Auto-reload is on, but still reload explicitly

`reload.lua` installs an `hs.pathwatcher` on `hs.configdir` that calls `hs.reload()` when a
`.lua` file changes. So a save usually reloads itself within a second.

Treat that as a convenience for Calum, not as your verification step:

- FSEvents delivery is asynchronous — reading state immediately after a write can race the
  reload and show you the *old* config.
- If the watcher itself was broken by your edit, nothing reloads and the failure is silent.

So: explicit `hs -c 'hs.reload()'`, then verify. If you want to avoid a double reload, just
accept it — reloading twice is harmless.

## Flags worth knowing

| Flag | Effect |
|---|---|
| `-c 'lua'` | Execute a command. Repeatable — runs in order. Implies non-interactive. |
| `/path/to/file.lua` | Execute a file inside the running instance. Path must start `~`, `./` or `/`. |
| `-A` | Auto-launch Hammerspoon if not running (default is to prompt). |
| `-q` | Quiet: only errors and the final result. Good for scripting/parsing. |
| `-n` / `-N` | Force colour off / on. Piped output auto-disables colour. |
| `-t sec` | Send/receive timeout. **Default 4s.** |
| `-C` | Mirror the Hammerspoon Console's `print` output into this terminal. |
| `-P` | Mirror this instance's `print` into the Hammerspoon Console. |
| `-i` | Force interactive REPL (default when no `-c`/file/pipe). |
| `-m name` | Connect to a named port other than `Hammerspoon`. |
| `--` | Stop parsing; remaining args land in `_cli.args`. |

Piping works too: `echo 'hs.reload()' | hs`.

## Gotchas

- **4-second default timeout.** Anything slower — a `hs.task` you wait on, a network call, a
  big `allWindows()` sweep — returns a timeout even though the command may still be running
  inside Hammerspoon. Use `-t 30`, or better, don't block: start the work and poll for the
  result in a later call.
- **Each invocation is its own scope.** `hs -c 'local x = 1'` then `hs -c 'return x'` gives
  `nil`. Use a global if you genuinely need to carry state between calls — and remember a
  reload wipes it.
- **`hs -c` returns the value of an expression.** `hs -c 'hs.window.focusedWindow()'` prints
  a userdata blob; wrap in `hs.inspect()` for tables, or pull specific fields.
- **Ad-hoc state does not persist.** Anything you create via `hs -c` vanishes on the next
  reload. It's for probing and testing, never for "installing" behaviour — that belongs in
  `init.lua`.
- **`hs` needs Hammerspoon actually running.** If it hangs or refuses, check the app is alive
  (`pgrep -x Hammerspoon`) before assuming the config is broken.
- Loading the first extension in a session prints `-- Loading extension: settings` etc. to
  stdout. Benign; filter it if parsing output.

## Useful probes

```bash
hs -c 'hs.inspect(hs.window.focusedWindow():application():name())'
hs -c 'hs.inspect(hs.fnutils.map(hs.application.runningApplications(), function(a) return a:name() end))'
hs -c 'hs.inspect(hs.screen.mainScreen():frame())'
hs -c 'hs.accessibilityState()'                 # false ⇒ permissions problem, not code
hs -c 'hs.inspect(hs.spoons.list())'
hs -c 'hs.logger.printHistory()'                # recent log lines (see hammerspoon-debug)
hs -c 'hs.openConsole()'                        # pop the GUI console when you need eyes on it
```
