-- Design tokens: one shadcn "zinc" dark palette, one type scale, one set of
-- radii, shared by every canvas UI in this config (the Hyper cheatsheet, the
-- screenshot library). Two overlays that look almost the same are worse than
-- two that look different, so there is exactly one place to change.
--
-- Colours are hex strings rather than canvas colour tables because this file,
-- like the rest of lib/, must load in a bare Lua interpreter — see
-- hammerspoon/tests/. ui.lua turns them into the {red=,green=,blue=,alpha=}
-- tables canvas wants; anything hs-shaped belongs there, not here.

local M = {}

-- shadcn's dark theme, token for token. The names are shadcn's too: when the
-- question is "what colour should this be", the answer should be a token you
-- can look up in their docs rather than a judgement call.
M.color = {
  popover         = "#09090b",  -- surfaces: cards, dialogs
  border          = "#27272a",  -- zinc-800: every hairline
  muted           = "#27272a",  -- zinc-800: recessed fills (keycaps, tiles)
  mutedEdge       = "#3f3f46",  -- zinc-700: the edge of a recessed fill
  foreground      = "#fafafa",  -- zinc-50: primary text
  mutedForeground = "#a1a1aa",  -- zinc-400: secondary text
  accent          = "#fafafa",  -- selection / pressed / hover
  backdrop        = "#000000",  -- dialog overlay, at BACKDROP_ALPHA
}

M.alpha = {
  surface  = 0.97,  -- a card is nearly opaque; the hint of translucency only
                    -- exists so it doesn't look pasted onto the screenshot
  backdrop = 0.5,
  hairline = 1.0,
}

M.radius = {
  card    = 15,  -- rounded-xl
  control = 8,   -- rounded-md: keycaps, tiles, thumbnails
}

-- Sizes in points. `title` is the small tracked-out label at the top of a card;
-- `label` is the primary row text; `caption` is anything secondary.
M.text = {
  title   = 12,
  label   = 15,
  key     = 14,
  body    = 13,
  caption = 11,
}

M.space = {
  pad = 28,  -- inside a card's edge
  gap = 10,  -- between siblings in a grid
  row = 42,  -- a list row's height
}

-- ".AppleSystemUIFont" is the system UI face (SF on this machine) and
-- ".AppleSystemUIFaceHeadline" its semibold cut. Neither is in
-- hs.styledtext.fontNames() — the SF family ships as a private system font
-- rather than an installed one — but NSFont resolves both by name, which is all
-- canvas needs.
M.font = {
  ui       = ".AppleSystemUIFont",
  semibold = ".AppleSystemUIFaceHeadline",
}

-- The shared drop shadow. Every surface gets the same one, which is most of
-- what makes two separate windows look like one system.
M.shadow = { blur = 26, alpha = 0.5, dy = 10 }

-- Radiating rings. The cadence maths is lib/sonar.lua; these are this design's
-- settings for it. Slower than the dictation indicator's 1.5s on purpose: that
-- one is a live-mic warning that has to register at a glance, these are ambient
-- while you read.
M.ring = {
  count    = 3,
  period   = 3.2,
  distance = 30,
  width    = 5,
  fade     = 1.7,
  peak     = 0.45,  -- alpha at spawn; white is loud
}

return M
