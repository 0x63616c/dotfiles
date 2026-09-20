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
-- repo path, not the symlink — never match on an absolute path prefix here,
-- only on the extension and on path components that survive resolution.
--
-- Spoons/ is excluded for that reason: EmmyLua.spoon regenerates several
-- hundred annotation .lua files whenever Hammerspoon updates, and every one of
-- them would otherwise land here as a config change.
--
-- Global, like the watchers above: an unreferenced pathwatcher is garbage-
-- collected and stops firing silently.

local log = hs.logger.new("reload", "info")

local reloadTimer = hs.timer.delayed.new(0.4, function()
  log.i("config changed -> reload")
  hs.reload()
end)

configWatcher = hs.pathwatcher.new(hs.configdir, function(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" and not file:find("/Spoons/", 1, true) then
      reloadTimer:start()  -- restarts the countdown; fires once the writes settle
      return
    end
  end
end):start()
