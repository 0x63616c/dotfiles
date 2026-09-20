-- EmmyLua annotations for the hs.* API ---------------------------------------
--
-- EmmyLua.spoon walks Hammerspoon's own docs.json (and the docs.json of every
-- installed Spoon) and writes one annotation stub per module into
-- Spoons/EmmyLua.spoon/annotations/. Those stubs are what gives an editor
-- completion, signatures and hover docs for `hs.*` — without them a language
-- server sees `hs` as an undefined global and every call as a guess.
--
-- The stubs are generated output, not source: they are regenerated whenever
-- Hammerspoon updates (the Spoon compares mtimes and skips anything current),
-- so they are gitignored rather than committed. Editor side, .emmyrc.json
-- points `workspace.library` at that directory.
--
-- Load order matters here. Modules load alphabetically, so this file runs
-- before reload.lua installs its pathwatcher — the first generation writes
-- several hundred .lua files, and a watcher already running would read that as
-- a config change and reload mid-write. reload.lua also ignores the Spoons
-- directory outright, which covers a regeneration triggered any other way.

local log = hs.logger.new("annotations", "info")

local ok, err = pcall(function()
  hs.loadSpoon("EmmyLua")
end)

if not ok then
  -- Not fatal: a missing or broken annotations Spoon costs editor completion,
  -- nothing at runtime. Reinstall with the EmmyLua.spoon zip from
  -- github.com/Hammerspoon/Spoons.
  log.e("EmmyLua.spoon failed to load, hs.* completion will be stale: " .. tostring(err))
end
