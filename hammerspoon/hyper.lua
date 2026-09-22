-- Hyper shortcuts -------------------------------------------------------------
--
-- Hyper is Ctrl+Shift+Alt+Gui, held by the Caps key on every keyboard: hidutil
-- remaps Caps Lock to F18 at login and capslock.lua turns a held F18 into the
-- four flags, replacing the old Hyperkey app (and the QMK board's old
-- hardware Hyper). By the time a keypress gets here macOS sees four real
-- modifier flags, so these are ordinary hs.hotkey binds.
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

-- Hammerspoon's own Console: the log/error window itself, not an app.
hyper.bind("h", "Open Hammerspoon Console", function()
  hs.openConsole()
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

local ui    = require("ui")
local theme = require("lib.theme")

local HOLD_DELAY  = 0.5   -- seconds of holding Hyper before the card appears
local FADE        = 0.14  -- seconds
local FLASH_HOLD  = 0.18  -- how long a pressed key stays lit before the card goes

-- Layout, in points, on the shared spacing scale. The card sizes itself to its
-- contents: the label column is measured from the longest label and the keycaps
-- from the longest key name, so a binding called something long widens the card
-- instead of being clipped.
local PAD         = theme.space.pad
local ROW_H       = theme.space.row
local KEY_H       = 33
local KEY_MIN_W   = 42    -- a single-letter keycap; longer names widen it
local KEY_PAD     = 20    -- keycap padding around its glyph
local KEY_GAP     = 18    -- keycap -> label
local COL_GAP     = 32
local HEADER_H    = 58
local BOTTOM_PAD  = 22
local LABEL_MIN_W = 165
local LABEL_MAX_W = 325
local MAX_ROWS    = 9     -- rows per column before spilling into another

-- Canvas slack around the card: the rings' full travel plus room for the drop
-- shadow, because a canvas clips its own contents.
local SHADOW_PAD  = ui.ringPad(24)

-- Retained: an unreferenced canvas, timer or eventtap is garbage-collected and
-- stops working silently. Same rule as the watchers in dictation.lua.
hyperCard      = nil
hyperHoldTimer = nil
hyperTap       = nil
hyperRingTimer = nil
hyperFlashTimer = nil

-- Set by showCard, read by the key flash: where each row's elements live. The
-- rings keep their own handle, since ui.rings owns their indices.
local hyperRings = nil
local rowElements = {}
-- A key is lit until the card goes. Teardown is then the flash timer's job
-- alone: releasing Hyper right after pressing a key would otherwise hide the
-- card before the lit key had been on screen long enough to see.
local flashing = false

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
  hyperRings = nil
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

-- Light up the pressed key's cap, shadcn-style: the accent colour as the fill
-- with the glyph knocked out of it. Returns false for a key with no binding,
-- which is the caller's cue to just dismiss.
local function flashKey(key)
  local row = rowElements[key]
  if not (row and hyperCard) then return false end
  hyperCard[row.fill].fillColor = ui.accent
  hyperCard[row.stroke].strokeColor = ui.accent
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
    local label = ui.styled(item.label, theme.text.label, ui.fg)
    local glyph = ui.styled(item.key:upper(), theme.text.key, ui.fg,
                            { font = theme.font.semibold, align = "center" })
    rows[#rows + 1] = {
      key = item.key,
      label = label,
      glyph = glyph,
      -- Built now rather than at press time: a keypress should light the cap on
      -- the next frame, not go and lay out text first.
      litGlyph = ui.styled(item.key:upper(), theme.text.key, ui.onAccent,
                           { font = theme.font.semibold, align = "center" }),
    }
    labelW = math.max(labelW, ui.width(label) + 2)
    keyW   = math.max(keyW, ui.width(glyph) + KEY_PAD)
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

  -- Rings first, so the card paints over their inner half and only what has
  -- escaped the edge is seen.
  hyperRings = ui.rings(card, cardFrame)
  card[#card + 1] = ui.surface(cardFrame)
  card[#card + 1] = ui.border(cardFrame)

  card[#card + 1] = ui.text(ui.title("HYPR"),
    { x = O + PAD, y = O + PAD - 4, w = cardW - PAD * 2, h = 18 })
  -- The modifiers themselves, right-aligned on the title row: the card says
  -- what you are holding, so it doubles as a reminder of what Hyper *is*.
  card[#card + 1] = ui.text(ui.styled("⌃ ⌥ ⇧ ⌘", theme.text.key, ui.muted, { align = "right" }),
    { x = O + PAD, y = O + PAD - 6, w = cardW - PAD * 2, h = 20 })
  card[#card + 1] = ui.rule(O + PAD, O + HEADER_H - 14, cardW - PAD * 2)

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
    local capOpts = { radius = theme.radius.control }

    card[#card + 1] = ui.chip(keyFrame, capOpts)
    local fillIdx = #card
    card[#card + 1] = ui.border(keyFrame, { radius = theme.radius.control, color = ui.chipEdge })
    local strokeIdx = #card
    card[#card + 1] = ui.text(row.glyph,
      { x = x, y = keyY + (KEY_H - 18) / 2, w = keyW, h = 20 })
    local glyphIdx = #card
    card[#card + 1] = ui.text(row.label,
      { x = x + keyW + KEY_GAP, y = y + (ROW_H - 18) / 2, w = labelW, h = 20 })

    rowElements[row.key] = {
      fill = fillIdx, stroke = strokeIdx, glyph = glyphIdx, litGlyph = row.litGlyph,
    }
  end

  hyperCard = card
  card:show(FADE)

  local t0 = hs.timer.secondsSinceEpoch()
  hyperRingTimer = hs.timer.doEvery(ui.FRAME_INTERVAL, function()
    if hyperRings then hyperRings.tick(hs.timer.secondsSinceEpoch() - t0) end
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
      -- F18 is the Caps key itself (capslock.lua swallows it, but eventtaps run
      -- newest-first so this one can see it on the way through, and it
      -- autorepeats for as long as Caps is held). It's the modifier, not a
      -- keypress, so it must neither cancel the countdown nor flash a cap.
      if e:getKeyCode() == hs.keycodes.map.f18 then return false end
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
