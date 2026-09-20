-- The sonar-ring cadence: how a ring's distance, thickness and alpha evolve
-- over its life, and how several rings in flight are staggered against each
-- other.
--
-- Shared by the dictation indicator (rings sweeping inward from the screen
-- edge) and the Hyper cheatsheet (rings radiating outward from the card), which
-- is the whole reason it's a module rather than eight lines inlined twice: the
-- two are meant to read as the same gesture, and they only stay that way if
-- there is one place that defines it. What differs between them — direction,
-- colour, and the path the ring is drawn along — is the caller's business.
--
-- Deliberately free of any `hs.*` reference, like lib/geometry.lua: this must
-- load in a bare Lua interpreter so hammerspoon/tests can exercise it without
-- Hammerspoon running. Keep it that way.

local M = {}

local DEFAULTS = {
  count  = 3,     -- rings in flight at once
  period = 1.5,   -- seconds for one ring: spawn -> faded out
  fade   = 1.5,   -- >1 makes the ring die away sooner than it travels
  thin   = 0.6,   -- fraction of its width a ring loses over its life
  width  = 1,
}

local function opt(opts, name)
  local v = opts[name]
  if v == nil then return DEFAULTS[name] end
  return v
end

-- Where ring `index` is in its life at `elapsed`, as 0 (just spawned) -> 1
-- (gone). The stagger is what makes three rings read as a continuous pulse
-- rather than three things blinking together.
function M.phase(elapsed, index, opts)
  opts = opts or {}
  local count = opt(opts, "count")
  return (((elapsed / opt(opts, "period")) + (index - 1) / count) % 1 + 1) % 1
end

-- The drawable state of ring `index`: how far it has travelled from its
-- spawn edge, how thick it is now, and how visible. `distance` (in points) is
-- the caller's, since "how far" means inward on one caller and outward on the
-- other.
--
-- Alpha falls off as a power of the remaining life rather than linearly: a
-- linear fade keeps a ring faintly visible for its whole travel, which reads as
-- a smear instead of a pulse.
function M.ring(elapsed, index, opts)
  opts = opts or {}
  local t = M.phase(elapsed, index, opts)
  return {
    t      = t,
    offset = t * (opts.distance or 0),
    width  = opt(opts, "width") * (1 - t * opt(opts, "thin")),
    alpha  = (1 - t) ^ opt(opts, "fade"),
  }
end

return M
