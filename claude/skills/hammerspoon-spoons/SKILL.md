---
name: hammerspoon-spoons
description: Use when finding, installing, configuring, or authoring a Hammerspoon Spoon (plugin) — window managers like MiroWindowsManager or PaperWM, utilities like Seal, Caffeine or ClipboardTool, hs.loadSpoon, hs.spoons.use, SpoonInstall, or building a new .spoon from scratch.
---

# Spoons

Spoons are Hammerspoon's plugin format: a self-contained bundle of Lua with a standard
lifecycle, so common automations don't have to be re-implemented in `init.lua`.

Catalog: <https://www.hammerspoon.org/Spoons/> · Source: <https://github.com/Hammerspoon/Spoons>

> **Status on this machine (verified 2026-09-20): no Spoons installed.**
> `~/.hammerspoon/Spoons/` exists but is empty, and `init.lua` calls no `hs.loadSpoon`.
> This skill is forward-looking. Everything below is from the official docs, not from
> established usage in this repo — don't describe any Spoon as "the one Calum uses".

## Anatomy

A Spoon is a directory named `Name.spoon` containing at minimum `init.lua`, which returns a
table carrying standard metadata and methods:

```lua
local obj = {}
obj.__index = obj

obj.name = "MySpoon"
obj.version = "1.0"
obj.author = "Calum <calumpeterwebb@icloud.com>"
obj.homepage = "https://github.com/0x63616c/dotfiles"
obj.license = "MIT - https://opensource.org/licenses/MIT"

function obj:init() end                      -- called by hs.loadSpoon at load
function obj:start() end                     -- begin doing work (start watchers here)
function obj:stop() end                      -- tear down
function obj:bindHotkeys(mapping) end        -- accept user hotkey config

return obj
```

Optional extras in the bundle: `docs.json` (generated API docs) and any resources —
images, sounds, scripts — reached via `hs.spoons.resourcePath("file.png")`.

`hs.spoons.newSpoon(name, basedir, metadata)` scaffolds this skeleton for you; it defaults to
`~/.hammerspoon/Spoons`.

## Installing

Spoons install to **`~/.hammerspoon/Spoons/Name.spoon/`** — which, because `~/.hammerspoon`
is a symlink to this dotfiles repo, means **installing a Spoon writes into the repo**. Decide
deliberately whether it gets committed (vendored, reproducible across machines) or ignored
(machine-local). Vendoring fits this repo's style, but it does mean carrying someone else's
code — say so rather than doing it silently, and add the README row either way.

Manual, which is the transparent option:

```bash
cd /tmp
curl -fsSLO https://github.com/Hammerspoon/Spoons/raw/master/Spoons/Caffeine.spoon.zip
unzip -q Caffeine.spoon.zip -d ~/.hammerspoon/Spoons/
```

(Double-clicking a downloaded `.spoon.zip` also installs it, via Hammerspoon's handler.)

Then in `init.lua`:

```lua
hs.loadSpoon("Caffeine")        -- no ".spoon" suffix
spoon.Caffeine:start()
```

`hs.loadSpoon` puts it at `spoon.Caffeine`. Loading does **not** start it — most Spoons need
an explicit `:start()`.

## Declarative configuration: `hs.spoons.use`

Built in, no extra dependency — load, configure, bind and start in one call:

```lua
hs.spoons.use("Caffeine", {
  config   = { some_setting = true },
  hotkeys  = { toggle = { {"cmd","alt","ctrl"}, "C" } },
  loglevel = "info",
  start    = true,
})
```

`hotkeys = "default"` uses the Spoon's own `defaultHotkeys` spec if it defines one.

Other `hs.spoons` helpers:

| Function | Purpose |
|---|---|
| `hs.spoons.list()` | Installed Spoons: name, loaded state, version. |
| `hs.spoons.isInstalled(name)` / `isLoaded(name)` | Presence checks before acting. |
| `hs.spoons.scriptPath()` | Directory of the calling Spoon. |
| `hs.spoons.resourcePath(rel)` | Absolute path to a bundled resource. |
| `hs.spoons.bindHotkeysToSpec(def, map)` | Standard `bindHotkeys` implementation for authors. |
| `hs.spoons.newSpoon(name, dir, meta)` | Scaffold a new Spoon. |

Probe the live state:

```bash
hs -c 'hs.inspect(hs.spoons.list())'
hs -c 'hs.inspect(hs.spoons.isInstalled("Caffeine"))'
```

## SpoonInstall (auto-install from config)

The `SpoonInstall` Spoon installs other Spoons on demand, so `init.lua` is self-bootstrapping
on a new machine and nothing needs vendoring:

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall:andUse("Caffeine", {
  config  = {},
  hotkeys = { toggle = { {"cmd","alt","ctrl"}, "C" } },
  start   = true,
})
```

`andUse` installs if missing, then loads/configures/starts. Also `asyncInstallSpoonFromRepo(name, repo, cb)`
and `repos` (defaults to the official repo).

**`updateRepo()` is synchronous and blocks all of Hammerspoon while it runs** — don't put a
bare `updateRepo` on the hot path of config load. Prefer the async install. And SpoonInstall
itself still has to be installed by hand first (chicken-and-egg).

Trade-off worth raising with Calum before choosing: `SpoonInstall` keeps the repo clean but
makes startup depend on the network and on upstream still existing; vendoring the `.spoon`
directories is reproducible and offline but adds third-party code to a public repo.

## Notable Spoons from the catalog

**Window management** — `MiroWindowsManager` (halves and corners by keyboard),
`WindowHalfsAndThirds` (half/third-of-screen sizing), `WindowGrid` (grid positioning),
`WindowScreenLeftAndRight` (move between displays), `PaperWM` (scrolling tiling WM, after the
GNOME extension), `WinWin` (general manipulation).

**Utilities** — `Seal` (pluggable launch bar), `ClipboardTool` (clipboard history),
`Caffeine` (prevent sleep), `DeepLTranslate` (translate selection), `Keychain` (credentials),
`SpoonInstall` (the above).

**Input** — `ModalMgr` (modal keybinding environments), `FnMate` (Fn-key navigation),
`InputSourceSwitch` (per-app input method).

Check the catalog page for the current list and each Spoon's own docs before relying on an
API — Spoons are community-maintained and vary in quality and upkeep. Read a Spoon's
`init.lua` before installing it; it runs with full Hammerspoon privileges, which on this
machine includes Accessibility and input tapping.

## Gotchas

- `hs.loadSpoon("X")` takes the name **without** `.spoon`; the directory has it.
- Loading ≠ starting. Most Spoons no-op until `:start()`.
- Spoons are wiped and re-created by `hs.reload()` like everything else — their state doesn't
  persist unless they use `hs.settings`.
- A Spoon that binds hotkeys can silently **shadow** yours (last enabled wins, no error). If a
  binding stops working after adding a Spoon, suspect this first.
- Installing into `~/.hammerspoon/Spoons/` dirties the dotfiles worktree. Commit or ignore
  deliberately; don't leave it as an untracked surprise.
- Spoon quality is uneven and many are unmaintained. For something small, writing 20 lines
  directly in `init.lua` is often better than taking a dependency — the existing config's
  style is self-contained and well-commented, and a Spoon works against that.
