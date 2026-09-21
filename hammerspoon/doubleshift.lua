-- Both shifts -> Caps Lock ----------------------------------------------------
--
-- Hold one Shift, add the other, and real Caps Lock toggles. This used to live
-- in the QMK firmware (qmk/0x63616c/keymap.c), which meant it only existed on
-- that board and — once the Caps key became F18 via the hidutil remap in
-- capslock.lua — would have sent a keycode that turned into a Hyper tap
-- instead. Doing it here gives every keyboard the same chord and keeps all the
-- Caps-key behaviour in one place.
--
-- Tracked by held state, not by timing: hold left, wait as long as you like,
-- add right, and it fires. Shift still works as Shift throughout — the tap
-- observes and never swallows, so this costs nothing on ordinary typing.
--
-- Left and right Shift are the same bit in getFlags(), so telling them apart
-- needs the raw CGEvent flags, which carry per-device bits:
-- NX_DEVICELSHIFTKEYMASK (0x2) and NX_DEVICERSHIFTKEYMASK (0x4) from
-- IOKit's IOLLEvent.h. The chord is the transition INTO both-down, so holding
-- both and rolling other keys doesn't re-toggle.
--
-- Interplay with the other flagsChanged watchers: the Shift+Ctrl media chord in
-- dictation.lua needs ctrl, and the cheatsheet in hyper.lua needs all four
-- flags, so neither ever sees a bare two-shift state as its own gesture.

local log = hs.logger.new("doubleshift", "info")

local LSHIFT_KEYCODE = 56
local RSHIFT_KEYCODE = 60
local LSHIFT_MASK    = 0x2
local RSHIFT_MASK    = 0x4

local bothDown = false

-- Retained deliberately: an unreferenced eventtap is garbage-collected and
-- stops firing silently.
doubleShiftTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  local code = e:getKeyCode()
  if code ~= LSHIFT_KEYCODE and code ~= RSHIFT_KEYCODE then return false end

  local raw = e:getRawEventData()
  local flags = raw and raw.CGEventData and raw.CGEventData.flags or 0
  local left  = bit.band(flags, LSHIFT_MASK) ~= 0
  local right = bit.band(flags, RSHIFT_MASK) ~= 0
  local now = left and right

  if now and not bothDown then
    hs.hid.capslock.toggle()
    log.i("both shifts -> Caps Lock " .. (hs.hid.capslock.get() and "on" or "off"))
  end
  bothDown = now
  return false
end):start()

log.i("both-shifts Caps Lock chord armed")
