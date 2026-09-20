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
local sonar = require("lib.sonar")
local theme = require("lib.theme")

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


-- notchPath ------------------------------------------------------------------

test("notch flares outward at the top, wider than the card itself", function()
  local segs = geometry.notchPath(400, 600, 0, 88, 18)
  local minx, _, maxx, _ = bounds(segs)
  near(minx, 382, "left flare reaches radius beyond the card")
  near(maxx, 618, "right flare reaches radius beyond the card")
end)

test("notch is exactly card-width at its widest point below the flare", function()
  local segs = geometry.notchPath(400, 600, 0, 88, 18)
  local atSides = 0
  for _, p in ipairs(segs) do
    if math.abs(p.x - 400) < 0.001 or math.abs(p.x - 600) < 0.001 then
      atSides = atSides + 1
    end
  end
  check(atSides >= 4, "sides should run straight at the card's own width")
end)

test("notch never extends past its own bottom", function()
  local _, _, _, maxy = bounds(geometry.notchPath(400, 600, 0, 88, 18))
  check(maxy <= 88.001, "got " .. tostring(maxy))
end)

test("notch has four curves: two flares, two bottom corners", function()
  local curves = 0
  for _, p in ipairs(geometry.notchPath(400, 600, 0, 88, 18)) do
    if p.c1x then curves = curves + 1 end
  end
  eq(curves, 4, "two concave flares + two convex bottom corners")
end)

test("flare and bottom corners share a radius", function()
  -- The left flare spans `r` horizontally; so does the bottom-left corner.
  local segs = geometry.notchPath(400, 600, 0, 88, 18)
  local minx = math.huge
  for _, p in ipairs(segs) do minx = math.min(minx, p.x) end
  near(400 - minx, 18, "flare inset equals the radius")
end)

test("radius clamps on a short card rather than folding through itself", function()
  -- Mid-slide the card is only a few points tall.
  local segs = geometry.notchPath(400, 600, 0, 10, 18)
  local _, miny, _, maxy = bounds(segs)
  check(miny >= -0.001, "must not reach above its own top")
  check(maxy <= 10.001, "must not reach below its own bottom")
end)

test("radius clamps on a narrow card", function()
  local segs = geometry.notchPath(400, 420, 0, 88, 18)
  local minx, _, maxx, _ = bounds(segs)
  check(maxx - minx <= 20 + 2 * 5 + 0.001, "flares can't exceed a quarter-width each")
end)

test("zero-height card degrades to a plain quad", function()
  local segs = geometry.notchPath(400, 600, 0, 0, 18)
  eq(#segs, 4, "no curves possible")
  for _, p in ipairs(segs) do check(p.c1x == nil, "should have no control points") end
end)

test("sliding card keeps its top above the screen edge", function()
  -- top is negative while it slides down out of the edge.
  local segs = geometry.notchPath(400, 600, -60, 28, 18)
  local _, miny, _, maxy = bounds(segs)
  near(miny, -60, "top tracks the slide")
  near(maxy, 28, "bottom tracks the slide")
end)

-- theme --------------------------------------------------------------------
--
-- The tokens are data, so what's worth testing is that they stay usable data:
-- ui.lua hands every colour straight to hs.canvas as {hex=...}, and a typo
-- there is rejected silently, leaving the previous colour in place — the same
-- class of silent failure as the invalid imageScaling in screenshots.lua.

test("every colour is a canvas-ready hex string", function()
  local n = 0
  for name, hex in pairs(theme.color) do
    check(type(hex) == "string", name .. " must be a string")
    check(hex:match("^#%x%x%x%x%x%x$") ~= nil, name .. " must be #rrggbb, got " .. tostring(hex))
    n = n + 1
  end
  check(n > 0, "palette is not empty")
end)

test("alphas are fractions", function()
  for name, a in pairs(theme.alpha) do
    check(type(a) == "number" and a >= 0 and a <= 1, name .. " out of range: " .. tostring(a))
  end
end)

test("radii and sizes are positive numbers", function()
  for _, group in ipairs({ theme.radius, theme.text, theme.space }) do
    for name, v in pairs(group) do
      check(type(v) == "number" and v > 0, name .. " must be a positive number")
    end
  end
end)

test("a control is rounded less than the card that holds it", function()
  -- Not arbitrary: a chip with the card's radius reads as a second card.
  check(theme.radius.control < theme.radius.card, "control radius must be tighter")
end)

test("the type scale is ordered", function()
  check(theme.text.caption < theme.text.body, "caption is the smallest")
  check(theme.text.body <= theme.text.key, "key glyphs are at least body size")
  check(theme.text.key <= theme.text.label, "labels are the largest row text")
end)

test("the shared rings outlast the dictation indicator's", function()
  -- The cheatsheet and library are ambient; dictation.lua's 1.5s is a warning.
  -- If this ever drops back to 1.5 the overlays start flickering, which is the
  -- bug that put this number in a token in the first place.
  check(theme.ring.period > 1.5, "ambient rings must be slower than 1.5s")
  check(theme.ring.peak > 0 and theme.ring.peak < 1, "peak alpha is a fraction")
  check(theme.ring.count >= 2, "one ring doesn't read as a pulse")
end)

-- sonar --------------------------------------------------------------------

local CADENCE = { count = 3, period = 1.5, width = 5, fade = 1.5, distance = 30 }

test("a ring is born at its spawn edge, full width, fully visible", function()
  local r = sonar.ring(0, 1, CADENCE)
  near(r.t, 0, "phase")
  near(r.offset, 0, "has not travelled")
  near(r.width, 5, "full stroke")
  near(r.alpha, 1, "fully visible")
end)

test("a ring travels, thins and fades over its period", function()
  local a = sonar.ring(0.375, 1, CADENCE)   -- a quarter of the way through
  local b = sonar.ring(0.75, 1, CADENCE)    -- halfway
  check(b.offset > a.offset, "keeps travelling")
  check(b.width < a.width, "keeps thinning")
  check(b.alpha < a.alpha, "keeps fading")
  near(b.offset, 15, "halfway is half the distance")
end)

test("the fade outruns the travel, so a ring pulses rather than smears", function()
  -- The bug this guards: a linear fade leaves a ring faintly visible for its
  -- whole trip, which reads as a smear. Alpha must lead the phase.
  local r = sonar.ring(0.75, 1, CADENCE)
  check(r.alpha < 0.5, "halfway through, less than half visible")
end)

test("rings are staggered, never in step", function()
  local seen = {}
  for k = 1, CADENCE.count do
    local t = sonar.phase(0, k, CADENCE)
    for _, other in ipairs(seen) do
      check(math.abs(t - other) > 0.1, "ring phases must not coincide")
    end
    seen[#seen + 1] = t
  end
  eq(#seen, 3, "all three placed")
end)

test("phase wraps into 0..1 and never goes negative", function()
  for _, elapsed in ipairs({ 0, 0.7, 1.5, 4.25, 97.3 }) do
    for k = 1, 3 do
      local t = sonar.phase(elapsed, k, CADENCE)
      check(t >= 0 and t < 1, "phase in range at " .. elapsed .. " ring " .. k)
    end
  end
end)

test("a ring's life repeats exactly one period later", function()
  local a = sonar.ring(0.4, 2, CADENCE)
  local b = sonar.ring(0.4 + CADENCE.period, 2, CADENCE)
  near(b.offset, a.offset, "same travel")
  near(b.alpha, a.alpha, "same alpha")
end)

test("distance is the caller's, so inward and outward share one cadence", function()
  -- dictation.lua sweeps inward a few points; hyper.lua radiates outward 30.
  -- Same phase, different distance: that is the whole shape of the sharing.
  local near_ = { count = 3, period = 1.5, width = 5, fade = 1.5, distance = 8 }
  local far   = { count = 3, period = 1.5, width = 5, fade = 1.5, distance = 80 }
  near(sonar.phase(0.5, 1, near_), sonar.phase(0.5, 1, far), "identical phase")
  near(sonar.ring(0.75, 1, near_).offset, 4, "scales to its own distance")
  near(sonar.ring(0.75, 1, far).offset, 40, "and so does the other")
end)

-- ----------------------------------------------------------------------------

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
