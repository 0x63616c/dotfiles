-- Sonos, the pure half: the UPnP/SOAP envelopes the speakers speak, the
-- topology parser, and the labelling of what a room is playing. Everything the
-- panel in sonos.lua needs that doesn't touch the network or a canvas.
--
-- Sonos speakers answer plain HTTP on port 1400 with no auth and no cloud —
-- SOAP envelopes POSTed to a handful of control paths. The recipes here were
-- verified against the real hardware (see the notes in the control-center
-- repo's docs/media-tiles/INTEGRATION-NOTES.md): grouping is a member setting
-- its transport URI to `x-rincon:<coordinator>`, line-in is `x-rincon-stream`,
-- the Beam's TV feed is `x-sonos-htastream:<uuid>:spdif`.
--
-- Deliberately free of any `hs.*` reference, like the rest of lib/: this loads
-- in a bare interpreter so hammerspoon/tests can exercise the parsing without
-- a speaker on the network. Keep it that way.

local M = {}

-- Services --------------------------------------------------------------------

M.services = {
  AVTransport      = "/MediaRenderer/AVTransport/Control",
  RenderingControl = "/MediaRenderer/RenderingControl/Control",
  ZoneGroupTopology = "/ZoneGroupTopology/Control",
}

local function escape(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- XML entities as they come back inside a SOAP response. The topology in
-- particular arrives double-encoded: an XML document escaped into a text node.
function M.unescape(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
           :gsub("&apos;", "'"):gsub("&amp;", "&"))
end

-- One SOAP request: the path to POST to, the headers, and the body. `args` is
-- an ordered list of { name, value } pairs — order matters to UPnP, which
-- validates arguments positionally against the service description.
function M.request(service, action, args)
  local path = M.services[service]
  assert(path, "sonos: unknown service " .. tostring(service))
  local urn = "urn:schemas-upnp-org:service:" .. service .. ":1"
  local parts = { "<InstanceID>0</InstanceID>" }
  for _, arg in ipairs(args or {}) do
    parts[#parts + 1] = "<" .. arg[1] .. ">" .. escape(arg[2]) .. "</" .. arg[1] .. ">"
  end
  local body = '<?xml version="1.0"?>'
    .. '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
    .. ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
    .. '<u:' .. action .. ' xmlns:u="' .. urn .. '">' .. table.concat(parts)
    .. '</u:' .. action .. '></s:Body></s:Envelope>'
  return {
    path = path,
    body = body,
    headers = {
      ["Content-Type"] = 'text/xml; charset="utf-8"',
      SOAPACTION = '"' .. urn .. "#" .. action .. '"',
    },
  }
end

-- The text of one tag in a response, or nil.
function M.value(xml, tag)
  if type(xml) ~= "string" then return nil end
  return xml:match("<" .. tag .. ">(.-)</" .. tag .. ">")
end

-- Transport URIs ----------------------------------------------------------------

function M.groupUri(coordinatorUuid)  return "x-rincon:" .. coordinatorUuid end
function M.lineInUri(uuid)            return "x-rincon-stream:" .. uuid .. ":0" end
function M.tvUri(uuid)                return "x-sonos-htastream:" .. uuid .. ":spdif" end

-- What a coordinator is playing, as a short label for the row. Line-in and TV
-- carry no track metadata at all (title/artist/duration all NOT_IMPLEMENTED),
-- so the source is the only thing there is to say about them.
local SOURCES = {
  { "^x%-sonos%-htastream:",  "TV" },
  { "^x%-rincon%-stream:",    "Line-in" },
  { "^x%-sonos%-spotify:",    "Spotify" },
  { "^x%-sonosapi%-radio:",   "Radio" },
  { "^x%-rincon%-mp3radio:",  "Radio" },
  { "^x%-sonosapi%-stream:",  "Radio" },
  { "^x%-rincon%-queue:",     "Queue" },
  { "^x%-sonos%-http:",       "Stream" },
  { "^x%-sonosprog%-http:",   "Stream" },
  { "^x%-sonosapi%-hls",      "Stream" },
  { "^x%-rincon:",            "Grouped" },
}

function M.sourceLabel(uri)
  if not uri or uri == "" then return "" end
  for _, s in ipairs(SOURCES) do
    if uri:match(s[1]) then return s[2] end
  end
  return "Playing"
end

-- Topology --------------------------------------------------------------------
--
-- GetZoneGroupState returns, escaped into a text node, a document of
-- <ZoneGroup Coordinator=... ID=...> elements each holding one or more
-- <ZoneGroupMember .../>. A stereo pair's second speaker is a member with
-- Invisible="1" and is dropped: it has no volume or transport of its own that
-- a person would want to touch, and showing "Desk" twice is just confusing.
--
-- Returns a flat, display-ordered list of rooms:
--   { name, uuid, ip, coordinator = <uuid>, isCoordinator = bool }
-- Groups are sorted by coordinator name, and within a group the coordinator
-- comes first with its members after it — the shape the panel draws.

local function attrs(s)
  local t = {}
  for k, v in s:gmatch('([%w_]+)="([^"]*)"') do t[k] = v end
  return t
end

function M.parseTopology(xml)
  local state = M.value(xml, "ZoneGroupState")
  if not state then return {} end
  state = M.unescape(state)

  local groups = {}
  for coord, inner in state:gmatch('<ZoneGroup Coordinator="([^"]+)"[^>]*>(.-)</ZoneGroup>') do
    local members = {}
    for tag in inner:gmatch("<ZoneGroupMember%s([^>]-)/?>") do
      local a = attrs(tag)
      if a.Invisible ~= "1" and a.UUID and a.ZoneName then
        members[#members + 1] = {
          name = M.unescape(a.ZoneName),
          uuid = a.UUID,
          ip = a.Location and a.Location:match("http://([%d%.]+):") or nil,
          coordinator = coord,
          isCoordinator = a.UUID == coord,
        }
      end
    end
    table.sort(members, function(x, y)
      if x.isCoordinator ~= y.isCoordinator then return x.isCoordinator end
      return x.name < y.name
    end)
    if #members > 0 then
      groups[#groups + 1] = { coordinator = coord, members = members }
    end
  end
  table.sort(groups, function(x, y) return x.members[1].name < y.members[1].name end)

  local rooms = {}
  for _, g in ipairs(groups) do
    for _, m in ipairs(g.members) do rooms[#rooms + 1] = m end
  end
  return rooms
end

function M.findRoom(rooms, name)
  for _, r in ipairs(rooms) do
    if r.name == name then return r end
  end
  return nil
end

-- A stable fingerprint of the room list, so the panel can tell "same rooms,
-- new numbers" (update in place) from "the topology changed" (rebuild).
function M.fingerprint(rooms)
  local keys = {}
  for i, r in ipairs(rooms) do keys[i] = r.uuid .. ">" .. r.coordinator end
  return table.concat(keys, "|")
end

-- Sliders ---------------------------------------------------------------------

-- Mouse x along a track -> 0..100, clamped, so a drag past either end pins.
function M.volumeFromX(x, trackX, trackW)
  if trackW <= 0 then return 0 end
  local v = (x - trackX) / trackW * 100
  if v < 0 then v = 0 elseif v > 100 then v = 100 end
  return math.floor(v + 0.5)
end

-- Calibration -------------------------------------------------------------
--
-- Raw Sonos volume (0-100) doesn't mean the same loudness on every speaker
-- model, so a room can be calibrated: its baseline is double the raw volume
-- it was at the moment "equally loud" was declared (M.calibratedBaseline),
-- so that moment reads as 50% rather than pinning the slider's ceiling at
-- however loud the room happened to be, and from then on the panel
-- shows/drives a percentage of that baseline instead of the raw number.
--
-- A missing or zero baseline means "not calibrated" and both directions
-- pass the value straight through (clamped, for the raw direction) — zero
-- would otherwise be a divide-by-zero, which is why callers must never
-- store one (a room calibrated while muted keeps its previous baseline, or
-- none).

-- Raw -> the percentage to display. Deliberately uncapped above 100: a room
-- that's gotten louder than its calibration (someone bumped it from the
-- Sonos app) reads as ">100%", which *is* the signal that it's past its
-- calibrated ceiling, rather than a clamp hiding it.
function M.displayVolume(raw, baseline)
  if not baseline or baseline == 0 then return raw end
  return math.floor(raw / baseline * 100 + 0.5)
end

-- The inverse: a displayed/dragged percentage -> the raw value to actually
-- send. Always clamped to Sonos' real 0-100 range, since a calibrated room
-- showing >100% (or a drag pinned at the slider's 100 end) would otherwise
-- ask for a raw volume above what a speaker accepts.
function M.rawVolume(display, baseline)
  local raw = (not baseline or baseline == 0) and display or (display * baseline / 100)
  raw = math.floor(raw + 0.5)
  if raw < 0 then raw = 0 elseif raw > 100 then raw = 100 end
  return raw
end

-- What calibrateRooms stores as a room's new baseline, given the raw volume
-- it read at the moment of calibration: double it, so that moment reads back
-- as 50% and there's headroom to go louder, but never past 100 — raw*2 only
-- clears 100 when raw itself was already past 50, and rawVolume already
-- clamps what gets SENT to a speaker at 100. If the stored baseline weren't
-- clamped too, that same sent raw would redisplay via displayVolume against
-- the uncapped baseline as something under 100%, snapping the slider visibly
-- backward even though the speaker is genuinely at max.
function M.calibratedBaseline(raw)
  return math.min(raw * 2, 100)
end

return M
