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
hyper.bind("w", "Wispr Flow", function()
  hs.application.launchOrFocusByBundleID("com.electron.wispr-flow")
end)

-- Messages. Bundle id is com.apple.MobileSMS, not com.apple.Messages — a
-- leftover from its iChat/SMS-relay days, and exactly the sort of trap that
-- makes launching by name tempting right up until Spotlight isn't indexing.
hyper.bind("m", "Messages", function()
  hs.application.launchOrFocusByBundleID("com.apple.MobileSMS")
end)

-- Hold-to-reveal cheatsheet ---------------------------------------------------
--
-- Hold Hyper for half a second without pressing anything and a card listing every
-- binding fades in at the top left; press a key or let go and it's gone. The
-- point is that the registry above stops being write-only — a shortcut you
-- can't remember is a shortcut you don't have.
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
local MARGIN      = { x = 32, y = 32 }   -- inset from the top-left corner
local CARD_W      = 280
local ROW_H       = 30
local PAD         = 18
local TITLE_H     = 30
local RADIUS      = 14
local KEY_W       = 30
local FADE        = 0.12  -- seconds

local BG    = { red = 0.07, green = 0.07, blue = 0.09, alpha = 0.94 }
local EDGE  = { red = 1.0,  green = 0.0,  blue = 1.0,  alpha = 0.55 }  -- matches the dictation magenta
local KEYBG = { red = 1.0,  green = 0.0,  blue = 1.0,  alpha = 0.22 }
local TEXT  = { white = 1.0, alpha = 0.95 }
local DIM   = { white = 1.0, alpha = 0.55 }

-- Retained: an unreferenced canvas, timer or eventtap is garbage-collected and
-- stops working silently. Same rule as the watchers in dictation.lua.
hyperCard     = nil
hyperHoldTimer = nil
hyperTap      = nil

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

  -- Same for the screen: read at display time, so moving between displays needs
  -- no rebuild and no screen watcher.
  local frame = hs.screen.mainScreen():frame()
  local height = PAD * 2 + TITLE_H + (#list * ROW_H)

  local card = hs.canvas.new({
    x = frame.x + MARGIN.x,
    y = frame.y + MARGIN.y,
    w = CARD_W,
    h = height,
  })
  card:level(hs.canvas.windowLevels.screenSaver)  -- above fullscreen windows
  card:behavior({ "canJoinAllSpaces", "stationary" })
  card:clickActivating(false)
  card:canvasMouseEvents(false, false, false, false)

  card[#card + 1] = {
    type = "rectangle", action = "fill",
    roundedRectRadii = { xRadius = RADIUS, yRadius = RADIUS },
    fillColor = BG,
  }
  card[#card + 1] = {
    type = "rectangle", action = "stroke",
    roundedRectRadii = { xRadius = RADIUS, yRadius = RADIUS },
    strokeColor = EDGE, strokeWidth = 1.5,
  }
  card[#card + 1] = {
    type = "text", text = "HYPER",
    textColor = DIM, textSize = 11, textFont = "Menlo-Bold",
    frame = { x = PAD, y = PAD - 2, w = CARD_W - PAD * 2, h = 16 },
  }

  for i, item in ipairs(list) do
    local y = PAD + TITLE_H + (i - 1) * ROW_H
    card[#card + 1] = {
      type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = 5, yRadius = 5 },
      fillColor = KEYBG,
      frame = { x = PAD, y = y, w = KEY_W, h = 22 },
    }
    card[#card + 1] = {
      type = "text", text = item.key:upper(),
      textColor = TEXT, textSize = 13, textFont = "Menlo-Bold",
      textAlignment = "center",
      frame = { x = PAD, y = y + 3, w = KEY_W, h = 18 },
    }
    card[#card + 1] = {
      type = "text", text = item.label,
      textColor = TEXT, textSize = 13,
      frame = { x = PAD + KEY_W + 12, y = y + 3, w = CARD_W - PAD * 2 - KEY_W - 12, h = 18 },
    }
  end

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
