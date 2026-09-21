-- Bootstrap only. Every other .lua file in this directory is a feature module
-- and is loaded automatically below, so adding a feature means dropping in a
-- file — there is no list here to keep in sync.
--
-- What lives where:
--   capslock.lua   Caps Lock (remapped to F18) -> Hyper, replacing Hyperkey
--   dictation.lua  auto pause/resume media + the on-screen dictation indicator
--   doubleshift.lua both Shifts held -> toggle real Caps Lock
--   hyper.lua      Hyper-key shortcuts and their registry
--   reload.lua     reload this config when any .lua here is saved
--   screenshots.lua screenshots -> clipboard, and the Hyper+X library
--   sonos.lua      Hyper+S Sonos panel: volumes, group-to-Desk, TV mode
--   ui.lua         the canvas component library the overlays share
--
-- hs.ipc comes first, before anything that can fail. A module that throws while
-- loading must not be able to take the `hs` CLI down with it: the CLI is the
-- tool you'd diagnose the failure with, and without it the only way back is the
-- menubar. Hence the pcall below, too — one broken module logs and is skipped,
-- rather than aborting the whole config.

require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")

local log = hs.logger.new("init", "info")

-- Alphabetical, so load order is deterministic rather than whatever order the
-- filesystem happens to hand back. Modules must therefore not depend on each
-- other's load order — anything that reads another module's state (the Hyper
-- shortcut registry, say) reads it at display time, not at load time.
--
-- Top-level .lua only: Spoons/ is a directory and fails the extension test, and
-- a leading underscore marks a file as work-in-progress and skips it.
local modules = {}
for file in hs.fs.dir(hs.configdir) do
  if file:sub(-4) == ".lua" and file ~= "init.lua" and file:sub(1, 1) ~= "_" then
    modules[#modules + 1] = file:sub(1, -5)
  end
end
table.sort(modules)

for _, name in ipairs(modules) do
  local ok, err = pcall(require, name)
  if ok then
    log.i("loaded " .. name)
  else
    log.e("FAILED to load " .. name .. ": " .. tostring(err))
  end
end
