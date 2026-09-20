-- Screenshots -> clipboard ----------------------------------------------------
--
-- Replaces CopyCat (github.com/0x63616c/copy-cat), a menu bar app whose whole
-- job was: notice a new screenshot, put it on the clipboard. That was ~2,500
-- lines of Swift, but only ~250 of it was the actual behaviour — the rest was
-- being an app (Sparkle updates, login item, settings window, notarisation,
-- security-scoped bookmarks, a status-badge state machine). Hammerspoon already
-- provides all of that scaffolding, so only the behaviour needs porting.
--
-- Detection deliberately mirrors CopyCat's, including its hard-won lessons:
--
--   * Two independent legs, so one failure can't blind it. An hs.pathwatcher
--     (FSEvents) reacts instantly; a slow poll re-scans regardless. CopyCat
--     carried the same belt-and-braces because FSEvents can silently drop
--     events, and a screenshot tool that quietly stops copying is worse than
--     one that never worked.
--   * No Spotlight. CopyCat originally identified screenshots by the
--     kMDItemIsScreenCapture metadata flag, which made it depend on Spotlight
--     indexing the folder. When macOS dropped indexing on ~/Screenshots,
--     auto-copy died with no error anywhere. Match on the filename prefix
--     instead — cruder, but it cannot silently stop working.
--   * Retry the image load. macOS writes the file then renames it into place,
--     so FSEvents can fire while the PNG is still partial and decoding returns
--     nil. CopyCat handled this with a debounce; belt-and-braces again here,
--     with a few short retries after the debounce.
--
-- Everything CopyCat's Settings window offered is a constant below.

local hyper = require("hyper")

local log = hs.logger.new("screenshots", "info")

local AUTO_COPY     = true   -- copy each new screenshot automatically
local POLL_INTERVAL = 4      -- safety-net rescan, seconds (FSEvents can drop)
local DEBOUNCE      = 0.3    -- coalesce a burst of FSEvents into one scan
local LOAD_RETRIES  = 6      -- attempts to decode a still-being-written file
local RETRY_DELAY   = 0.15   -- seconds between those attempts
local PREFIX        = "Screenshot"  -- macOS default capture filename

-- Where macOS saves captures. `defaults read` blocks, but this runs once at
-- load and cfprefs doesn't reliably flush to the plist on disk, so reading the
-- file directly would be less correct rather than faster.
local function screenshotFolder()
  local out = hs.execute("defaults read com.apple.screencapture location 2>/dev/null")
  local path = out and out:gsub("%s+$", "") or ""
  if path == "" then path = os.getenv("HOME") .. "/Desktop" end
  return path:gsub("^~", os.getenv("HOME"))
end

local folder = screenshotFolder()

-- Newest screenshot in the folder, by mtime. Returns nil if the folder is
-- unreadable or holds none. pcall'd because hs.fs.dir raises on a folder that
-- has been deleted or is TCC-blocked, and that must not kill the watcher.
local function newestScreenshot()
  local newest, newestAt = nil, -1
  local ok = pcall(function()
    for file in hs.fs.dir(folder) do
      if file:sub(1, #PREFIX) == PREFIX then
        local path = folder .. "/" .. file
        local attrs = hs.fs.attributes(path)
        if attrs and attrs.mode == "file" and attrs.modification > newestAt then
          newest, newestAt = path, attrs.modification
        end
      end
    end
  end)
  if not ok then log.w("cannot read " .. folder) end
  return newest
end

-- Retained: an unreferenced hs.timer is garbage-collected and never fires.
-- A single slot is enough because only one copy is ever in flight, and each
-- retry replaces a timer that has already fired.
screenshotRetryTimer = nil

local function copyToClipboard(path, attempt)
  attempt = attempt or 1
  local image = hs.image.imageFromPath(path)
  if image and hs.pasteboard.writeObjects(image) then
    log.i("copied " .. path:match("[^/]+$"))
    return
  end
  if attempt >= LOAD_RETRIES then
    log.e("gave up decoding " .. path:match("[^/]+$") .. " after " .. attempt .. " attempts")
    return
  end
  screenshotRetryTimer = hs.timer.doAfter(RETRY_DELAY, function()
    copyToClipboard(path, attempt + 1)
  end)
end

-- Newest screenshot already delivered. Seeded by the first scan so a folder
-- full of old screenshots doesn't copy one the moment Hammerspoon loads.
local lastSeen = nil
local gathered = false

local function rescan()
  local newest = newestScreenshot()
  if not newest or newest == lastSeen then return end
  lastSeen = newest
  if not gathered then
    gathered = true
    return  -- first scan establishes the baseline; it is not a new screenshot
  end
  if AUTO_COPY then copyToClipboard(newest) end
end

local scanTimer = hs.timer.delayed.new(DEBOUNCE, rescan)

-- Both legs are global for the same reason as the watchers in dictation.lua:
-- an unreferenced pathwatcher or timer is collected and stops firing silently.
screenshotWatcher = hs.pathwatcher.new(folder, function()
  scanTimer:start()  -- restarts the countdown; fires once the writes settle
end):start()

screenshotPoll = hs.timer.doEvery(POLL_INTERVAL, rescan)

rescan()  -- establish the baseline immediately

hyper.bind("c", "Copy latest screenshot", function()
  local newest = newestScreenshot()
  if newest then
    copyToClipboard(newest)
  else
    hs.alert.show("No screenshots in " .. folder)
  end
end)

log.i("watching " .. folder .. " (FSEvents + " .. POLL_INTERVAL .. "s poll)")
