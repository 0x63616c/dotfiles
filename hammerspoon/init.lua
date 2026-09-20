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

require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")

local log = hs.logger.new("micwatch", "debug")

local MEDIA_CONTROL = "/opt/homebrew/bin/media-control"

micState = {
  dictating = false,
  userToggled = false,
  mcPaused = false,   -- we paused a MediaRemote app
  session = 0,
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
  end, { "get", "--no-artwork" }):start()
end

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
  mcIsPlaying(function(playing)
    if playing and micState.dictating and not micState.userToggled
      and session == micState.session then
      log.d("MediaRemote app playing -> pause")
      mcCommand("pause")
      micState.mcPaused = true
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
    end
  end
  micState.mcPaused = false
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

-- Auto-reload on config change ----------------------------------------------
--
-- Editing this file does nothing until something calls hs.reload(): init.lua is
-- only executed at load. Without this watcher every change needs a trip to the
-- menubar (or `hs -c 'hs.reload()'`), which is easy to forget and makes an edit
-- look like it simply didn't work.
--
-- Filter on `.lua` so editor noise (swap files, `.lua~`, Finder metadata) can't
-- put us in a reload loop. Reload is debounced through hs.timer.delayed: a save
-- fires several FSEvents and a multi-file write fires more, and each one would
-- otherwise tear down and rebuild the whole Lua state.
--
-- ~/.hammerspoon is a symlink to this repo, so FSEvents reports the resolved
-- repo path, not the symlink — never match on a path prefix here, only on the
-- extension.
--
-- Global, like the watchers above: an unreferenced pathwatcher is garbage-
-- collected and stops firing silently.

local reloadTimer = hs.timer.delayed.new(0.4, function()
  log.i("config changed -> reload")
  hs.reload()
end)

configWatcher = hs.pathwatcher.new(hs.configdir, function(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      reloadTimer:start()  -- restarts the countdown; fires once the writes settle
      return
    end
  end
end):start()
