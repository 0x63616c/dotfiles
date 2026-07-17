-- Auto pause/resume media around dictation (Wispr Flow).
--
-- Watches the default microphone's in-use state. When any app grabs the
-- mic (Wispr Flow recording), pause what's actually playing; when the
-- mic is released, resume exactly what was paused. If dictation fails
-- to start, the mic never activates and nothing happens.
--
-- Two playback sources, each handled deterministically (no blind
-- toggles, so a paused video is never accidentally started):
--
--  * MediaRemote apps (Spotify, Music, ...): state read via
--    `media-control get`, paused/resumed with `media-control pause/play`.
--  * Chrome video tabs (YouTube): MediaRemote is blind to Chrome on
--    macOS 26, so playing videos are found and paused/resumed via
--    AppleScript-injected JavaScript. Requires Chrome menu:
--    View > Developer > Allow JavaScript from Apple Events.
--
-- Pressing the physical play/pause media key mid-dictation means you
-- took control: the auto-resume is skipped.

require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")

local log = hs.logger.new("micwatch", "debug")

local MEDIA_CONTROL = "/opt/homebrew/bin/media-control"

micState = {
  dictating = false,
  userToggled = false,
  mcPaused = false,   -- we paused a MediaRemote app
  chromeTabs = {},    -- Chrome tab ids whose videos we paused
}

-- MediaRemote source (Spotify etc.) -----------------------------------------

local function mcCommand(cmd)
  hs.task.new(MEDIA_CONTROL, nil, { cmd }):start()
end

local function mcIsPlaying(callback)
  hs.task.new(MEDIA_CONTROL, function(exitCode, stdout)
    local ok, info = pcall(hs.json.decode, stdout or "")
    callback(exitCode == 0 and ok and type(info) == "table"
      and info.playbackRate ~= nil and info.playbackRate > 0)
  end, { "get" }):start()
end

-- Chrome video tabs ----------------------------------------------------------

local function chromeRunning()
  return hs.application.get("Google Chrome") ~= nil
end

-- Pause every playing video in YouTube tabs; return their tab ids.
local function chromePausePlayingVideos()
  if not chromeRunning() then return {} end
  local ok, result = hs.osascript.applescript([[
    tell application "Google Chrome"
      set pausedTabs to {}
      repeat with w in windows
        repeat with t in tabs of w
          if URL of t contains "youtube.com/watch" then
            try
              set r to execute t javascript "(() => { const v = document.querySelector('video'); if (v && !v.paused) { v.pause(); return 'paused'; } return 'no'; })()"
              if r is "paused" then set end of pausedTabs to (id of t)
            end try
          end if
        end repeat
      end repeat
      return pausedTabs
    end tell
  ]])
  if not ok or type(result) ~= "table" then return {} end
  return result
end

local function chromeResumeVideos(tabIds)
  if #tabIds == 0 or not chromeRunning() then return end
  local idList = table.concat(tabIds, ", ")
  hs.osascript.applescript(string.format([[
    tell application "Google Chrome"
      repeat with w in windows
        repeat with t in tabs of w
          if {%s} contains (id of t) then
            try
              execute t javascript "document.querySelector('video') && document.querySelector('video').play()"
            end try
          end if
        end repeat
      end repeat
    end tell
  ]], idList))
end

-- Mic watcher ----------------------------------------------------------------

local function micInUse()
  local dev = hs.audiodevice.defaultInputDevice()
  return dev ~= nil and dev:inUse()
end

function onMicGrabbed()
  micState.userToggled = false
  micState.mcPaused = false
  mcIsPlaying(function(playing)
    if playing then
      log.d("MediaRemote app playing -> pause")
      mcCommand("pause")
      micState.mcPaused = true
    end
  end)
  micState.chromeTabs = chromePausePlayingVideos()
  if #micState.chromeTabs > 0 then
    log.df("paused %d Chrome video tab(s)", #micState.chromeTabs)
  end
end

function onMicReleased()
  if micState.userToggled then
    log.d("user toggled during dictation -> leaving playback as-is")
  else
    if micState.mcPaused then
      log.d("resuming MediaRemote app")
      mcCommand("play")
    end
    chromeResumeVideos(micState.chromeTabs)
  end
  micState.mcPaused = false
  micState.chromeTabs = {}
end

micWatcher = hs.timer.doEvery(0.3, function()
  local inUse = micInUse()
  if inUse == micState.dictating then return end
  micState.dictating = inUse
  log.df("mic inUse -> %s", tostring(inUse))
  if inUse then onMicGrabbed() else onMicReleased() end
end)

-- Physical media-key presses (the F8-position play/pause key).
mediaKeyTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
  local key = e:systemKey()
  if key and key.down and (key.key == "PLAY" or key.key == "PAUSE") and micState.dictating then
    micState.userToggled = true
    log.d("user pressed play/pause during dictation")
  end
  return false
end):start()
