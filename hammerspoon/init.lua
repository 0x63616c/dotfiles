-- Auto pause/resume media around dictation (Wispr Flow).
--
-- Watches the default microphone's in-use state. When any app grabs the
-- mic (Wispr Flow recording), send a play/pause toggle to pause whatever
-- is playing (Spotify, YouTube, anything). When the mic is released,
-- toggle again to resume.
--
-- Toggles fire in mic-on/mic-off pairs so playback state can't desync.
-- If dictation fails to start, the mic never activates and nothing
-- happens. If you press the play/pause media key yourself while
-- dictating, the auto-resume is skipped — you took control.

require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")

local log = hs.logger.new("micwatch", "debug")

micState = { dictating = false, userToggled = false }

local function pressPlayPause()
  hs.task.new("/opt/homebrew/bin/media-control", nil, { "toggle-play-pause" }):start()
end

local function micInUse()
  local dev = hs.audiodevice.defaultInputDevice()
  return dev ~= nil and dev:inUse()
end

micWatcher = hs.timer.doEvery(0.3, function()
  local inUse = micInUse()
  if inUse == micState.dictating then return end
  micState.dictating = inUse

  if inUse then
    micState.userToggled = false
    log.d("mic grabbed -> pausing media")
    pressPlayPause()
  elseif micState.userToggled then
    log.d("mic released, but user toggled during dictation -> leaving as-is")
  else
    log.d("mic released -> resuming media")
    pressPlayPause()
  end
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
