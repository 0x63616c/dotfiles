-- Sonos panel ------------------------------------------------------------------
--
-- Hyper+S: a card listing every Sonos room on the LAN with its volume on a
-- slider, which group it's in and what it's playing, plus two one-key moves —
-- "everything to the Desk" and "TV mode" (the Beam back on its TV feed).
--
-- Replaces reaching for the Sonos app or the menu bar controller for the two
-- things that actually happen at this desk: pulling the whole house onto the
-- Desk pair, and handing the living room back to the TV.
--
-- Talks to the speakers directly: they answer plain HTTP on :1400 with no auth
-- and no cloud, so there is nothing to sign into and nothing to break when
-- Sonos changes its app. Discovery is SSDP (an M-SEARCH on 239.255.255.250:1900
-- through hs.socket.udp) with the last-seen addresses as a fallback, so the
-- panel still opens if multicast is having a bad day. Every request is
-- hs.http.asyncPost — nothing here blocks, since a speaker that has gone to
-- sleep would otherwise hang Hammerspoon for the length of a TCP timeout.
--
-- Topology is read fresh every poll and never cached: grouping is volatile
-- (the TV coming on regroups the Beam by itself). Same rooms → the numbers are
-- updated in place, so a hover or a drag survives the poll; a regroup rebuilds.
--
-- The envelopes, the topology parser and the source labels are lib/sonos.lua,
-- which loads in a bare interpreter and is tested; this file is the network
-- and the canvas. Built from ui.lua on lib/theme.lua's tokens like the
-- cheatsheet and the screenshot library, so the three read as one program.

local hyper = require("hyper")
local ui    = require("ui")
local theme = require("lib.theme")
local sonos = require("lib.sonos")

local log = hs.logger.new("sonos", "info")

-- The two rooms the shortcuts are about. Everything else is discovered.
local DESK_ROOM = "Desk"
local TV_ROOM   = "Living Room"

-- Used only if SSDP turns up nothing: the addresses the speakers had when this
-- was written (they're fixed leases). One reachable speaker is enough, since
-- the topology it returns names every other one.
local SEED_IPS = { "192.168.0.152", "192.168.0.193", "192.168.0.63", "192.168.0.149", "192.168.0.179" }

local DISCOVERY_WAIT = 1.0   -- seconds to collect SSDP replies
local POLL_INTERVAL  = 2     -- re-read topology + volumes while open
local SEND_THROTTLE  = 0.12  -- min gap between SetVolume calls during a drag
local SETTLE_DELAY   = 1.2   -- how long a regroup takes to show in topology
local FLASH_HOLD     = 0.18  -- a pressed button stays lit this long

-- Layout, in points, on the shared spacing scale.
local PAD        = 24
local HEADER_H   = 52
local ROW_H      = theme.space.row
local GAP        = 16
local NAME_MIN_W = 120
local SRC_W      = 96
local SLIDER_W   = 200
local TRACK_H    = 6
local KNOB_R     = 6
local NUM_W      = 34
local BTN_H      = 33
local BTN_PAD    = 16
local BTN_GAP    = theme.space.gap
local FOOTER_H   = 14 + BTN_H + PAD

-- Network ----------------------------------------------------------------------

-- Fire one SOAP action at a speaker. cb(body) gets the response body, or nil
-- on any failure — the caller decides whether that matters.
local function call(ip, service, action, args, cb)
  local req = sonos.request(service, action, args)
  hs.http.asyncPost("http://" .. ip .. ":1400" .. req.path, req.body, req.headers,
    function(status, body)
      if status ~= 200 then
        log.w(action .. " on " .. ip .. " -> " .. tostring(status))
        if cb then cb(nil) end
        return
      end
      if cb then cb(body) end
    end)
end

-- Last addresses that answered, kept across opens so a reopen is instant and
-- so a discovery that finds nothing still has somewhere to try.
local knownIps = {}

-- Retained: an unreferenced socket or timer is collected and goes silent.
sonosDiscoverySocket = nil
sonosDiscoveryTimer  = nil

local M_SEARCH = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
  .. 'MAN: "ssdp:discover"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n'

-- SSDP: shout, collect LOCATION headers for a second, hand back the ips.
local function discover(cb)
  if sonosDiscoverySocket then sonosDiscoverySocket:close() end
  local hits, seen = {}, {}
  sonosDiscoverySocket = hs.socket.udp.new(function(data)
    local ip = data:match("LOCATION:%s*http://([%d%.]+):1400")
    if ip and not seen[ip] then
      seen[ip] = true
      hits[#hits + 1] = ip
    end
  end)
  -- listen(0) binds an ephemeral port; without a bound port replies have
  -- nowhere to land and the callback never fires.
  sonosDiscoverySocket:listen(0):broadcast(true):receive()
  sonosDiscoverySocket:send(M_SEARCH, "239.255.255.250", 1900)
  sonosDiscoveryTimer = hs.timer.doAfter(DISCOVERY_WAIT, function()
    sonosDiscoveryTimer = nil
    if sonosDiscoverySocket then
      sonosDiscoverySocket:close()
      sonosDiscoverySocket = nil
    end
    if #hits > 0 then
      knownIps = hits
    elseif #knownIps == 0 then
      knownIps = SEED_IPS
    end
    cb(knownIps)
  end)
end

-- Per-room calibration baselines: uuid -> raw volume (1-100) at the moment
-- Calibrate was pressed. Persisted so a Hammerspoon restart doesn't lose
-- them; keyed by uuid like sendLatest/sendTimers below, since room name
-- isn't stable (and a stereo pair's hidden half doesn't get one at all).
local BASELINES_KEY = "sonosCalibrationBaselines"
local baselines = hs.settings.get(BASELINES_KEY) or {}

local function saveBaselines()
  hs.settings.set(BASELINES_KEY, baselines)
end

-- Rooms as last read: lib/sonos.lua's records with volume, uri, state and a
-- source label added.
local rooms = {}
-- Bumped per refresh; a response for an older generation is dropped rather
-- than painting stale numbers over newer ones.
local generation = 0

local apply  -- forward: paints a finished room list, defined with the canvas

-- Whether every visible room's slider is locked to move together; see
-- setLocked, defined with the rest of the panel below (it also repaints the
-- Lock button). Forward-declared here since clearCalibration, above the
-- panel section, needs to drop the lock.
local locked = false
local setLocked

-- Read topology from the first speaker that answers, then fan out for volumes
-- and what each coordinator is playing. Every branch counts itself in and out
-- so the paint happens once, after the last response.
local function refresh()
  if #knownIps == 0 then return end
  generation = generation + 1
  local gen = generation
  local tried = 0

  local function fanOut(list)
    local pending = 0
    local function done()
      pending = pending - 1
      if pending == 0 and gen == generation then apply(list) end
    end
    for _, r in ipairs(list) do
      r.volume, r.uri, r.state, r.source = 0, "", "", ""
      pending = pending + 1
      call(r.ip, "RenderingControl", "GetVolume", { { "Channel", "Master" } }, function(body)
        local raw = tonumber(sonos.value(body, "CurrentVolume")) or 0
        r.volume = sonos.displayVolume(raw, baselines[r.uuid])
        done()
      end)
      if r.isCoordinator then
        pending = pending + 2
        call(r.ip, "AVTransport", "GetMediaInfo", {}, function(body)
          r.uri = sonos.unescape(sonos.value(body, "CurrentURI") or "")
          r.source = sonos.sourceLabel(r.uri)
          done()
        end)
        call(r.ip, "AVTransport", "GetTransportInfo", {}, function(body)
          r.state = sonos.value(body, "CurrentTransportState") or ""
          done()
        end)
      end
    end
    if pending == 0 then apply(list) end
  end

  local function tryNext()
    tried = tried + 1
    local ip = knownIps[tried]
    if not ip then
      log.w("no speaker answered GetZoneGroupState")
      if gen == generation then apply({}) end
      return
    end
    call(ip, "ZoneGroupTopology", "GetZoneGroupState", {}, function(body)
      if gen ~= generation then return end
      local list = body and sonos.parseTopology(body) or {}
      if #list == 0 then return tryNext() end
      -- Every visible room's ip is in the topology, so one good answer refreshes
      -- the fallback list too.
      knownIps = {}
      for _, r in ipairs(list) do knownIps[#knownIps + 1] = r.ip end
      fanOut(list)
    end)
  end
  tryNext()
end

-- Volume sends during a drag are throttled per room: the slider moves at 30fps
-- but a speaker doesn't need 30 SetVolumes a second, and flooding one makes it
-- lag behind the knob. The latest value always lands — a pending timer sends
-- whatever was set last when it fires.
local sendTimers = {}
local sendLatest = {}

local function setVolume(room, v)
  sendLatest[room.uuid] = v
  if sendTimers[room.uuid] then return end
  local function flush()
    local latest = sendLatest[room.uuid]
    sendLatest[room.uuid] = nil
    if latest == nil then
      sendTimers[room.uuid] = nil
      return
    end
    call(room.ip, "RenderingControl", "SetVolume",
      { { "Channel", "Master" }, { "DesiredVolume", latest } })
    sendTimers[room.uuid] = hs.timer.doAfter(SEND_THROTTLE, flush)
  end
  flush()
end

-- Reads a fresh raw volume from every room currently in the panel (never the
-- painted number, which could be stale or already normalized) and stores
-- sonos.calibratedBaseline(raw) as that room's new calibration baseline, so
-- the room reads 50% from here on rather than 100% — leaving headroom to go
-- louder instead of pinning the raw volume at the moment of calibration as a
-- hard ceiling. A room read as 0 (muted) keeps whatever baseline it already
-- had rather than storing an unusable zero one.
local function calibrateRooms()
  local list = rooms
  local pending = #list
  if pending == 0 then return end
  for _, r in ipairs(list) do
    local uuid = r.uuid
    call(r.ip, "RenderingControl", "GetVolume", { { "Channel", "Master" } }, function(body)
      local raw = tonumber(sonos.value(body, "CurrentVolume")) or 0
      if raw > 0 then baselines[uuid] = sonos.calibratedBaseline(raw) end
      pending = pending - 1
      if pending == 0 then
        saveBaselines()
        refresh()
      end
    end)
  end
end

-- Undoes calibrateRooms: drops every currently-visible room's baseline
-- entirely (not zeroing it) so lib/sonos.lua's display logic treats it as
-- never calibrated and falls back to showing raw volume. Also drops the lock
-- (see `locked` above) — matching percentages stops meaning anything once
-- there's no calibration behind them.
local function clearCalibration()
  for _, r in ipairs(rooms) do
    baselines[r.uuid] = nil
  end
  saveBaselines()
  setLocked(false)
  refresh()
end

-- The two moves --------------------------------------------------------------

-- Every room joins the Desk pair's group. Joining is a member pointing its
-- transport at the coordinator; no Play needed, the coordinator's stream just
-- starts arriving.
local function groupAllToDesk()
  local desk = sonos.findRoom(rooms, DESK_ROOM)
  if not desk then
    hs.alert.show("No room called " .. DESK_ROOM)
    return
  end
  local uri = sonos.groupUri(desk.coordinator)
  for _, r in ipairs(rooms) do
    if r.coordinator ~= desk.coordinator then
      call(r.ip, "AVTransport", "SetAVTransportURI",
        { { "CurrentURI", uri }, { "CurrentURIMetaData", "" } })
    end
  end
  hs.timer.doAfter(SETTLE_DELAY, refresh)
end

-- The Beam back on its TV input: the TV should play in the living room and
-- nowhere else.
--
-- Setting a transport URI on a grouped *member* pulls it out of the group,
-- which is what this used to rely on. On a group *coordinator* the same call
-- does the opposite — it repoints the entire group at the new source. The Beam
-- is the coordinator more often than not (Sonos hands a home theatre the
-- coordinator role whenever the TV wakes it, and it keeps it while the rest of
-- the house is grouped onto the living room), and in that state this pushed the
-- TV's SPDIF feed onto every room at once: the Desk stopped carrying line-in
-- and went quiet with its transport still reading PLAYING. So evict the other
-- members explicitly first rather than assuming which role the Beam is in.
local function tvMode()
  local tv = sonos.findRoom(rooms, TV_ROOM)
  if not tv then
    hs.alert.show("No room called " .. TV_ROOM)
    return
  end
  for _, r in ipairs(rooms) do
    if r.coordinator == tv.coordinator and r.uuid ~= tv.uuid then
      call(r.ip, "AVTransport", "BecomeCoordinatorOfStandaloneGroup", {})
    end
  end
  call(tv.ip, "AVTransport", "SetAVTransportURI",
    { { "CurrentURI", sonos.tvUri(tv.uuid) }, { "CurrentURIMetaData", "" } },
    function()
      call(tv.ip, "AVTransport", "Play", { { "Speed", "1" } })
    end)
  hs.timer.doAfter(SETTLE_DELAY, refresh)
end

-- Panel -----------------------------------------------------------------------
--
-- One fullscreen canvas, for the same reason as the screenshot library: a
-- canvas only gets mouse events inside itself, and a fullscreen one gives the
-- dimmed backdrop, click-outside-to-dismiss, hover and — the reason it matters
-- here — a drag that keeps working after the pointer has wandered off the
-- slider, all from a single mouseCallback in one coordinate space.

-- Retained, same rule as every other canvas and timer in this config.
sonosPanelCanvas = nil
sonosPanelTimer  = nil
sonosPanelPoll   = nil
sonosPanelKeys   = nil
sonosFlashTimer  = nil
sonosDragTap     = nil   -- eventtap driving a slider drag; see startDrag
sonosDragTimer   = nil   -- coalesces drag repaints down to frame rate

local panelRings = nil
local ringsT0    = nil          -- kept across rebuilds so the pulse doesn't restart
local fingerprint = nil         -- of the rooms currently drawn
local rowLayout   = {}          -- per row: track x, y, for the drag maths
local dragging    = nil         -- row index while the mouse is down on a slider
local stopDrag                  -- forward declaration: closePanel tears a drag down
local screenFrame = nil

local BUTTONS = {
  { id = "group",     key = "g", label = "Group all → " .. DESK_ROOM, fn = groupAllToDesk },
  { id = "tv",        key = "t", label = "TV mode",                    fn = tvMode },
  { id = "calibrate", key = "c", label = "Calibrate",                  fn = calibrateRooms },
  { id = "clearCalibration", key = "x", label = "Clear Calibration",   fn = clearCalibration },
  { id = "lock",      key = "l", label = "Lock",                       fn = function() setLocked(not locked) end },
}

local function sourceText(r)
  if not r.isCoordinator then
    local coord
    for _, o in ipairs(rooms) do
      if o.uuid == r.coordinator then coord = o end
    end
    return "with " .. (coord and coord.name or "group")
  end
  if r.source == "" then return "idle" end
  if r.state == "PLAYING" then return r.source end
  return r.source .. " · paused"
end

local function closePanel()
  if sonosPanelTimer then sonosPanelTimer:stop(); sonosPanelTimer = nil end
  if sonosPanelPoll  then sonosPanelPoll:stop();  sonosPanelPoll  = nil end
  if sonosFlashTimer then sonosFlashTimer:stop(); sonosFlashTimer = nil end
  if sonosPanelKeys then
    for _, k in ipairs(sonosPanelKeys) do k:disable() end
  end
  stopDrag()
  panelRings, fingerprint = nil, nil
  rowLayout = {}
  if sonosPanelCanvas then
    sonosPanelCanvas:delete()
    sonosPanelCanvas = nil
  end
end

local function fillWidth(volume)
  return math.max(0, math.min(SLIDER_W, SLIDER_W * volume / 100))
end

-- The three elements a volume change moves. Split out from paintRow because a
-- drag repaints at frame rate and the source label can't change mid-drag —
-- restyling it every frame is a styledtext build and a canvas redraw for text
-- that is already correct.
local function paintSlider(c, i, r)
  local L = rowLayout[i]
  if not (c and r and L) then return end
  local w = fillWidth(r.volume)
  c["fill:" .. i].frame = { x = L.trackX, y = L.trackY, w = w, h = TRACK_H }
  c["knob:" .. i].center = { x = L.trackX + w, y = L.trackY + TRACK_H / 2 }
  c["num:" .. i].text = ui.styled(tostring(r.volume), theme.text.body, ui.fg, { align = "right" })
end

-- Paint one row's numbers into existing elements.
local function paintRow(c, i, r)
  if not rowLayout[i] then return end
  paintSlider(c, i, r)
  c["src:" .. i].text = ui.styled(sourceText(r), theme.text.caption, ui.muted)
end

-- Reading the pointer and moving the knob are deliberately separate.
--
-- A canvas only hears the mouse through its own tracking areas: every move is
-- hit-tested against every element and the leftovers are coalesced, so a quick
-- drag arrives as a handful of widely spaced positions — the knob lands on 59,
-- then 74, and never the points between. A drag therefore runs off an eventtap
-- (startDrag), which sees every move the mouse actually makes.
--
-- That leaves the opposite problem: mouse moves outrun the display, and each
-- element assignment redraws a canvas the size of the screen. So dragTo only
-- moves the model and marks it dirty; a frame-rate timer does the painting.
local dragDirty = false

-- Paints whatever a drag last touched: just the dragged row normally, or
-- every currently-painted room when locked, since dragTo below moved all of
-- them together.
local function paintDragged(i)
  if not sonosPanelCanvas then return end
  if locked then
    for j, o in ipairs(rooms) do
      if rowLayout[j] then paintSlider(sonosPanelCanvas, j, o) end
    end
  elseif rooms[i] then
    paintSlider(sonosPanelCanvas, i, rooms[i])
  end
end

local function dragTo(i)
  local r, L = rooms[i], rowLayout[i]
  if not (sonosPanelCanvas and r and L) then return end
  local x = hs.mouse.absolutePosition().x - screenFrame.x
  local v = sonos.volumeFromX(x, L.trackX, SLIDER_W)
  if v == r.volume then return end
  r.volume = v
  dragDirty = true
  setVolume(r, sonos.rawVolume(v, baselines[r.uuid]))
  if locked then
    -- Every other visible room snaps to the same displayed percentage,
    -- through its own baseline — matching percentage is the whole point.
    for j, o in ipairs(rooms) do
      if j ~= i and rowLayout[j] and o.volume ~= v then
        o.volume = v
        setVolume(o, sonos.rawVolume(v, baselines[o.uuid]))
      end
    end
  end
end

function stopDrag()
  if sonosDragTap then sonosDragTap:stop(); sonosDragTap = nil end
  if sonosDragTimer then sonosDragTimer:stop(); sonosDragTimer = nil end
  dragging, dragDirty = nil, false
end

local function endDrag()
  local i = dragging
  stopDrag()
  if i and sonosPanelCanvas and rooms[i] then
    dragTo(i)          -- take the release position
    paintDragged(i)    -- and land on it (every locked room, or just this one)
  end
end

local function startDrag(i)
  stopDrag()
  dragging = i
  dragTo(i)
  sonosDragTimer = hs.timer.doEvery(ui.FRAME_INTERVAL, function()
    if dragDirty and dragging and sonosPanelCanvas and rooms[dragging] then
      dragDirty = false
      paintDragged(dragging)
    end
  end)
  local types = hs.eventtap.event.types
  sonosDragTap = hs.eventtap.new({ types.leftMouseDragged, types.leftMouseUp }, function(e)
    if not dragging then return false end
    if e:getType() == types.leftMouseUp then
      endDrag()
    else
      dragTo(dragging)
    end
    return false   -- never swallow a real click
  end):start()
end

local function buttonLabel(id)
  for _, b in ipairs(BUTTONS) do
    if b.id == id then return b.label end
  end
  return ""
end

local function buttonLabelStyle(id, color)
  return ui.styled(buttonLabel(id), theme.text.body, color, { font = theme.font.semibold, align = "center" })
end

-- Only the Lock button has a persistent on/off state; everything else settles
-- back to the plain chip look once its press-flash ends.
local function buttonActive(id)
  return id == "lock" and locked
end

-- Paints a button's resting look — accent-filled while "on" (same look
-- flashButton uses for a press, just held), the recessed chip otherwise.
local function paintButtonState(c, id)
  local on = buttonActive(id)
  c["btnfill:" .. id].fillColor = on and ui.accent or ui.chipColor
  c["btnedge:" .. id].strokeColor = on and ui.accent or ui.chipEdge
  c["btntext:" .. id].text = buttonLabelStyle(id, on and ui.onAccent or ui.fg)
end

local function flashButton(c, id, fn)
  c["btnfill:" .. id].fillColor = ui.accent
  c["btnedge:" .. id].strokeColor = ui.accent
  c["btntext:" .. id].text = buttonLabelStyle(id, ui.onAccent)
  if sonosFlashTimer then sonosFlashTimer:stop() end
  sonosFlashTimer = hs.timer.doAfter(FLASH_HOLD, function()
    sonosFlashTimer = nil
    if sonosPanelCanvas ~= c then return end
    paintButtonState(c, id)
  end)
  fn()
end

local function runButton(id)
  for _, b in ipairs(BUTTONS) do
    if b.id == id and sonosPanelCanvas then
      flashButton(sonosPanelCanvas, id, b.fn)
    end
  end
end

-- Flips the lock and repaints the button to match. fn() in BUTTONS runs
-- inside flashButton's press-flash, so the button lands on this resting
-- state the moment the flash ends; setting it here too covers the paths that
-- don't go through a button press (clearCalibration, and openPanel resetting
-- it on close/reopen).
setLocked = function(v)
  locked = v
  if sonosPanelCanvas then paintButtonState(sonosPanelCanvas, "lock") end
end

-- The one mouse handler. Element ids are stable, so everything mutates
-- elements in place rather than rebuilding. Pointer position comes from
-- hs.mouse rather than the callback's x/y so a drag has the same maths whether
-- the event arrived via the slider's hit rect or fell through to the backdrop.
local function onMouse(c, event, id)
  if type(id) ~= "string" or c ~= sonosPanelCanvas then return end
  local volRow = tonumber(id:match("^vol:(%d+)$"))
  local btn = id:match("^btn:(%w+)$")

  if event == "mouseDown" then
    if volRow then
      startDrag(volRow)
    elseif btn then
      runButton(btn)
    elseif id == "backdrop" and not dragging then
      closePanel()
    end
  elseif event == "mouseMove" then
    if dragging then
      dragTo(dragging)
      if not sonosDragTap then paintSlider(c, dragging, rooms[dragging]) end
    end
  elseif event == "mouseUp" then
    if dragging then endDrag() end
  elseif event == "mouseEnter" and btn then
    c["btnedge:" .. btn].strokeColor = ui.accent
  elseif event == "mouseExit" and btn then
    c["btnedge:" .. btn].strokeColor = ui.chipEdge
  end
end

-- Build the whole canvas for `list`. Called on open (with whatever is known,
-- usually nothing yet) and again whenever the topology changes shape.
local function build(list)
  local hadCanvas = sonosPanelCanvas ~= nil
  if sonosPanelCanvas then
    sonosPanelCanvas:delete()
    sonosPanelCanvas = nil
  end
  panelRings = nil
  rowLayout = {}
  stopDrag()

  -- Measure the name column from the longest name, like the cheatsheet does
  -- for its labels; the other columns are fixed.
  local names, nameW = {}, NAME_MIN_W
  for i, r in ipairs(list) do
    local prefix = r.isCoordinator and "" or "↳  "
    names[i] = ui.styled(prefix .. r.name, theme.text.label, r.isCoordinator and ui.fg or ui.muted)
    nameW = math.max(nameW, ui.width(names[i]) + 2)
  end

  local btnText, btnW = {}, {}
  local btnRowW = 0
  for i, b in ipairs(BUTTONS) do
    btnText[b.id] = ui.styled(b.label, theme.text.body, ui.fg, { font = theme.font.semibold, align = "center" })
    btnW[b.id] = ui.width(btnText[b.id]) + BTN_PAD * 2
    btnRowW = btnRowW + btnW[b.id] + (i > 1 and BTN_GAP or 0)
  end
  btnRowW = PAD * 2 + btnRowW

  local nRows = math.max(#list, 1)
  local rowW = PAD * 2 + nameW + GAP + SRC_W + GAP + SLIDER_W + GAP + NUM_W
  local cardW = math.max(rowW, btnRowW)
  local cardH = HEADER_H + nRows * ROW_H + FOOTER_H

  screenFrame = hs.screen.mainScreen():frame()
  local screen = screenFrame
  local cx = math.floor((screen.w - cardW) / 2)
  local cy = math.floor((screen.h - cardH) * 0.33)

  local c = hs.canvas.new(screen)
  c:level(hs.canvas.windowLevels.screenSaver)
  c:behavior({ "canJoinAllSpaces", "stationary" })

  -- The backdrop also tracks move and up: a drag that leaves the slider's own
  -- hit rect keeps arriving here, and a release anywhere ends it.
  local backdrop = ui.backdrop()
  backdrop.trackMouseMove = true
  backdrop.trackMouseUp = true
  c[#c + 1] = backdrop

  local cardFrame = { x = cx, y = cy, w = cardW, h = cardH }
  panelRings = ui.rings(c, cardFrame)
  c[#c + 1] = ui.surface(cardFrame)
  c[#c + 1] = ui.border(cardFrame)

  -- Header, laid out like the other two: tracked-out title left, detail right,
  -- hairline under both.
  c[#c + 1] = ui.text(ui.title("SONOS"),
    { x = cx + PAD, y = cy + PAD - 4, w = cardW - PAD * 2, h = 18 })
  c[#c + 1] = ui.text(
    ui.styled("g group  ·  t tv  ·  c calibrate  ·  x clear calibration  ·  l lock  ·  esc to close", theme.text.caption, ui.muted, { align = "right" }),
    { x = cx + PAD, y = cy + PAD - 2, w = cardW - PAD * 2, h = 16 })
  c[#c + 1] = ui.rule(cx + PAD, cy + HEADER_H - 14, cardW - PAD * 2)

  if #list == 0 then
    local msg = hadCanvas and "No speakers found" or "Looking for speakers…"
    c[#c + 1] = ui.text(ui.styled(msg, theme.text.label, ui.muted),
      { x = cx + PAD, y = cy + HEADER_H + (ROW_H - 18) / 2, w = cardW - PAD * 2, h = 20 })
  end

  local srcX    = cx + PAD + nameW + GAP
  local trackX  = srcX + SRC_W + GAP
  local numX    = trackX + SLIDER_W + GAP
  for i, r in ipairs(list) do
    local y = cy + HEADER_H + (i - 1) * ROW_H
    local trackY = y + (ROW_H - TRACK_H) / 2
    rowLayout[i] = { trackX = trackX, trackY = trackY, y = y }

    c[#c + 1] = ui.text(names[i], { x = cx + PAD, y = y + (ROW_H - 18) / 2, w = nameW, h = 20 })
    c[#c + 1] = ui.text(ui.styled(sourceText(r), theme.text.caption, ui.muted),
      { x = srcX, y = y + (ROW_H - 16) / 2 + 1, w = SRC_W, h = 16 }, "src:" .. i)

    -- The slider: a recessed track (the same chip as a keycap, just thin), the
    -- filled part in accent, a knob on the end. Nothing here is interactive —
    -- the hit rect below is, and it covers the whole row's right half so a
    -- drag doesn't have to stay on a six-point line.
    local w = fillWidth(r.volume)
    c[#c + 1] = ui.chip({ x = trackX, y = trackY, w = SLIDER_W, h = TRACK_H }, { radius = TRACK_H / 2 })
    c[#c + 1] = ui.chip({ x = trackX, y = trackY, w = w, h = TRACK_H },
                        { radius = TRACK_H / 2, color = ui.accent, id = "fill:" .. i })
    c[#c + 1] = { type = "circle", action = "fill", id = "knob:" .. i,
                  center = { x = trackX + w, y = trackY + TRACK_H / 2 }, radius = KNOB_R,
                  fillColor = ui.fg }
    c[#c + 1] = ui.text(ui.styled(tostring(r.volume), theme.text.body, ui.fg, { align = "right" }),
      { x = numX, y = y + (ROW_H - 18) / 2, w = NUM_W, h = 20 }, "num:" .. i)
    c[#c + 1] = { type = "rectangle", action = "fill", id = "vol:" .. i,
                  fillColor = ui.color(theme.color.accent, 0), trackMouseByBounds = true,
                  trackMouseDown = true, trackMouseUp = true, trackMouseMove = true,
                  frame = { x = trackX - KNOB_R * 2, y = y, w = SLIDER_W + KNOB_R * 4 + GAP + NUM_W, h = ROW_H } }
  end

  -- Footer: hairline, then the two buttons as recessed chips with a keycap's
  -- edge, lit in accent on hover and inverted for a beat on press.
  local footY = cy + HEADER_H + nRows * ROW_H
  c[#c + 1] = ui.rule(cx + PAD, footY, cardW - PAD * 2)
  local bx = cx + PAD
  local by = footY + 14
  for _, b in ipairs(BUTTONS) do
    local frame = { x = bx, y = by, w = btnW[b.id], h = BTN_H }
    c[#c + 1] = ui.chip(frame, { id = "btnfill:" .. b.id })
    c[#c + 1] = ui.border(frame, { radius = theme.radius.control, color = ui.chipEdge, id = "btnedge:" .. b.id })
    c[#c + 1] = ui.text(btnText[b.id], { x = bx, y = by + (BTN_H - 18) / 2, w = btnW[b.id], h = 20 }, "btntext:" .. b.id)
    c[#c + 1] = { type = "rectangle", action = "fill", id = "btn:" .. b.id,
                  fillColor = ui.color(theme.color.accent, 0), trackMouseByBounds = true,
                  trackMouseDown = true, trackMouseEnterExit = true, frame = frame }
    bx = bx + btnW[b.id] + BTN_GAP
  end
  paintButtonState(c, "lock")   -- built with the resting look above; fix it up if locked

  c:mouseCallback(onMouse)

  sonosPanelCanvas = c
  fingerprint = sonos.fingerprint(list)
  c:show()

  ringsT0 = ringsT0 or hs.timer.secondsSinceEpoch()
  if not sonosPanelTimer then
    sonosPanelTimer = hs.timer.doEvery(ui.FRAME_INTERVAL, function()
      if panelRings then panelRings.tick(hs.timer.secondsSinceEpoch() - ringsT0) end
    end)
  end
end

-- A finished read lands here. Same rooms in the same groups: paint numbers in
-- place, skipping a row mid-drag so the poll can't yank the knob back. Anything
-- else: rebuild.
apply = function(list)
  if not sonosPanelCanvas then return end
  rooms = list
  if sonos.fingerprint(list) == fingerprint and #list > 0 then
    for i, r in ipairs(list) do
      if i ~= dragging then paintRow(sonosPanelCanvas, i, r) end
    end
  else
    build(list)
  end
end

local function openPanel()
  closePanel()
  ringsT0 = nil
  rooms = {}
  locked = false   -- never silently on for a freshly opened panel; see `locked` above
  build({})
  if not sonosPanelKeys then
    sonosPanelKeys = { hs.hotkey.new({}, "escape", closePanel) }
    for _, b in ipairs(BUTTONS) do
      sonosPanelKeys[#sonosPanelKeys + 1] = hs.hotkey.new({}, b.key, function() runButton(b.id) end)
    end
  end
  for _, k in ipairs(sonosPanelKeys) do k:enable() end

  if #knownIps > 0 then refresh() end   -- instant on a reopen; discovery corrects it
  discover(function() refresh() end)
  sonosPanelPoll = hs.timer.doEvery(POLL_INTERVAL, function()
    if not dragging then refresh() end
  end)
end

-- Exposed for `hs -c 'sonosPanel.open()'`, which is how the layout gets
-- checked without a keypress; `.group()` and `.tv()` fire the moves headless.
sonosPanel = {
  open = openPanel, close = closePanel, refresh = refresh,
  group = groupAllToDesk, tv = tvMode,
  rooms = function() return rooms end,
  -- Synthetic clicks never reach a canvas, so this is how the mouse paths get
  -- exercised headless: park the pointer, then feed the event by element id.
  mouse = function(event, id) onMouse(sonosPanelCanvas, event, id) end,
}

hyper.bind("s", "Sonos", function()
  if sonosPanelCanvas then closePanel() else openPanel() end
end)
