-- The Shift+Ctrl chord state machine.
--
-- Pure: no `hs.*`, no timers, no side effects. Flag states and a clock go in,
-- "fire now" comes out — which is what makes it testable without a keyboard.
-- The eventtap that feeds it lives in init.lua.
--
-- The hard part isn't detecting the chord, it's *not* firing on everything else
-- that passes through the same flag state:
--
--   * every Ctrl+Shift+<key> shortcut (Ctrl+Shift+T, Ctrl+Shift+Tab, ...);
--   * the Hyper key. Hyper is cmd+alt+ctrl+shift, and when those modifiers hit
--     the wire one at a time there is a transient instant where the flags are
--     *exactly* shift+ctrl — on the way down and again on the way up. Matching
--     on the instantaneous state fires on every Hyper press.
--
-- So `dirty` is sticky: once anything disqualifies the chord it stays
-- disqualified until every modifier is released, and the toggle fires only when
-- the flags reach empty. A Hyper press dirties itself the moment cmd or alt
-- appears, and cannot re-arm on the way back down because the flags never went
-- empty in between.

local M = {}
M.__index = M

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    maxHold = opts.maxHold or 0.6,
    armed = false,
    dirty = false,
    held = false,
    since = 0,
  }, M)
end

local function isEmpty(f)
  return not (f.shift or f.ctrl or f.cmd or f.alt or f.fn)
end

local function isExactlyShiftCtrl(f)
  return f.shift and f.ctrl and not f.cmd and not f.alt and not f.fn
end

-- A real keypress or click means the modifiers were held *for* that input, not
-- pressed as a command of their own, so it disqualifies the chord.
--
-- Only while a modifier is actually down. Input with no modifiers held has
-- nothing to do with any chord, and dirtying on it silently ate the *next*
-- chord: nothing clears `dirty` until the flags reach empty, and a bare
-- keystroke never changes the flags at all. So typing a word and then reaching
-- for shift+ctrl did nothing the first time and worked the second.
function M:keyDown()
  if self.held then self.dirty = true end
end

-- Returns true exactly once: on the release that completes a clean chord.
function M:flagsChanged(flags, now)
  -- Whether any modifier is down right now; keyDown() is only meaningful then.
  self.held = not isEmpty(flags)

  if isEmpty(flags) then
    local fire = self.armed
             and not self.dirty
             and (now - self.since) <= self.maxHold
    self.armed = false
    self.dirty = false
    return fire == true
  end

  if flags.cmd or flags.alt or flags.fn then
    -- Hyper, or anything else merely passing through shift+ctrl.
    self.dirty = true
    self.armed = false
  elseif isExactlyShiftCtrl(flags) and not self.dirty and not self.armed then
    self.armed = true
    self.since = now
  end

  return false
end

return M
