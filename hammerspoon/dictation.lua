-- Auto pause/resume media around dictation (Wispr Flow).
--
-- Watches the default microphone's in-use state. When any app grabs the
-- mic (Wispr Flow recording), pause what's actually playing; when the
-- mic is released, resume the current media player if we paused it. If dictation fails
-- to start, the mic never activates and nothing happens.
--
-- Controls the current macOS media player (Spotify, Music, Chrome, ...).
-- Explicit pause/play commands avoid starting media that was already paused.
-- Skip artwork when querying state: large responses can block hs.task pipes.
--
-- Pressing the physical play/pause media key mid-dictation means you
-- took control: the auto-resume is skipped.


local log = hs.logger.new("dictation", "debug")

local MEDIA_CONTROL = "/opt/homebrew/bin/media-control"

micState = {
  dictating = false,
  userToggled = false,
  mcPaused = false,   -- we paused a MediaRemote app
  appPaused = nil,    -- or we paused a scriptable one directly; see below
  session = 0,
}

-- Now-playing clients that aren't playing anything on this Mac.
--
-- The Sonos menu bar controller registers with MediaRemote on behalf of the
-- *speakers*, and it outranks a browser tab the moment the Sonos system changes
-- state — a volume nudge from the Hyper+S panel is enough. From then on
-- `media-control get` answers "Line-In" and `media-control pause` pauses the
-- house rather than the YouTube tab that is actually talking over dictation.
-- Neither is wanted, so these are never treated as the thing to pause.
local IGNORED_PLAYERS = {
  ["com.app-lane.mbc"] = "Menu Bar Controller for Sonos",
}

-- MediaRemote commands only ever reach the top client, so when that client is
-- one of the above there is no way to reach a browser. The players that take
-- AppleScript directly can still be paused by name, which covers Spotify and
-- Music; a browser tab in that state is simply left alone.
local SCRIPTABLE = {
  { name = "Spotify", app = hs.spotify },
  { name = "Music",   app = hs.itunes },
}

local function pauseScriptablePlayer()
  for _, p in ipairs(SCRIPTABLE) do
    local ok, playing = pcall(function() return p.app.isRunning() and p.app.isPlaying() end)
    if ok and playing then
      p.app.pause()
      local title = select(2, pcall(p.app.getCurrentTrack))
      local artist = select(2, pcall(p.app.getCurrentArtist))
      return p, { title = type(title) == "string" and title or p.name,
                  artist = type(artist) == "string" and artist or p.name }
    end
  end
  return nil, nil
end

-- MediaRemote source (Spotify etc.) -----------------------------------------

local function mcCommand(cmd)
  hs.task.new(MEDIA_CONTROL, nil, { cmd }):start()
end

-- Calls back with (playing, info). `info` is media-control's JSON — title,
-- artist, album, bundleIdentifier — so the notch can name what it paused.
local function mcIsPlaying(callback)
  hs.task.new(MEDIA_CONTROL, function(exitCode, stdout)
    local ok, info = pcall(hs.json.decode, stdout or "")
    if not (exitCode == 0 and ok and type(info) == "table") then
      callback(false, nil)
      return
    end
    callback(info.playbackRate ~= nil and info.playbackRate > 0, info)
  end, { "get", "--no-artwork" }):start()
end

-- Screen-edge indicator ------------------------------------------------------
--
-- Dictation state, readable at a glance without hunting for Wispr's own UI:
-- a magenta edge glow on every screen while the mic is live, with sonar rings
-- that spawn at the edge and sweep a short way inward before fading
-- (RING_TRAVEL is deliberately tiny; a longer sweep drags magenta across
-- whatever you're dictating into).
--
-- Two layers, deliberately:
--   * a static edge glow, so the "mic is live" signal stays legible even at the
--     moment a ring has faded out;
--   * the travelling rings, which are the part that catches the eye.
--
-- When we also pause media, a notch slides down from the top centre naming the
-- track and where it was paused. It lags the border, because `media-control
-- get` answers asynchronously and the border must not wait on it.
--
-- The path maths lives in lib/geometry.lua so it can be tested without
-- Hammerspoon running — see hammerspoon/tests/. Everything hs-specific (the
-- canvases, timers and watchers) stays here.

local geometry = require("lib.geometry")
-- The ring cadence is shared with the Hyper cheatsheet card (hyper.lua), so the
-- two overlays pulse as one gesture. Direction, colour and path stay here.
local sonar = require("lib.sonar")

local BORDER_MAGENTA = { red = 1.0, green = 0.0, blue = 1.0 }
local BORDER_WIDTH   = 28    -- static edge glow thickness, points
local BORDER_BANDS   = 12    -- nested strokes faking the glow's falloff
local BORDER_FALLOFF = 1.7   -- >1 concentrates brightness at the outer edge,
                             -- which is what reads as a glow rather than a frame
local BORDER_BASE    = 0.55  -- static glow alpha (the rings supply the motion)
local SCREEN_RADIUS  = 28    -- corner rounding of the display itself
-- How far outside the screen edge the outermost arc sits. Flush (0) leaves the
-- display's square corners unpainted: a rounded path along the edge cuts the
-- corner off and you see dark exactly where the glow should be densest. The
-- corner arc is centred on (SCREEN_RADIUS, SCREEN_RADIUS) whatever the
-- overshoot, so it reaches the corner once its radius passes
-- SCREEN_RADIUS * sqrt(2) — that is, at this overshoot and no more. Taking the
-- minimum keeps the glow where it already looked right; only the corner
-- changes, and the sliver beyond the edge is clipped by the screen anyway.
local BORDER_OVERSHOOT = SCREEN_RADIUS * (math.sqrt(2) - 1)
-- Extra bands laid outward to cover the overshoot, so widening the glow outward
-- doesn't pull its inner edge out with it.
local BORDER_BAND_W  = BORDER_WIDTH / BORDER_BANDS
local BORDER_EXTRA   = math.ceil(BORDER_OVERSHOOT / BORDER_BAND_W)

local RING_COUNT     = 3     -- rings in flight at once
local RING_PERIOD    = 1.5   -- seconds for one ring: edge -> faded out
local RING_TRAVEL    = 0.04  -- how far in it gets, as a fraction of half the
                             -- screen's shorter side (1.0 would be dead centre)
local RING_WIDTH     = 6     -- stroke at spawn; thins as it travels
local RING_FADE      = 1.5   -- >1 makes the ring die away sooner
local FRAME_INTERVAL = 1 / 30

-- The "paused" notch. Kept narrow on purpose — it sits over your content — so
-- the title marquees rather than the box growing to fit it.
local NOTCH_W        = 420
local NOTCH_H        = 88
local NOTCH_OVERHANG = 24    -- extra height above the screen edge, so the top
                             -- corners' rounding is never visible
local NOTCH_RADIUS   = 18
local NOTCH_JOIN_R   = 18    -- rounding where the ring's top edge turns down to
                             -- meet the notch; matches NOTCH_RADIUS so the ring
                             -- and the card's own flare share a silhouette
local NOTCH_SLIDE    = 0.28  -- seconds for the slide-down
local NOTCH_PAD      = 16    -- horizontal inset for the marquee window
local NOTCH_PAD_TOP  = 18    -- gap above the first line; the rest of the
                             -- layout is derived from it

local MARQUEE = { speed = 38, hold = 1.4 }   -- points/sec, seconds at each end

local RING_OPTS = {
  screenRadius = SCREEN_RADIUS,
  overshoot = BORDER_OVERSHOOT,
  notchRadius = NOTCH_RADIUS,
  joinRadius = NOTCH_JOIN_R,
}

-- `distance` is filled in per canvas: it's measured off that screen's shorter
-- side, so a ring on a wide display doesn't collapse its height to zero before
-- it has gone anywhere.
local RING_CADENCE = {
  count = RING_COUNT, period = RING_PERIOD,
  width = RING_WIDTH, fade = RING_FADE,
}

-- Retained deliberately: an unreferenced canvas or timer is garbage-collected
-- and disappears silently, same as the watchers above.
borderCanvases = {}
borderAnimTimer = nil
borderNotchCanvas = nil   -- the one canvas carrying the notch (main screen)

local borderVisible = false
local notchShown = false
local notchSlide = 0      -- 0 = hidden above the edge, 1 = fully down
local notchLine1 = ""
local notchTitle = ""
local notchSub = ""
local notchTextW = 0      -- measured width of the title, for the marquee
local notchShownAt = 0

local function magentaAlpha(alpha)
  return { red = BORDER_MAGENTA.red, green = BORDER_MAGENTA.green,
           blue = BORDER_MAGENTA.blue, alpha = alpha }
end

-- Element indices are fixed so rings and the notch can be addressed by index.
local RING_BASE    = BORDER_EXTRA + BORDER_BANDS
local NOTCH_BG     = RING_BASE + RING_COUNT + 1
local NOTCH_LINE1  = RING_BASE + RING_COUNT + 2
local NOTCH_CLIP   = RING_BASE + RING_COUNT + 3
local NOTCH_LINE2  = RING_BASE + RING_COUNT + 4
local NOTCH_UNCLIP = RING_BASE + RING_COUNT + 5
local NOTCH_LINE3  = RING_BASE + RING_COUNT + 6

local function buildBorderCanvas(screen, withNotch)
  local f = screen:fullFrame()
  local c = hs.canvas.new({ x = f.x, y = f.y, w = f.w, h = f.h })
  if not c then return nil end

  c:level(hs.canvas.windowLevels.screenSaver)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
             + hs.canvas.windowBehaviors.stationary)
  c:clickActivating(false)
  c:canvasMouseEvents(false, false, false, false)

  -- Static edge glow. Bands 1..BORDER_EXTRA sit outside the screen edge and
  -- carry full brightness; the falloff is measured from the edge inward, as
  -- before, so the glow reads exactly as it did.
  local band = BORDER_BAND_W
  for i = 1, BORDER_EXTRA + BORDER_BANDS do
    local step = i - 1 - BORDER_EXTRA          -- 0 = flush with the edge
    local inset = step * band
    -- Radius tracks the inset (same rule as ringPath), so every band is
    -- concentric with the display's own rounding rather than parallel to it.
    local radius = math.max(2, SCREEN_RADIUS - inset)
    local fade = math.max(0, step) / BORDER_BANDS
    c[i] = {
      type = "rectangle",
      action = "stroke",
      strokeWidth = band * 2,
      strokeColor = magentaAlpha(BORDER_BASE * ((1 - fade) ^ BORDER_FALLOFF)),
      frame = { x = inset, y = inset,
                w = f.w - inset * 2, h = f.h - inset * 2 },
      roundedRectRadii = { xRadius = radius, yRadius = radius },
    }
  end

  -- Travelling rings. The animation tick owns their path and colour.
  for k = 1, RING_COUNT do
    c[RING_BASE + k] = {
      type = "segments",
      action = "skip",
      closed = true,
      strokeWidth = RING_WIDTH,
      strokeColor = magentaAlpha(0),
      coordinates = geometry.ringPath(f.w, f.h, 0, nil, RING_OPTS),
    }
  end

  -- The notch: top centre, solid magenta, white text. One screen only —
  -- repeating it on every display is noise. Frames are set by the tick.
  local nx = (f.w - NOTCH_W) / 2
  local act = withNotch and "fill" or "skip"
  c[NOTCH_BG] = {
    type = "segments",
    action = act,
    closed = true,
    fillColor = magentaAlpha(0.95),
    coordinates = geometry.notchPath(nx, nx + NOTCH_W,
                                     -NOTCH_H - NOTCH_OVERHANG, -NOTCH_OVERHANG,
                                     NOTCH_RADIUS),
  }
  c[NOTCH_LINE1] = {
    type = "text",
    action = act,
    text = "",
    textColor = { white = 1, alpha = 1.0 },
    textSize = 15,
    textAlignment = "center",
    frame = { x = nx, y = -NOTCH_H + NOTCH_PAD_TOP, w = NOTCH_W, h = 20 },
  }
  -- The title scrolls, so it must be clipped to the notch's inner width —
  -- canvas text does not clip to its own frame.
  c[NOTCH_CLIP] = {
    type = "rectangle",
    action = "clip",
    frame = { x = nx + NOTCH_PAD, y = -NOTCH_H + NOTCH_PAD_TOP + 21,
              w = NOTCH_W - NOTCH_PAD * 2, h = 22 },
  }
  c[NOTCH_LINE2] = {
    type = "text",
    action = act,
    text = "",
    textColor = { white = 1, alpha = 0.95 },
    textSize = 13,
    textAlignment = "left",
    frame = { x = nx + NOTCH_PAD, y = -NOTCH_H + NOTCH_PAD_TOP + 22,
              w = NOTCH_W, h = 20 },
  }
  c[NOTCH_UNCLIP] = { type = "resetClip" }
  c[NOTCH_LINE3] = {
    type = "text",
    action = act,
    text = "",
    textColor = { white = 1, alpha = 0.8 },
    textSize = 11,
    textAlignment = "center",
    frame = { x = nx, y = -NOTCH_H + NOTCH_PAD_TOP + 44, w = NOTCH_W, h = 16 },
  }

  return c
end

local function rebuildBorderCanvases()
  for _, c in ipairs(borderCanvases) do c:delete() end
  borderCanvases = {}
  borderNotchCanvas = nil
  local main = hs.screen.mainScreen()
  for _, screen in ipairs(hs.screen.allScreens()) do
    local isMain = (screen:id() == main:id())
    local c = buildBorderCanvas(screen, notchShown and isMain)
    if c then
      table.insert(borderCanvases, c)
      if isMain then borderNotchCanvas = c end
    end
  end
end

-- One animation frame: rings on every screen, plus the notch slide + marquee.
local function tickBorder(elapsed)
  local notchRect = nil
  if notchShown and notchSlide > 0 and borderNotchCanvas then
    local f = borderNotchCanvas:frame()
    local nx = (f.w - NOTCH_W) / 2
    local e = 1 - (1 - notchSlide) ^ 3
    notchRect = { left = nx, right = nx + NOTCH_W, bottom = e * NOTCH_H }
  end

  for _, c in ipairs(borderCanvases) do
    local f = c:frame()
    RING_CADENCE.distance = (math.min(f.w, f.h) / 2) * RING_TRAVEL
    -- Only the notch's own screen gets the detour.
    local notch = (c == borderNotchCanvas) and notchRect or nil
    for k = 1, RING_COUNT do
      local r = sonar.ring(elapsed, k, RING_CADENCE)
      local el = c[RING_BASE + k]
      el.action = "stroke"
      el.strokeWidth = r.width
      el.strokeColor = magentaAlpha(r.alpha)
      el.coordinates = geometry.ringPath(f.w, f.h, r.offset, notch, RING_OPTS)
    end
  end

  local c = borderNotchCanvas
  if not (notchShown and c) then return end

  if notchSlide < 1 then
    notchSlide = math.min(1, notchSlide + FRAME_INTERVAL / NOTCH_SLIDE)
  end

  -- Ease out cubic, so it settles rather than snapping to a stop.
  local e = 1 - (1 - notchSlide) ^ 3
  local f = c:frame()
  local nx = (f.w - NOTCH_W) / 2
  local top = e * NOTCH_H - NOTCH_H + NOTCH_PAD_TOP
  local windowW = NOTCH_W - NOTCH_PAD * 2

  c[NOTCH_BG].coordinates = geometry.notchPath(
    nx, nx + NOTCH_W, e * NOTCH_H - NOTCH_H, e * NOTCH_H, NOTCH_RADIUS)
  c[NOTCH_LINE1].frame = { x = nx, y = top, w = NOTCH_W, h = 20 }
  c[NOTCH_CLIP].frame = { x = nx + NOTCH_PAD, y = top + 21, w = windowW, h = 22 }
  c[NOTCH_LINE2].frame = {
    x = nx + NOTCH_PAD
        + geometry.marqueeOffset(elapsed - notchShownAt, windowW, notchTextW, MARQUEE),
    y = top + 22,
    w = math.max(notchTextW + 4, windowW), h = 20,
  }
  c[NOTCH_LINE3].frame = { x = nx, y = top + 44, w = NOTCH_W, h = 16 }
end

local function startAnimation()
  if borderAnimTimer then return end
  local t0 = hs.timer.secondsSinceEpoch()
  borderAnimTimer = hs.timer.doEvery(FRAME_INTERVAL, function()
    tickBorder(hs.timer.secondsSinceEpoch() - t0)
  end)
end

local function stopAnimation()
  if borderAnimTimer then
    borderAnimTimer:stop()
    borderAnimTimer = nil
  end
end

function borderShow()
  if borderVisible then return end
  borderVisible = true
  notchShown = false
  notchSlide = 0
  rebuildBorderCanvases()
  for _, c in ipairs(borderCanvases) do c:show() end
  startAnimation()
end

function borderHide()
  borderVisible = false
  notchShown = false
  notchSlide = 0
  stopAnimation()
  for _, c in ipairs(borderCanvases) do c:delete() end
  borderCanvases = {}
  borderNotchCanvas = nil
end

-- Apply the current notch text to a canvas and measure the title for the
-- marquee. Measuring needs a live canvas, which is why it isn't in lib/.
local function applyNotchText(c)
  for _, i in ipairs({ NOTCH_BG, NOTCH_LINE1, NOTCH_LINE2, NOTCH_LINE3 }) do
    c[i].action = "fill"
  end
  c[NOTCH_LINE1].text = notchLine1
  c[NOTCH_LINE2].text = notchTitle
  c[NOTCH_LINE3].text = notchSub
  local size = c:minimumTextSize(NOTCH_LINE2, notchTitle)
  notchTextW = (size and size.w) or 0
end

-- `info` is media-control's JSON for the thing we just paused. Every field is
-- optional — Chrome tabs often have no artist, album is usually empty, and a
-- live stream has no duration — so each is guarded rather than assumed.
function borderMarkPaused(info)
  if not borderVisible then return end
  local title, artist, elapsed, duration = "", "", nil, nil
  if type(info) == "table" then
    title = type(info.title) == "string" and info.title or ""
    artist = type(info.artist) == "string" and info.artist or ""
    if artist == "" and type(info.bundleIdentifier) == "string" then
      artist = hs.application.nameForBundleID(info.bundleIdentifier) or ""
    end
    elapsed = tonumber(info.elapsedTime)
    duration = tonumber(info.duration)
  end

  notchLine1 = "⏸  PAUSED"
  notchTitle = title
  notchSub = geometry.subtitle(artist, elapsed, duration)

  notchShown = true
  notchSlide = 0
  notchShownAt = hs.timer.secondsSinceEpoch()
  if borderNotchCanvas then applyNotchText(borderNotchCanvas) end
end

-- Displays coming and going invalidate every canvas frame; rebuild in place.
borderScreenWatcher = hs.screen.watcher.new(function()
  if not borderVisible then return end
  local wasShown = notchShown
  rebuildBorderCanvases()
  for _, c in ipairs(borderCanvases) do c:show() end
  if wasShown and borderNotchCanvas then
    notchShown = true
    applyNotchText(borderNotchCanvas)
  end
end):start()

-- Mic watcher ----------------------------------------------------------------

local function micInUse()
  local dev = hs.audiodevice.defaultInputDevice()
  return dev ~= nil and dev:inUse()
end

function onMicGrabbed()
  micState.session = micState.session + 1
  local session = micState.session
  micState.userToggled = false
  micState.mcPaused = false
  micState.appPaused = nil
  borderShow()
  mcIsPlaying(function(playing, info)
    if not (micState.dictating and not micState.userToggled
            and session == micState.session) then return end

    local bundle = type(info) == "table" and info.bundleIdentifier or nil
    if bundle and IGNORED_PLAYERS[bundle] then
      log.df("now-playing is %s (not local) -> trying scriptable players",
             IGNORED_PLAYERS[bundle])
      local player, meta = pauseScriptablePlayer()
      if player then
        micState.appPaused = player
        borderMarkPaused(meta)
      end
      return
    end

    if playing then
      log.d("MediaRemote app playing -> pause")
      mcCommand("pause")
      micState.mcPaused = true
      borderMarkPaused(info)
    end
  end)
end

function onMicReleased()
  if micState.userToggled then
    log.d("user toggled during dictation -> leaving playback as-is")
  else
    if micState.mcPaused then
      log.d("resuming MediaRemote app")
      mcCommand("play")
    elseif micState.appPaused then
      log.df("resuming %s", micState.appPaused.name)
      micState.appPaused.app.play()
    end
  end
  micState.mcPaused = false
  micState.appPaused = nil
  borderHide()
end

local function syncMicState()
  local inUse = micInUse()
  if inUse == nil or inUse == micState.dictating then return end
  micState.dictating = inUse
  log.df("mic inUse -> %s", tostring(inUse))
  if inUse then onMicGrabbed() else onMicReleased() end
end

local function watchDefaultMicrophone()
  if micDevice then micDevice:watcherStop() end
  micDevice = hs.audiodevice.defaultInputDevice()
  if micDevice then
    micDevice:watcherCallback(function(_, event)
      if event == "gone" or event == "diff" then syncMicState() end
    end)
    micDevice:watcherStart()
  end
  syncMicState()
end

-- macOS notifies us when microphone use or the default input changes.
hs.audiodevice.watcher.setCallback(function(event)
  if event == "dIn " or event == "dev#" then watchDefaultMicrophone() end
end)
hs.audiodevice.watcher.start()
watchDefaultMicrophone()

-- Physical media-key presses (the F8-position play/pause key).
mediaKeyTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
  local key = e:systemKey()
  if key and key.down and (key.key == "PLAY" or key.key == "PAUSE") and micState.dictating then
    micState.userToggled = true
    log.d("user pressed play/pause during dictation")
  end
  return false
end):start()

-- Shift+Control chord -> toggle play/pause -----------------------------------
--
-- hs.hotkey cannot bind bare modifiers — it needs a key — so a modifiers-only
-- chord has to come off a flagsChanged eventtap. The tap is the only part that
-- belongs here; the state machine deciding whether a sequence of flag states
-- counts as a deliberate chord lives in lib/chord.lua, where it is tested
-- against Hyper presses and Ctrl+Shift+<key> without needing a keyboard.
--
-- Hyper matters specifically: hyper.lua binds Ctrl+Shift+Alt+Gui, so every
-- Hyper press puts shift+ctrl on the wire on its way up and down. See
-- lib/chord.lua for why `dirty` has to be sticky to survive that.
--
-- Needs Accessibility, and may prompt separately for Input Monitoring — a
-- keyDown tap is the heavyweight kind. The callback stays trivial because
-- anything slow here degrades system-wide input latency, and it always returns
-- false so no real input is ever swallowed.

local Chord = require("lib.chord")

local mediaChord = Chord.new({ maxHold = 0.6 })

mediaChordTap = hs.eventtap.new(
  { hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown },
  function(e)
    if e:getType() == hs.eventtap.event.types.keyDown then
      mediaChord:keyDown()
      return false
    end

    if mediaChord:flagsChanged(e:getFlags(), hs.timer.secondsSinceEpoch()) then
      log.d("shift+ctrl chord -> toggle play/pause")
      mcCommand("toggle-play-pause")
      -- Toggling mid-dictation is taking control, exactly like the physical
      -- media key: don't auto-resume on mic release.
      if micState.dictating then
        micState.userToggled = true
        log.d("chord used during dictation -> auto-resume suppressed")
      end
    end
    return false
  end):start()
