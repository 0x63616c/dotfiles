-- Test runner for the pure logic under hammerspoon/lib/.
--
-- No LuaRocks, no busted, no Hammerspoon: a new machine needs nothing but the
-- `luajit` already required elsewhere. A dependency you have to install is a
-- dependency the pre-commit hook will one day fail on.
--
--   luajit hammerspoon/tests/run.lua
--
-- Only `hs`-free modules can be tested here. init.lua builds eventtaps and
-- watchers at load time, so it can never be required in a bare interpreter —
-- that is the whole reason lib/ exists.

package.path = "hammerspoon/?.lua;" .. package.path

local passed, failed = 0, 0
local current = "?"

local function check(ok, msg)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.write(string.format("  FAIL  %s: %s\n", current, msg or "assertion failed"))
  end
end

local function eq(got, want, msg)
  check(got == want,
    string.format("%s (got %s, want %s)", msg or "", tostring(got), tostring(want)))
end

local function near(got, want, msg)
  check(type(got) == "number" and math.abs(got - want) < 0.001,
    string.format("%s (got %s, want ~%s)", msg or "", tostring(got), tostring(want)))
end

local function test(name, fn)
  current = name
  local ok, err = pcall(fn)
  if not ok then
    failed = failed + 1
    io.write(string.format("  ERROR %s: %s\n", name, err))
  end
end

local geometry = require("lib.geometry")
local Chord = require("lib.chord")

-- Chord state machine --------------------------------------------------------

local SHIFT      = { shift = true }
local SHIFT_CTRL = { shift = true, ctrl = true }
local HYPER      = { shift = true, ctrl = true, cmd = true, alt = true }
local NONE       = {}

-- Feed a sequence of flag states, 0.05s apart; return how many times it fired.
local function feed(chord, states, gap)
  gap = gap or 0.05
  local fires, t = 0, 0
  for _, s in ipairs(states) do
    t = t + gap
    if chord:flagsChanged(s, t) then fires = fires + 1 end
  end
  return fires
end

test("clean shift+ctrl fires once", function()
  eq(feed(Chord.new(), { SHIFT, SHIFT_CTRL, SHIFT, NONE }), 1, "should fire")
end)

test("ctrl pressed before shift also fires", function()
  eq(feed(Chord.new(), { { ctrl = true }, SHIFT_CTRL, NONE }), 1, "order shouldn't matter")
end)

-- The regression this whole file exists for.
test("hyper does not fire (modifiers arrive one at a time)", function()
  eq(feed(Chord.new(), {
    SHIFT, SHIFT_CTRL, { shift = true, ctrl = true, alt = true },
    HYPER,
    { shift = true, ctrl = true, alt = true }, SHIFT_CTRL, SHIFT, NONE,
  }), 0, "hyper must never toggle media")
end)

test("hyper as a single simultaneous event does not fire", function()
  eq(feed(Chord.new(), { HYPER, NONE }), 0, "no shift+ctrl-only instant at all")
end)

test("repeated hyper presses never fire", function()
  local c = Chord.new()
  local total = 0
  for _ = 1, 5 do
    total = total + feed(c, { SHIFT, SHIFT_CTRL, HYPER, SHIFT_CTRL, NONE })
  end
  eq(total, 0, "state must not leak between presses")
end)

test("ctrl+shift+<key> does not fire", function()
  local c = Chord.new()
  local fires = 0
  if c:flagsChanged(SHIFT, 0.05) then fires = fires + 1 end
  if c:flagsChanged(SHIFT_CTRL, 0.10) then fires = fires + 1 end
  c:keyDown()  -- e.g. Ctrl+Shift+T
  if c:flagsChanged(SHIFT, 0.15) then fires = fires + 1 end
  if c:flagsChanged(NONE, 0.20) then fires = fires + 1 end
  eq(fires, 0, "a keypress disqualifies the chord")
end)

test("holding past maxHold does not fire", function()
  local c = Chord.new({ maxHold = 0.6 })
  c:flagsChanged(SHIFT_CTRL, 0)
  eq(c:flagsChanged(NONE, 5.0), false, "a long rest must not toggle")
end)

test("chord recovers after a dirty press", function()
  local c = Chord.new()
  feed(c, { SHIFT, SHIFT_CTRL, HYPER, NONE })          -- dirty, no fire
  eq(feed(c, { SHIFT, SHIFT_CTRL, NONE }), 1, "next clean chord should fire")
end)

-- formatTime -----------------------------------------------------------------

test("formatTime", function()
  eq(geometry.formatTime(0), "0:00")
  eq(geometry.formatTime(61), "1:01")
  eq(geometry.formatTime(599), "9:59")
  eq(geometry.formatTime(3600), "1:00:00")
  eq(geometry.formatTime(7021.701), "1:57:02")
  eq(geometry.formatTime(nil), nil, "nil in, nil out")
  eq(geometry.formatTime("x"), nil, "non-number in, nil out")
  eq(geometry.formatTime(-5), nil, "negative in, nil out")
  eq(geometry.formatTime(math.huge), nil, "infinite in, nil out")
end)

test("subtitle omits what it doesn't have", function()
  eq(geometry.subtitle("Adam Ten", 2170, 7021), "Adam Ten  ·  36:10 / 1:57:01")
  eq(geometry.subtitle("Adam Ten", nil, nil), "Adam Ten")
  eq(geometry.subtitle("", 2170, 7021), "36:10 / 1:57:01")
  eq(geometry.subtitle("", nil, nil), "", "nothing known -> empty, not junk")
end)

-- marqueeOffset --------------------------------------------------------------

test("short text is centred, not flush left", function()
  near(geometry.marqueeOffset(0, 100, 40), 30, "centred in the window")
  near(geometry.marqueeOffset(99, 100, 40), 30, "and stays put over time")
end)

test("long text holds, scrolls, holds, returns", function()
  local o = { speed = 10, hold = 1 }          -- overflow 50 -> travel 5s
  near(geometry.marqueeOffset(0, 100, 150, o), 0, "holds at the start")
  near(geometry.marqueeOffset(0.9, 100, 150, o), 0, "still holding")
  near(geometry.marqueeOffset(3.5, 100, 150, o), -25, "mid-scroll")
  near(geometry.marqueeOffset(6.0, 100, 150, o), -50, "holds at the end")
  near(geometry.marqueeOffset(6.9, 100, 150, o), -50, "still holding")
  near(geometry.marqueeOffset(9.5, 100, 150, o), -25, "scrolling back")
end)

test("marquee never scrolls past its bounds", function()
  local o = { speed = 10, hold = 1 }
  for i = 0, 400 do
    local x = geometry.marqueeOffset(i * 0.05, 100, 150, o)
    check(x <= 0.001 and x >= -50.001,
      "offset " .. tostring(x) .. " out of range at t=" .. tostring(i * 0.05))
  end
end)

-- ringPath -------------------------------------------------------------------

local function bounds(segs)
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(segs) do
    minx, maxx = math.min(minx, p.x), math.max(maxx, p.x)
    miny, maxy = math.min(miny, p.y), math.max(maxy, p.y)
  end
  return minx, miny, maxx, maxy
end

test("plain ring stays within the screen, inset on all sides", function()
  local segs = geometry.ringPath(1000, 800, 10, nil)
  local minx, miny, maxx, maxy = bounds(segs)
  check(minx >= 10 - 0.001, "left edge respects inset")
  check(miny >= 10 - 0.001, "top edge respects inset")
  check(maxx <= 990 + 0.001, "right edge respects inset")
  check(maxy <= 790 + 0.001, "bottom edge respects inset")
end)

test("notch detour adds points and reaches below the notch", function()
  local notch = { left = 400, right = 600, bottom = 68 }
  local plain = geometry.ringPath(1000, 800, 0, nil)
  local bent = geometry.ringPath(1000, 800, 0, notch)
  check(#bent > #plain, "detour should add segments")
  local _, _, _, maxy = bounds({ unpack and unpack(bent, 1, 10) or bent[1] })
  local reached = false
  for _, p in ipairs(bent) do
    if p.y >= 68 - 0.001 and p.y < 200 then reached = true end
  end
  check(reached, "path should dip to the notch's bottom edge")
end)

test("detour keeps a gap equal to the ring's own inset", function()
  local notch = { left = 400, right = 600, bottom = 68 }
  -- At inset 20 the detour should sit 20pt clear: left side at x = 380.
  local segs = geometry.ringPath(1000, 800, 20, notch)
  local found = false
  for _, p in ipairs(segs) do
    if math.abs(p.x - 380) < 0.001 then found = true end
  end
  check(found, "detour left edge should be notch.left - inset")
end)

test("cramped notch falls back to a plain edge rather than knotting", function()
  -- A notch wider than the screen can't be detoured around sanely.
  local notch = { left = -50, right = 1050, bottom = 68 }
  local segs = geometry.ringPath(1000, 800, 0, notch)
  local plain = geometry.ringPath(1000, 800, 0, nil)
  eq(#segs, #plain, "should degrade to the plain path")
end)

test("rounded join produces curves, not right angles", function()
  local notch = { left = 400, right = 600, bottom = 68 }
  local segs = geometry.ringPath(1000, 800, 0, notch, { joinRadius = 12 })
  local curves = 0
  for _, p in ipairs(segs) do
    if p.c1x then curves = curves + 1 end
  end
  -- 4 screen corners + 2 notch bottom corners + 2 join turns.
  eq(curves, 8, "every corner should be a bezier")
end)

-- ----------------------------------------------------------------------------

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
