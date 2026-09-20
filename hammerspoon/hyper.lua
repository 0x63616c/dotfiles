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

-- Layout, in points. The card sizes itself to its contents: the label column is
-- measured from the longest label and the keycaps from the longest key name, so
-- a binding called something long widens the card instead of being clipped.
local PAD         = 22    -- card inner padding
local ROW_H       = 34
local KEY_H       = 26
local KEY_MIN_W   = 34    -- a single-letter keycap; longer names widen it
local KEY_PAD     = 16    -- keycap padding around its glyph
local KEY_GAP     = 14    -- keycap -> label
local COL_GAP     = 26
local HEADER_H    = 46
local FOOTER_H    = 30
local RADIUS      = 12   -- shadcn card, rounded-xl
local LABEL_MIN_W = 132
local LABEL_MAX_W = 260
local MAX_ROWS    = 9     -- rows per column before spilling into another
-- Canvas slack around the card. A canvas clips its own contents, so without
-- this the drop shadow would be sliced off flush with the card's edges.
local SHADOW_PAD  = 40

-- ".AppleSystemUIFont" is the system UI face (SF on this machine), and
-- ".AppleSystemUIFaceHeadline" its semibold cut. Neither is in
-- hs.styledtext.fontNames() — the SF family ships as a private system font, not
-- an installed one — but NSFont resolves both by name, which is all canvas
-- needs. Sans rather than mono for the keycaps, matching shadcn's <kbd>.
local FONT_UI  = ".AppleSystemUIFont"
local FONT_KEY = ".AppleSystemUIFaceHeadline"

-- shadcn's dark "zinc" palette, token for token — flat surfaces, one hairline
-- border, and all the hierarchy carried by foreground vs muted-foreground
-- rather than by colour. Deliberately NOT the dictation indicator's magenta:
-- that overlay is a state you need to notice mid-sentence, so it shouts, while
-- this one is a thing you read, so it shouldn't.
local BG        = { hex = "#09090b", alpha = 0.97 }  -- popover
local BORDER    = { hex = "#27272a", alpha = 1.0 }   -- border      (zinc-800)
local KEY_BG    = { hex = "#27272a", alpha = 1.0 }   -- muted       (zinc-800)
local KEY_EDGE  = { hex = "#3f3f46", alpha = 1.0 }   -- zinc-700
local TEXT      = { hex = "#fafafa", alpha = 1.0 }   -- foreground  (zinc-50)
local DIM       = { hex = "#a1a1aa", alpha = 1.0 }   -- muted-fg    (zinc-400)
local RULE      = { hex = "#27272a", alpha = 1.0 }   -- border

-- Retained: an unreferenced canvas, timer or eventtap is garbage-collected and
-- stops working silently. Same rule as the watchers in dictation.lua.
hyperCard     = nil
hyperHoldTimer = nil
hyperTap      = nil

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

local function hideCard()
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
  hideCard()
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
    local label = styled(item.label, 13.5, TEXT)
    local glyph = styled(item.key:upper(), 12.5, TEXT, { font = FONT_KEY, align = "center" })
    rows[#rows + 1] = { label = label, glyph = glyph }
    labelW = math.max(labelW, widthOf(label) + 2)
    keyW   = math.max(keyW, widthOf(glyph) + KEY_PAD)
  end
  labelW = math.min(labelW, LABEL_MAX_W)

  -- Spill into columns rather than growing a tall thin card off the screen.
  local cols   = math.ceil(#rows / MAX_ROWS)
  local perCol = math.ceil(#rows / cols)
  local colW   = keyW + KEY_GAP + labelW
  local cardW  = PAD * 2 + cols * colW + (cols - 1) * COL_GAP
  local cardH  = HEADER_H + perCol * ROW_H + FOOTER_H

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
    text = styled("HYPER", 11, DIM, { kerning = 1.8 }),
    frame = { x = O + PAD, y = O + PAD - 4, w = cardW - PAD * 2, h = 16 },
  }
  -- The modifiers themselves, right-aligned on the title row: the card says
  -- what you are holding, so it doubles as a reminder of what Hyper *is*.
  card[#card + 1] = {
    type = "text",
    text = styled("⌃ ⌥ ⇧ ⌘", 12, DIM, { align = "right" }),
    frame = { x = O + PAD, y = O + PAD - 6, w = cardW - PAD * 2, h = 18 },
  }
  card[#card + 1] = {
    type = "segments", action = "stroke",
    coordinates = {
      { x = O + PAD, y = O + HEADER_H - 10 },
      { x = O + cardW - PAD, y = O + HEADER_H - 10 },
    },
    strokeColor = RULE, strokeWidth = 1,
  }

  for i, row in ipairs(rows) do
    local col = math.floor((i - 1) / perCol)
    local x   = O + PAD + col * (colW + COL_GAP)
    local y   = O + HEADER_H + ((i - 1) % perCol) * ROW_H
    local keyY = y + (ROW_H - KEY_H) / 2
    local keyFrame = { x = x, y = keyY, w = keyW, h = KEY_H }
    local keyRadii = { xRadius = 6, yRadius = 6 }  -- shadcn kbd, rounded-md

    card[#card + 1] = {
      type = "rectangle", action = "fill",
      frame = keyFrame, roundedRectRadii = keyRadii,
      fillColor = KEY_BG,
    }
    card[#card + 1] = {
      type = "rectangle", action = "stroke",
      frame = keyFrame, roundedRectRadii = keyRadii,
      strokeColor = KEY_EDGE, strokeWidth = 1,
    }
    card[#card + 1] = {
      type = "text", text = row.glyph,
      frame = { x = x, y = keyY + (KEY_H - 16) / 2, w = keyW, h = 18 },
    }
    card[#card + 1] = {
      type = "text", text = row.label,
      frame = { x = x + keyW + KEY_GAP, y = y + (ROW_H - 16) / 2, w = labelW, h = 18 },
    }
  end

  card[#card + 1] = {
    type = "text",
    text = styled("keep holding to read · press a key to run it", 10.5, DIM, { align = "center" }),
    frame = { x = O, y = O + cardH - FOOTER_H + 8, w = cardW, h = 16 },
  }

  hyperCard = card
  card:show(FADE)
end

-- Exposed for debugging: `hs -c 'require("hyper").showCard()'` renders the card
-- without having to hold the keys down.
hyper.showCard = showCard
hyper.hideCard = hideCard

local function isHyperHeld(f)
  return f.cmd and f.alt and f.ctrl and f.shift
end

hyperTap = hs.eventtap.new(
  { hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown },
  function(e)
    if e:getType() == hs.eventtap.event.types.keyDown then
      -- A real keypress means Hyper was a prefix, not a gesture. This is what
      -- keeps Hyper+W from flashing the card on its way to launching Wispr.
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
