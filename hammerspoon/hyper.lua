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
-- display time by the cheatsheet below.
--
-- This module RETURNS a table, so other modules register their own shortcuts
-- with `require("hyper").bind(...)`. require resolves on demand and caches, so
-- that works no matter which module init.lua happens to load first — the
-- alphabetical load order is irrelevant here.

local hyper = {}

hyper.mods = { "cmd", "alt", "ctrl", "shift" }

-- List of { key = "w", label = "Wispr Flow" }. Also exposed as a global purely
-- so it can be eyeballed from `hs -c`.
hyper.shortcuts = {}
hyperShortcuts = hyper.shortcuts

-- The ONLY way to add a Hyper binding. Registering and binding are the same
-- call on purpose: there is no path that binds a key without it showing up on
-- the cheatsheet, so a new shortcut can't be added and then forgotten about.
-- The label is required for the same reason — an unlabelled row would be a
-- shortcut you still can't remember, so a missing one is a hard error at load
-- rather than a blank line on the card.
function hyper.bind(key, label, fn)
  assert(type(key) == "string" and key ~= "", "hyper.bind: key must be a non-empty string")
  assert(type(label) == "string" and label ~= "", "hyper.bind: every Hyper binding needs a label for the cheatsheet (key: " .. tostring(key) .. ")")
  assert(type(fn) == "function", "hyper.bind: fn must be a function (key: " .. tostring(key) .. ")")
  hyper.shortcuts[#hyper.shortcuts + 1] = { key = key, label = label }
  hs.hotkey.bind(hyper.mods, key, fn)
end

-- Bindings --------------------------------------------------------------------

-- Wispr Flow. Launch-or-focus by bundle id rather than by name: the app's
-- on-disk identifier is com.electron.wispr-flow.accessibility-mac-app while the
-- process that actually runs is com.electron.wispr-flow, and a name lookup goes
-- through Spotlight, which this config already refuses to depend on.
hyper.bind("w", "Open Wispr Flow", function()
  hs.application.launchOrFocusByBundleID("com.electron.wispr-flow")
end)

-- Messages. Bundle id is com.apple.MobileSMS, not com.apple.Messages — a
-- leftover from its iChat/SMS-relay days, and exactly the sort of trap that
-- makes launching by name tempting right up until Spotlight isn't indexing.
hyper.bind("m", "Open Messages", function()
  hs.application.launchOrFocusByBundleID("com.apple.MobileSMS")
end)

-- Hold-to-reveal cheatsheet ---------------------------------------------------
--
-- Hold Hyper for half a second without pressing anything and a card listing every
-- binding fades in over the middle of the screen; press a key or let go and
-- it's gone. The point is that the registry above stops being write-only — a
-- shortcut you can't remember is a shortcut you don't have.
--
-- hs.hotkey can't bind bare modifiers (it needs a key), so this comes off a
-- flagsChanged eventtap, same as the Shift+Ctrl chord in dictation.lua. It also
-- taps keyDown, which is the heavyweight kind of tap and may want Input
-- Monitoring on top of Accessibility — dictation.lua already taps keyDown, so
-- the permission is in place.
--
-- The guard that matters is the keyDown one: Hyper+W must show nothing. A real
-- keypress means the modifiers were a prefix, not a gesture, so it cancels the
-- countdown outright. Everything else falls out of matching the full four-flag
-- state — no transient-state problem here, unlike the Shift+Ctrl chord, because
-- all four flags being set at once is unambiguous.
--
-- The callback returns false always: this observes input, it never swallows it,
-- so the bindings above still fire normally with the card on screen.
--
-- Built fresh on each show and torn down on hide, rather than kept around
-- hidden. It appears rarely and briefly, so there's nothing to gain from
-- holding a canvas (and a stale one would survive a screen change).

local HOLD_DELAY  = 0.5   -- seconds of holding Hyper before the card appears
local FADE        = 0.14  -- seconds
local FLASH_HOLD  = 0.18  -- how long a pressed key stays lit before the card goes

-- Layout, in points. The card sizes itself to its contents: the label column is
-- measured from the longest label and the keycaps from the longest key name, so
-- a binding called something long widens the card instead of being clipped.
local PAD         = 28    -- card inner padding
local ROW_H       = 42
local KEY_H       = 33
local KEY_MIN_W   = 42    -- a single-letter keycap; longer names widen it
local KEY_PAD     = 20    -- keycap padding around its glyph
local KEY_GAP     = 18    -- keycap -> label
local COL_GAP     = 32
local HEADER_H    = 58
local BOTTOM_PAD  = 22
local RADIUS      = 15    -- shadcn card, rounded-xl
local KEY_RADIUS  = 8     -- shadcn kbd, rounded-md
local LABEL_MIN_W = 165
local LABEL_MAX_W = 325
local MAX_ROWS    = 9     -- rows per column before spilling into another

local SIZE_TITLE  = 12
local SIZE_MODS   = 14
local SIZE_LABEL  = 15
local SIZE_KEY    = 14

-- Radiating rings, the same gesture as the dictation indicator's — outward from
-- the card here, inward from the screen edge there. The cadence itself lives in
-- lib/sonar.lua so the two can't drift apart; only the direction, the colour and
-- the path are this module's business.
--
-- White rather than that indicator's magenta: magenta on this card would put a
-- colour back that the shadcn palette below deliberately removed.
local RING_COUNT     = 3
-- Much slower than the dictation indicator's 1.5s, and deliberately so: that
-- one is a live-mic warning that has to register at a glance, this one is
-- ambient while you read a list. At 1.5s over this travel it read as flickering.
local RING_PERIOD    = 3.2   -- seconds for one ring: card edge -> faded out
local RING_DISTANCE  = 30    -- how far out it gets, points
local RING_WIDTH     = 5     -- stroke at spawn; thins as it travels
local RING_FADE      = 1.7   -- >1 makes the ring die away sooner
local RING_PEAK      = 0.45  -- alpha at spawn; white is loud
local FRAME_INTERVAL = 1 / 30

local RING_CADENCE = {
  count = RING_COUNT, period = RING_PERIOD,
  width = RING_WIDTH, fade = RING_FADE, distance = RING_DISTANCE,
}

-- Canvas slack around the card. A canvas clips its own contents, so without
-- this the rings and the drop shadow would be sliced off flush with the card's
-- edges. It has to clear the furthest a ring travels plus its own stroke.
local SHADOW_PAD  = RING_DISTANCE + RING_WIDTH + 24

-- ".AppleSystemUIFont" is the system UI face (SF on this machine), and
-- ".AppleSystemUIFaceHeadline" its semibold cut. Neither is in
-- hs.styledtext.fontNames() — the SF family ships as a private system font, not
-- an installed one — but NSFont resolves both by name, which is all canvas
-- needs. Sans rather than mono for the keycaps, matching shadcn's <kbd>.
local FONT_UI  = ".AppleSystemUIFont"
local FONT_KEY = ".AppleSystemUIFaceHeadline"

-- shadcn's dark "zinc" palette, token for token — flat surfaces, one hairline
-- border, and all the hierarchy carried by foreground vs muted-foreground
-- rather than by colour.
local BG        = { hex = "#09090b", alpha = 0.97 }  -- popover
local BG_SOLID  = { hex = "#09090b", alpha = 1.0 }   -- glyph on a lit keycap
local BORDER    = { hex = "#27272a", alpha = 1.0 }   -- border      (zinc-800)
local KEY_BG    = { hex = "#27272a", alpha = 1.0 }   -- muted       (zinc-800)
local KEY_EDGE  = { hex = "#3f3f46", alpha = 1.0 }   -- zinc-700
local KEY_LIT   = { hex = "#fafafa", alpha = 1.0 }   -- a pressed keycap
local TEXT      = { hex = "#fafafa", alpha = 1.0 }   -- foreground  (zinc-50)
local DIM       = { hex = "#a1a1aa", alpha = 1.0 }   -- muted-fg    (zinc-400)
local RULE      = { hex = "#27272a", alpha = 1.0 }   -- border
local RING_HEX  = "#fafafa"                          -- alpha is per-frame

local sonar = require("lib.sonar")

-- Retained: an unreferenced canvas, timer or eventtap is garbage-collected and
-- stops working silently. Same rule as the watchers in dictation.lua.
hyperCard      = nil
hyperHoldTimer = nil
hyperTap       = nil
hyperRingTimer = nil
hyperFlashTimer = nil

-- Set by showCard, read by the ring tick and the key flash. The card's own
-- frame in canvas coordinates, and where each row's elements live.
local cardGeom = nil
local rowElements = {}
-- A key is lit until the card goes. Teardown is then the flash timer's job
-- alone: releasing Hyper right after pressing a key would otherwise hide the
-- card before the lit key had been on screen long enough to see.
local flashing = false

-- Text is built as styledtext rather than passed as a bare string so it can be
-- measured before the canvas exists — the card's width depends on it — and so
-- kerning and alignment are available, which canvas's plain text attributes
-- don't offer.
local function styled(text, size, color, opts)
  opts = opts or {}
  local attrs = {
    font  = { name = opts.font or FONT_UI, size = size },
    color = color,
  }
  if opts.kerning then attrs.kerning = opts.kerning end
  if opts.align then attrs.paragraphStyle = { alignment = opts.align } end
  return hs.styledtext.new(text, attrs)
end

local function widthOf(st)
  local size = hs.drawing.getTextDrawingSize(st)
  return size and size.w or 0
end

local function stopRings()
  if hyperRingTimer then
    hyperRingTimer:stop()
    hyperRingTimer = nil
  end
end

local function hideCard()
  stopRings()
  if hyperFlashTimer then
    hyperFlashTimer:stop()
    hyperFlashTimer = nil
  end
  flashing = false
  rowElements = {}
  cardGeom = nil
  if hyperCard then
    hyperCard:delete(FADE)
    hyperCard = nil
  end
end

local function cancelHold()
  if hyperHoldTimer then
    hyperHoldTimer:stop()
    hyperHoldTimer = nil
  end
  if flashing then return end
  hideCard()
end

-- One frame of the rings: concentric rounded rectangles stepping outward from
-- the card's own edge, each keeping the card's corner profile so they read as
-- the card pulsing rather than as circles behind it. They are the canvas's
-- first elements, so the opaque card covers their inner half and only the part
-- that has escaped the edge is ever seen.
local function tickRings(elapsed)
  if not (hyperCard and cardGeom) then return end
  for k = 1, RING_COUNT do
    local r = sonar.ring(elapsed, k, RING_CADENCE)
    local el = hyperCard[k]
    if not el then return end
    el.action = "stroke"
    el.strokeWidth = r.width
    el.strokeColor = { hex = RING_HEX, alpha = r.alpha * RING_PEAK }
    el.frame = {
      x = cardGeom.x - r.offset,
      y = cardGeom.y - r.offset,
      w = cardGeom.w + r.offset * 2,
      h = cardGeom.h + r.offset * 2,
    }
    el.roundedRectRadii = { xRadius = RADIUS + r.offset, yRadius = RADIUS + r.offset }
  end
end

-- Light up the pressed key's cap, shadcn-style: the accent colour as the fill
-- with the glyph knocked out of it. Returns false for a key with no binding,
-- which is the caller's cue to just dismiss.
local function flashKey(key)
  local row = rowElements[key]
  if not (row and hyperCard) then return false end
  hyperCard[row.fill].fillColor = KEY_LIT
  hyperCard[row.stroke].strokeColor = KEY_LIT
  hyperCard[row.glyph].text = row.litGlyph
  return true
end

local function showCard()
  hideCard()
  -- Read the registry at display time, so a binding registered by any module —
  -- including ones that load after this one — is on the card without wiring.
  -- Sorted by key rather than left in bind order: bind order is really module
  -- load order, so an alphabetically-later module would otherwise shuffle the
  -- rows around under you.
  local list = {}
  for i, item in ipairs(hyper.shortcuts) do list[i] = item end
  table.sort(list, function(a, b) return a.key < b.key end)
  if #list == 0 then return end

  -- Style and measure every row up front. The registry entries themselves are
  -- never touched: they belong to whichever module registered them.
  local rows, labelW, keyW = {}, LABEL_MIN_W, KEY_MIN_W
  for _, item in ipairs(list) do
    local label = styled(item.label, SIZE_LABEL, TEXT)
    local glyph = styled(item.key:upper(), SIZE_KEY, TEXT, { font = FONT_KEY, align = "center" })
    rows[#rows + 1] = {
      key = item.key,
      label = label,
      glyph = glyph,
      -- Built now rather than at press time: a keypress should light the cap on
      -- the next frame, not go and lay out text first.
      litGlyph = styled(item.key:upper(), SIZE_KEY, BG_SOLID, { font = FONT_KEY, align = "center" }),
    }
    labelW = math.max(labelW, widthOf(label) + 2)
    keyW   = math.max(keyW, widthOf(glyph) + KEY_PAD)
  end
  labelW = math.min(labelW, LABEL_MAX_W)

  -- Spill into columns rather than growing a tall thin card off the screen.
  local cols   = math.ceil(#rows / MAX_ROWS)
  local perCol = math.ceil(#rows / cols)
  local colW   = keyW + KEY_GAP + labelW
  local cardW  = PAD * 2 + cols * colW + (cols - 1) * COL_GAP
  local cardH  = HEADER_H + perCol * ROW_H + BOTTOM_PAD

  -- Same as the registry: read the screen at display time, so moving between
  -- displays needs no rebuild and no screen watcher.
  local frame = hs.screen.mainScreen():frame()
  local canvasW, canvasH = cardW + SHADOW_PAD * 2, cardH + SHADOW_PAD * 2
  local card = hs.canvas.new({
    x = frame.x + math.floor((frame.w - canvasW) / 2),
    -- A third of the way down, not halfway: optically centred beats
    -- mathematically centred, and it keeps clear of whatever is mid-screen.
    y = frame.y + math.floor((frame.h - canvasH) * 0.33),
    w = canvasW,
    h = canvasH,
  })
  card:level(hs.canvas.windowLevels.screenSaver)  -- above fullscreen windows
  card:behavior({ "canJoinAllSpaces", "stationary" })
  card:clickActivating(false)
  card:canvasMouseEvents(false, false, false, false)

  local O = SHADOW_PAD  -- every frame below is in canvas space, card-inset
  local cardFrame = { x = O, y = O, w = cardW, h = cardH }
  local radii     = { xRadius = RADIUS, yRadius = RADIUS }
  cardGeom = cardFrame

  -- Rings first, so the card is painted over their inner half. The tick owns
  -- their frame and colour; these are just placeholders of the right shape.
  for k = 1, RING_COUNT do
    card[k] = {
      type = "rectangle", action = "skip",
      frame = cardFrame, roundedRectRadii = radii,
      strokeWidth = RING_WIDTH, strokeColor = { hex = RING_HEX, alpha = 0 },
    }
  end

  -- Flat fill, one hairline border, one soft shadow — shadcn's card, and the
  -- reason there's no gradient or inner highlight here: those read as chrome,
  -- and the point of this surface is that you look straight past it at the rows.
  card[#card + 1] = {
    type = "rectangle", action = "fill",
    frame = cardFrame, roundedRectRadii = radii,
    fillColor = BG,
    withShadow = true,
    shadow = { blurRadius = 26, color = { alpha = 0.5 }, offset = { h = 10, w = 0 } },
  }
  card[#card + 1] = {
    type = "rectangle", action = "stroke",
    frame = cardFrame, roundedRectRadii = radii,
    strokeColor = BORDER, strokeWidth = 1,
  }

  card[#card + 1] = {
    type = "text",
    text = styled("HYPR", SIZE_TITLE, DIM, { kerning = 1.8 }),
    frame = { x = O + PAD, y = O + PAD - 4, w = cardW - PAD * 2, h = 18 },
  }
  -- The modifiers themselves, right-aligned on the title row: the card says
  -- what you are holding, so it doubles as a reminder of what Hyper *is*.
  card[#card + 1] = {
    type = "text",
    text = styled("⌃ ⌥ ⇧ ⌘", SIZE_MODS, DIM, { align = "right" }),
    frame = { x = O + PAD, y = O + PAD - 6, w = cardW - PAD * 2, h = 20 },
  }
  card[#card + 1] = {
    type = "segments", action = "stroke",
    coordinates = {
      { x = O + PAD, y = O + HEADER_H - 14 },
      { x = O + cardW - PAD, y = O + HEADER_H - 14 },
    },
    strokeColor = RULE, strokeWidth = 1,
  }

  -- Element indices are recorded per row rather than derived from a base, so a
  -- new element anywhere above can't silently point the key flash at the wrong
  -- thing.
  rowElements = {}
  for i, row in ipairs(rows) do
    local col = math.floor((i - 1) / perCol)
    local x   = O + PAD + col * (colW + COL_GAP)
    local y   = O + HEADER_H + ((i - 1) % perCol) * ROW_H
    local keyY = y + (ROW_H - KEY_H) / 2
    local keyFrame = { x = x, y = keyY, w = keyW, h = KEY_H }
    local keyRadii = { xRadius = KEY_RADIUS, yRadius = KEY_RADIUS }

    card[#card + 1] = {
      type = "rectangle", action = "fill",
      frame = keyFrame, roundedRectRadii = keyRadii,
      fillColor = KEY_BG,
    }
    local fillIdx = #card
    card[#card + 1] = {
      type = "rectangle", action = "stroke",
      frame = keyFrame, roundedRectRadii = keyRadii,
      strokeColor = KEY_EDGE, strokeWidth = 1,
    }
    local strokeIdx = #card
    card[#card + 1] = {
      type = "text", text = row.glyph,
      frame = { x = x, y = keyY + (KEY_H - 18) / 2, w = keyW, h = 20 },
    }
    local glyphIdx = #card
    card[#card + 1] = {
      type = "text", text = row.label,
      frame = { x = x + keyW + KEY_GAP, y = y + (ROW_H - 18) / 2, w = labelW, h = 20 },
    }

    rowElements[row.key] = {
      fill = fillIdx, stroke = strokeIdx, glyph = glyphIdx, litGlyph = row.litGlyph,
    }
  end

  hyperCard = card
  card:show(FADE)

  local t0 = hs.timer.secondsSinceEpoch()
  hyperRingTimer = hs.timer.doEvery(FRAME_INTERVAL, function()
    tickRings(hs.timer.secondsSinceEpoch() - t0)
  end)
end

-- Exposed for debugging: `hs -c 'require("hyper").showCard()'` renders the card
-- without having to hold the keys down, and `.flashKey("w")` lights a cap
-- without a keypress — which is the only way to see that state, since a real
-- press dismisses the card 0.18s later.
hyper.showCard = showCard
hyper.hideCard = hideCard
hyper.flashKey = flashKey

local function isHyperHeld(f)
  return f.cmd and f.alt and f.ctrl and f.shift
end

hyperTap = hs.eventtap.new(
  { hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown },
  function(e)
    if e:getType() == hs.eventtap.event.types.keyDown then
      -- With the card up, a keypress is you using it: light that key's cap for
      -- a moment so you see which binding you just fired, then let the card go.
      -- Matched on the keycode rather than the event's characters, because with
      -- all four modifiers down the characters are whatever the layout makes of
      -- Hyper+W, not "w".
      if hyperCard and not flashing then
        local key = hs.keycodes.map[e:getKeyCode()]
        if type(key) == "string" and flashKey(key) then
          -- Rings stop so the lit key is what moves. The flash timer owns the
          -- teardown from here; cancelHold defers to it.
          stopRings()
          flashing = true
          hyperFlashTimer = hs.timer.doAfter(FLASH_HOLD, function()
            hyperFlashTimer = nil
            flashing = false
            hideCard()
          end)
          return false
        end
      end
      -- Otherwise a real keypress means Hyper was a prefix, not a gesture. This
      -- is what keeps Hyper+W from flashing the card on its way to launching
      -- Wispr during the hold countdown.
      cancelHold()
      return false
    end

    if isHyperHeld(e:getFlags()) then
      if not hyperHoldTimer and not hyperCard then
        hyperHoldTimer = hs.timer.doAfter(HOLD_DELAY, function()
          hyperHoldTimer = nil
          showCard()
        end)
      end
    else
      cancelHold()
    end
    return false
  end):start()

return hyper
