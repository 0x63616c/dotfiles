-- Caps Lock -> Hyper ----------------------------------------------------------
--
-- Replaces the Hyperkey app (deleted from the Brewfile): a held Caps Lock is
-- Ctrl+Shift+Alt+Cmd, on every keyboard, entirely in software. The QMK board's
-- Caps key sends plain Caps Lock too (qmk/0x63616c/keymap.c), so both
-- keyboards go through this one path. See hyper.lua for the bindings it feeds.
--
-- Caps Lock itself is never seen here. A hidutil remap (launchagents/
-- com.calum.capslock-f18.plist, applied at login) turns the physical key into
-- F18 before it reaches the OS, and this module watches F18 instead. That
-- indirection is the whole design, and it exists because of how the first
-- version of this file broke:
--
--   Caps Lock is a LATCH to macOS, not a modifier you hold. It arrives as a
--   flagsChanged event whose flags don't carry a capslock bit that
--   getFlags()/setFlags() can read or clear, and the only API that reports it
--   (hs.eventtap.checkKeyboardModifiers) reports the toggle state, which flips
--   on every press and stays put on release. A module that reads "held" from
--   that stamps the four Hyper flags onto every letter you type until the next
--   tap flips it back — which is the symbol storm that took the keyboard out.
--
-- F18 has none of that. It's an ordinary key with a real keyDown and a real
-- keyUp, so "held" is exactly the interval between them and cannot latch.
--
-- Two taps do the work. The first watches F18 alone: on keyDown it swallows
-- the event (so no app ever sees an F18) and posts a synthetic flagsChanged
-- with all four Hyper flags down; on keyUp it posts the matching release.
-- That's what lets hyper.lua's own flagsChanged watch — the hold-to-reveal
-- cheatsheet — recognise a held Caps Lock for free: it just sees a real
-- four-flag-down event. The second tap adds the same four flags to every other
-- keyDown/keyUp while F18 is down, which is what makes
-- hs.hotkey.bind(hyper.mods, ...) fire exactly as if the modifier keys were
-- physically held. The synthetic flagsChanged alone isn't enough for that:
-- posting it doesn't change the hardware modifier state the OS stamps on the
-- next real keypress.
--
-- A lone tap does nothing — no Escape, no literal Caps Lock — matching how the
-- key has always behaved on this machine. Real Caps Lock is the both-shifts
-- chord in doubleshift.lua.
--
-- Recovery if it ever wedges (an F18 keyUp lost mid-hold would leave the
-- flags stamped on everything): `hs -c 'hs.reload()'` resets the held state,
-- and `hidutil property --set '{"UserKeyMapping":[]}'` drops the remap so the
-- key is plain Caps Lock again.

local log = hs.logger.new("capslock", "info")

local F18_KEYCODE = hs.keycodes.map.f18 -- 79
local HYPER_MODS  = { "cmd", "alt", "ctrl", "shift" }

local hyperHeld = false

local function postHyper(down)
  -- A "key event" for a modifier key is a flagsChanged event; the mods table is
  -- the flag state after it.
  hs.eventtap.event.newKeyEvent(down and HYPER_MODS or {}, "cmd", down):post()
end

-- Retained deliberately: an unreferenced eventtap is garbage-collected and
-- stops firing silently, same rule as every other watcher in this config.
capsF18Tap = hs.eventtap.new({
  hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.keyUp,
}, function(e)
  if e:getKeyCode() ~= F18_KEYCODE then return false end

  local down = e:getType() == hs.eventtap.event.types.keyDown
  if down == hyperHeld then return true end -- key autorepeat; still swallow it
  hyperHeld = down
  postHyper(down)
  return true -- nothing downstream should ever see an F18
end):start()

capsKeyTap = hs.eventtap.new({
  hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.keyUp,
}, function(e)
  if not hyperHeld then return false end
  if e:getKeyCode() == F18_KEYCODE then return false end -- capsF18Tap's job
  local flags = e:getFlags()
  flags.cmd, flags.alt, flags.ctrl, flags.shift = true, true, true, true
  e:setFlags(flags)
  return false
end):start()

log.i("Caps Lock (as F18) -> Hyper armed")
