-- Hyper shortcuts -------------------------------------------------------------
--
-- Hyper is Ctrl+Shift+Alt+Gui, held by the Caps key in the QMK firmware
-- (qmk/0x63616c/keymap.c). macOS sees four real modifier flags, not a distinct
-- keycode, so these are ordinary hs.hotkey binds — no Karabiner F18 indirection.
--
-- Bindings go through hyper.bind rather than hs.hotkey.bind directly so each one
-- records what it does. hs.hotkey's own `message` argument can't serve that
-- purpose: it fires an hs.alert on every single press, which is unbearable on a
-- shortcut you use all day. The registry is a plain table instead, read at
-- display time by anything that wants to list the bindings.
--
-- This module RETURNS a table, so other modules register their own shortcuts
-- with `require("hyper").bind(...)`. require resolves on demand and caches, so
-- that works no matter which module init.lua happens to load first — the
-- alphabetical load order is irrelevant here.

local hyper = {}

hyper.mods = { "cmd", "alt", "ctrl", "shift" }

-- Ordered list of { key = "w", label = "Wispr Flow" }, in bind order.
-- Also exposed as a global purely so it can be eyeballed from `hs -c`.
hyper.shortcuts = {}
hyperShortcuts = hyper.shortcuts

function hyper.bind(key, label, fn)
  hyper.shortcuts[#hyper.shortcuts + 1] = { key = key, label = label }
  hs.hotkey.bind(hyper.mods, key, fn)
end

-- Wispr Flow. Launch-or-focus by bundle id rather than by name: the app's
-- on-disk identifier is com.electron.wispr-flow.accessibility-mac-app while the
-- process that actually runs is com.electron.wispr-flow, and a name lookup goes
-- through Spotlight, which this config already refuses to depend on.
hyper.bind("w", "Wispr Flow", function()
  hs.application.launchOrFocusByBundleID("com.electron.wispr-flow")
end)

return hyper
