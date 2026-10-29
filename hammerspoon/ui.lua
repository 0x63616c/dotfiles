-- The canvas component library: the handful of shapes every overlay in this
-- config is built from — a surface, a hairline, a recessed chip, a line of
-- text, a set of radiating rings.
--
-- Why this exists: the Hyper cheatsheet and the screenshot library are two
-- windows the same person opens with two fingers of the same hand, seconds
-- apart. They have to look like one program. That only stays true if "a card"
-- is a function rather than a convention, so a change to the shadow or the
-- border lands in both without anyone remembering to go and do it.
--
-- Split from lib/theme.lua on the hs boundary: the tokens are pure data and
-- live in lib/ where the tests can reach them, while everything here needs
-- hs.canvas, hs.styledtext or hs.drawing. Keep the split — the moment a token
-- needs `hs`, it isn't a token.
--
-- This is a library, not a feature: it binds nothing and watches nothing. It
-- sits at the top level because init.lua's loader only picks up top-level .lua,
-- and because that is already how hyper.lua is consumed — require it and use
-- the table it returns. Loading it twice is free; require caches.
--
-- Builders return element tables for the caller to append, rather than taking
-- the canvas themselves. The caller then owns element order and ids, which both
-- of them care about: the cheatsheet paints its rings under the card, and the
-- library addresses tiles by id from its mouse callback.

local theme = require("lib.theme")
local sonar = require("lib.sonar")

local ui = {}
ui.theme = theme

-- Tokens -> canvas colours. hs.canvas takes {hex=..., alpha=...} directly, so
-- this is mostly about the alpha being a separate argument at the call site.
function ui.color(hex, alpha)
  return { hex = hex, alpha = alpha or 1.0 }
end

local C = theme.color

-- Named shorthands for the colours used often enough that spelling out
-- ui.color(theme.color.x) at every call site would bury the layout.
ui.fg      = ui.color(C.foreground)
ui.muted   = ui.color(C.mutedForeground)
ui.surfaceColor = ui.color(C.popover, theme.alpha.surface)
ui.borderColor  = ui.color(C.border)
ui.chipColor    = ui.color(C.muted)
ui.chipEdge     = ui.color(C.mutedEdge)
ui.accent       = ui.color(C.accent)
ui.onAccent     = ui.color(C.popover)   -- text knocked out of an accent fill

-- Text ------------------------------------------------------------------------
--
-- styledtext rather than canvas's plain text attributes, for two reasons: it
-- can be measured before any canvas exists (both windows size themselves to
-- their content), and it carries kerning and alignment, which the plain
-- attributes don't.

function ui.styled(text, size, color, opts)
  opts = opts or {}
  local attrs = {
    font  = { name = opts.font or theme.font.ui, size = size or theme.text.body },
    color = color or ui.fg,
  }
  if opts.kerning then attrs.kerning = opts.kerning end
  if opts.align then attrs.paragraphStyle = { alignment = opts.align } end
  return hs.styledtext.new(text, attrs)
end

function ui.width(st)
  local size = hs.drawing.getTextDrawingSize(st)
  return size and size.w or 0
end

function ui.text(st, frame, id)
  return { type = "text", text = st, frame = frame, id = id }
end

-- The small tracked-out label at the top of a card. Tracking is what makes
-- eleven points of muted grey read as a heading rather than as small print.
function ui.title(text)
  return ui.styled(text, theme.text.title, ui.muted, { kerning = 1.8 })
end

-- Surfaces ---------------------------------------------------------------------

-- A card: flat fill, one soft shadow. No gradient and no inner highlight —
-- those read as chrome, and the point of a surface is that you look straight
-- past it at what's on it.
function ui.surface(frame, opts)
  opts = opts or {}
  local r = opts.radius or theme.radius.card
  local el = {
    type = "rectangle", action = "fill",
    frame = frame,
    roundedRectRadii = { xRadius = r, yRadius = r },
    fillColor = opts.color or ui.surfaceColor,
  }
  if opts.shadow ~= false then
    el.withShadow = true
    el.shadow = {
      blurRadius = theme.shadow.blur,
      color = { alpha = theme.shadow.alpha },
      offset = { h = theme.shadow.dy, w = 0 },
    }
  end
  return el
end

function ui.border(frame, opts)
  opts = opts or {}
  local r = opts.radius or theme.radius.card
  return {
    type = "rectangle", action = "stroke",
    frame = frame,
    roundedRectRadii = { xRadius = r, yRadius = r },
    strokeColor = opts.color or ui.borderColor,
    strokeWidth = opts.width or 1,
    id = opts.id,
  }
end

-- A recessed chip: a keycap on the cheatsheet, a tile behind a thumbnail in the
-- library. Same token, same radius, so they're recognisably the same thing.
function ui.chip(frame, opts)
  opts = opts or {}
  local r = opts.radius or theme.radius.control
  return {
    type = "rectangle", action = "fill",
    frame = frame,
    roundedRectRadii = { xRadius = r, yRadius = r },
    fillColor = opts.color or ui.chipColor,
    id = opts.id,
  }
end

-- A hairline separator, in the same colour as every border.
function ui.rule(x, y, w)
  return {
    type = "segments", action = "stroke",
    coordinates = { { x = x, y = y }, { x = x + w, y = y } },
    strokeColor = ui.borderColor, strokeWidth = 1,
  }
end

-- The dimmed backdrop behind a modal window. Carries trackMouseDown so the
-- caller can dismiss on a click outside.
function ui.backdrop(id)
  return {
    type = "rectangle", action = "fill",
    fillColor = ui.color(C.backdrop, theme.alpha.backdrop),
    trackMouseDown = true, id = id or "backdrop",
  }
end

-- Radiating rings ---------------------------------------------------------------
--
-- Concentric rounded rectangles stepping outward from a surface's own edge,
-- each keeping that surface's corner profile so they read as the card pulsing
-- rather than as shapes behind it. The cadence is lib/sonar.lua, shared with
-- the dictation indicator so the two pulse as one gesture.
--
-- Appends its placeholders at the canvas's current end and returns a handle
-- with the base index and a tick. Append them BEFORE the surface: the opaque
-- card then paints over their inner half, and only the part that has escaped
-- the edge is ever seen. Whatever canvas they go on needs slack around the
-- surface — see ui.ringPad — because a canvas clips its own contents.
--
-- Returns a table, so the caller can hold it in the same retained global as the
-- canvas. An unreferenced timer is collected and stops firing silently, but
-- this owns no timer: the caller drives tick from whatever clock it already has.

-- How much room the rings need outside the surface.
function ui.ringPad(extra)
  return theme.ring.distance + theme.ring.width + (extra or 0)
end

function ui.rings(canvas, frame, opts)
  opts = opts or {}
  local ring = theme.ring
  local radius = opts.radius or theme.radius.card
  local cadence = {
    count = ring.count, period = opts.period or ring.period,
    width = ring.width, fade = ring.fade, distance = ring.distance,
  }
  local base = #canvas

  for _ = 1, ring.count do
    canvas[#canvas + 1] = {
      type = "rectangle", action = "skip",
      frame = frame,
      roundedRectRadii = { xRadius = radius, yRadius = radius },
      strokeWidth = ring.width,
      strokeColor = ui.color(opts.hex or C.accent, 0),
    }
  end

  return {
    base = base,
    tick = function(elapsed)
      for k = 1, ring.count do
        local r = sonar.ring(elapsed, k, cadence)
        local el = canvas[base + k]
        if not el then return end
        el.action = "stroke"
        el.strokeWidth = r.width
        el.strokeColor = ui.color(opts.hex or C.accent, r.alpha * ring.peak)
        el.frame = {
          x = frame.x - r.offset,
          y = frame.y - r.offset,
          w = frame.w + r.offset * 2,
          h = frame.h + r.offset * 2,
        }
        el.roundedRectRadii = {
          xRadius = radius + r.offset,
          yRadius = radius + r.offset,
        }
      end
    end,
  }
end

-- 30fps. Fast enough that a slow fade doesn't step, cheap enough to leave
-- running while a window is open.
ui.FRAME_INTERVAL = 1 / 30

return ui
