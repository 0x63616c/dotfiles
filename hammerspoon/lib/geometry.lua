-- Pure geometry and text-layout helpers for the dictation indicator.
--
-- Deliberately free of any `hs.*` reference: this module must load in a bare
-- Lua interpreter so hammerspoon/tests can exercise it without Hammerspoon
-- running. Anything that touches macOS belongs in init.lua, not here. Keep it
-- that way — the moment this file requires `hs`, the tests stop working.

local M = {}

-- Control points pulled this fraction of the way toward the corner give a cubic
-- bezier indistinguishable from a true quarter-circle. Standard constant.
local ARC_K = 0.5523
M.ARC_K = ARC_K

function M.lineTo(segs, x, y)
  segs[#segs + 1] = { x = x, y = y }
end

-- A quarter-turn from (fromX,fromY) to (toX,toY) bending around (cornerX,cornerY).
-- Works for turns in either direction: the corner is just an attractor.
function M.arcTo(segs, fromX, fromY, toX, toY, cornerX, cornerY)
  segs[#segs + 1] = {
    x = toX, y = toY,
    c1x = fromX + (cornerX - fromX) * ARC_K,
    c1y = fromY + (cornerY - fromY) * ARC_K,
    c2x = toX + (cornerX - toX) * ARC_K,
    c2y = toY + (cornerY - toY) * ARC_K,
  }
end

-- The ring path: a rounded rect inset from the screen edge, optionally
-- detouring around a notch on the top edge.
--
--   notch = { left = , right = , bottom = }  (screen coords) or nil
--   opts  = { screenRadius = , notchRadius = , joinRadius = }
--
-- The detour sits `inset` clear of the notch on every side, so it expands
-- outward in step with the ring itself — that is what makes the ripple appear
-- to bend around the notch rather than pass behind it.
--
-- joinRadius rounds the two turns where the top edge drops down to meet the
-- notch. Without it those are hard 90-degree corners, which read as a glitch
-- next to everything else being curved.
function M.ringPath(w, h, inset, notch, opts)
  opts = opts or {}
  local screenR = opts.screenRadius or 14
  local notchR  = opts.notchRadius or 18
  local joinR   = opts.joinRadius or 12

  local L, T, R, B = inset, inset, w - inset, h - inset
  local r = math.max(2, screenR - inset)
  local segs = {}
  local lineTo, arcTo = M.lineTo, M.arcTo

  lineTo(segs, L + r, T)

  if notch then
    local nl = notch.left - inset
    local nr = notch.right + inset
    local nb = notch.bottom + inset
    local cr = notchR + inset            -- detour's bottom-corner radius

    -- Only detour when every curve has room. A cramped detour produces a
    -- self-intersecting path, which renders as a magenta knot; falling back to
    -- a plain top edge is the graceful failure.
    local fits = (nl - joinR > L + r)
             and (nr + joinR < R - r)
             and (nb - cr > T + joinR)
             and (nr - cr > nl + cr)

    if fits then
      lineTo(segs, nl - joinR, T)
      arcTo(segs, nl - joinR, T, nl, T + joinR, nl, T)   -- turn down
      lineTo(segs, nl, nb - cr)
      arcTo(segs, nl, nb - cr, nl + cr, nb, nl, nb)      -- notch bottom-left
      lineTo(segs, nr - cr, nb)
      arcTo(segs, nr - cr, nb, nr, nb - cr, nr, nb)      -- notch bottom-right
      lineTo(segs, nr, T + joinR)
      arcTo(segs, nr, T + joinR, nr + joinR, T, nr, T)   -- turn back up
    end
  end

  lineTo(segs, R - r, T)
  arcTo(segs, R - r, T, R, T + r, R, T)
  lineTo(segs, R, B - r)
  arcTo(segs, R, B - r, R - r, B, R, B)
  lineTo(segs, L + r, B)
  arcTo(segs, L + r, B, L, B - r, L, B)
  lineTo(segs, L, T + r)
  arcTo(segs, L, T + r, L + r, T, L, T)

  return segs
end

-- Where a marquee'd string sits this frame: hold, scroll to the end, hold,
-- scroll back. Ping-pong rather than wrap-around, so the text is never cut
-- mid-word at a seam.
--
-- Text that fits doesn't scroll at all — it gets centred. The text element has
-- to be left-aligned for the marquee to work (a centred one would fight the
-- offset), so short titles would otherwise sit flush left under a centred
-- header, which reads as broken rather than deliberate.
function M.marqueeOffset(elapsed, windowW, textW, opts)
  opts = opts or {}
  local speed = opts.speed or 38
  local hold  = opts.hold or 1.4

  local overflow = textW - windowW
  if overflow <= 0 then return (windowW - textW) / 2 end

  local travel = overflow / speed
  local cycle = travel * 2 + hold * 2
  local t = elapsed % cycle

  if t < hold then return 0 end
  t = t - hold
  if t < travel then return -t * speed end
  t = t - travel
  if t < hold then return -overflow end
  return -overflow + (t - hold) * speed
end

-- Seconds -> "m:ss", or "h:mm:ss" past the hour. Returns nil for anything that
-- isn't a usable number, so callers can omit the field rather than print junk —
-- media-control leaves duration out entirely for live streams.
function M.formatTime(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds then return nil end
  if seconds < 0 or seconds == math.huge then return nil end
  local s = math.floor(seconds + 0.5)
  local h = math.floor(s / 3600)
  local m = math.floor((s % 3600) / 60)
  local sec = s % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
  return string.format("%d:%02d", m, sec)
end

-- The notch's third line: artist and position, whichever of them exist.
function M.subtitle(artist, elapsed, duration)
  local parts = {}
  if artist and artist ~= "" then parts[#parts + 1] = artist end
  local e, d = M.formatTime(elapsed), M.formatTime(duration)
  if e and d then
    parts[#parts + 1] = e .. " / " .. d
  elseif e then
    parts[#parts + 1] = e
  elseif d then
    parts[#parts + 1] = d
  end
  return table.concat(parts, "  ·  ")
end

return M
