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

-- Library window --------------------------------------------------------------
--
-- CopyCat's popover: a grid of recent screenshots, newest first, click one to
-- copy it, hover for a bigger preview. Its Settings pane is gone — everything it
-- offered is a constant in this file — and so is the menu bar icon, since
-- Hyper+X opens this directly.
--
-- Deliberately ONE fullscreen canvas rather than a floating card, because a
-- canvas only receives mouse events inside itself. A fullscreen one gets the
-- dimmed backdrop, click-outside-to-dismiss and all hover tracking from a
-- single mouseCallback in one coordinate space; a card-sized canvas would need
-- a second canvas behind it just to notice the clicks that should close it.
--
-- Thumbnails are cached by path across opens. Decoding fifteen multi-megabyte
-- PNGs on every open is visibly slow, and it's the same fifteen files each
-- time. CopyCat solved this by downsampling into a ThumbnailCache; caching the
-- decoded images is the same trick with less machinery, and the cache is
-- dropped wholesale once it grows past CACHE_MAX so it can't creep.

local COLS, ROWS = 3, 5     -- CopyCat's default grid
local TILE       = 86
local GAP         = 8
local PREVIEW_W  = 300
local PAD        = 16
local INFO_H     = 34
local RADIUS     = 14
local CACHE_MAX  = 60

local DIM      = { white = 0, alpha = 0.35 }   -- backdrop
local CARD_BG  = { red = 0.07, green = 0.07, blue = 0.09, alpha = 0.97 }
local CARD_EDGE = { red = 1.0, green = 0.0, blue = 1.0, alpha = 0.5 }
local TILE_BG  = { white = 1, alpha = 0.06 }
local HILITE   = { red = 1.0, green = 0.0, blue = 1.0, alpha = 0.9 }
local TEXT     = { white = 1, alpha = 0.95 }
local SUBTLE   = { white = 1, alpha = 0.5 }

local thumbCache = {}
local thumbCount = 0

-- Downsample once, through an offscreen canvas, and cache the small result.
--
-- This is load-bearing, not an optimisation. Handing a canvas the full-size
-- hs.image looks fine — loading one is ~1ms because NSImage decodes lazily —
-- but the decode then happens at *draw* time, on the main thread, for every
-- tile. Fifteen 5120x2160 captures scaled into 86pt squares wedged Hammerspoon
-- hard enough that hs.ipc stopped answering and the window never appeared.
-- Rendering each into a small canvas and snapshotting it with imageFromCanvas
-- forces the resample once: 15 thumbnails in ~150ms, then free from cache.
-- CopyCat hit the same wall and solved it the same way (its ThumbnailCache
-- "downsamples images rather than decoding full-size screenshots for every
-- grid tile").
-- mode is "fill" (crop to cover, for square tiles) or "fit" (letterbox at
-- native aspect, for the preview).
--
-- Hammerspoon has no aspect-fill: imageScaling accepts only none,
-- scaleProportionally, scaleToFit and shrinkToFit. An invalid value is
-- rejected and silently leaves the previous one in place, so asking for
-- "scaleToFill" letterboxed every tile instead of erroring. Fill is therefore
-- computed here — scale so the shorter side covers the square, centre the
-- oversized frame, and let the offscreen canvas clip the overflow. That is
-- exactly the aspect-fill CopyCat's grid specified: "fill the square, crop
-- overflow".
local function downsample(path, w, h, mode)
  local key = path .. "|" .. w .. "x" .. h .. "|" .. mode
  local cached = thumbCache[key]
  if cached then return cached end
  local full = hs.image.imageFromPath(path)
  if not full then return nil end

  local frame = { x = 0, y = 0, w = w, h = h }
  if mode == "fill" then
    local size = full:size()
    if size and size.w > 0 and size.h > 0 then
      local scale = math.max(w / size.w, h / size.h)
      local dw, dh = size.w * scale, size.h * scale
      frame = { x = (w - dw) / 2, y = (h - dh) / 2, w = dw, h = dh }
    end
  end

  local tmp = hs.canvas.new({ x = 0, y = 0, w = w, h = h })
  tmp[1] = { type = "image", image = full, imageScaling = "scaleProportionally",
             imageAlignment = "center", frame = frame }
  local small = tmp:imageFromCanvas()
  tmp:delete()
  if thumbCount >= CACHE_MAX then
    thumbCache, thumbCount = {}, 0   -- drop wholesale; cheaper than LRU bookkeeping
  end
  thumbCache[key] = small
  thumbCount = thumbCount + 1
  return small
end

-- Square, aspect-fill (cropped) for grid tiles. 2x for retina.
local function thumbnail(path)
  return downsample(path, TILE * 2, TILE * 2, "fill")
end

-- Native aspect ratio, letterboxed into the preview pane.
local function previewImage(path, w, h)
  return downsample(path, w * 2, h * 2, "fit")
end

-- The `limit` most recent screenshots, newest first. Separate from
-- newestScreenshot() because that one deliberately avoids sorting 2,000 entries
-- on every poll; this runs only when the window opens.
local function recentScreenshots(limit)
  local all = {}
  local ok = pcall(function()
    for file in hs.fs.dir(folder) do
      if file:sub(1, #PREFIX) == PREFIX then
        local path = folder .. "/" .. file
        local attrs = hs.fs.attributes(path)
        if attrs and attrs.mode == "file" then
          all[#all + 1] = { path = path, name = file, at = attrs.modification }
        end
      end
    end
  end)
  if not ok then log.w("cannot read " .. folder) end
  table.sort(all, function(a, b) return a.at > b.at end)
  local out = {}
  for i = 1, math.min(limit, #all) do out[i] = all[i] end
  return out
end

local function ago(at)
  local secs = os.time() - at
  if secs < 60 then return "just now" end
  if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h ago" end
  return math.floor(secs / 86400) .. "d ago"
end

-- Retained: an unreferenced canvas or hotkey is collected and stops working.
screenshotLibrary = nil
screenshotLibraryEsc = nil

local function closeLibrary()
  if screenshotLibrary then
    screenshotLibrary:delete()
    screenshotLibrary = nil
  end
  if screenshotLibraryEsc then screenshotLibraryEsc:disable() end
end

local function openLibrary()
  closeLibrary()
  local shots = recentScreenshots(COLS * ROWS)
  if #shots == 0 then
    hs.alert.show("No screenshots in " .. folder)
    return
  end

  local gridW = COLS * TILE + (COLS - 1) * GAP
  local gridH = ROWS * TILE + (ROWS - 1) * GAP
  local cardW = PAD * 3 + PREVIEW_W + gridW
  local cardH = PAD * 2 + math.max(gridH, 240 + INFO_H)
  local screen = hs.screen.mainScreen():frame()
  local cardX = screen.x + (screen.w - cardW) / 2
  local cardY = screen.y + (screen.h - cardH) / 2

  local c = hs.canvas.new(screen)
  c:level(hs.canvas.windowLevels.screenSaver)
  c:behavior({ "canJoinAllSpaces", "stationary" })

  -- Backdrop: dismisses on click, which is why the canvas is fullscreen.
  c[#c + 1] = { type = "rectangle", action = "fill", fillColor = DIM,
                trackMouseDown = true, id = "backdrop" }

  local cx, cy = cardX - screen.x, cardY - screen.y
  c[#c + 1] = { type = "rectangle", action = "fill", fillColor = CARD_BG,
                roundedRectRadii = { xRadius = RADIUS, yRadius = RADIUS },
                frame = { x = cx, y = cy, w = cardW, h = cardH } }
  c[#c + 1] = { type = "rectangle", action = "stroke", strokeColor = CARD_EDGE,
                strokeWidth = 1.5,
                roundedRectRadii = { xRadius = RADIUS, yRadius = RADIUS },
                frame = { x = cx, y = cy, w = cardW, h = cardH } }

  -- Preview pane. scaleProportionally keeps the native aspect ratio, unlike the
  -- tiles, which crop to squares.
  local previewH = cardH - PAD * 2 - INFO_H
  c[#c + 1] = { type = "image", id = "preview",
                image = previewImage(shots[1].path, PREVIEW_W, previewH),
                imageScaling = "scaleProportionally", imageAlignment = "center",
                frame = { x = cx + PAD, y = cy + PAD, w = PREVIEW_W, h = previewH } }
  c[#c + 1] = { type = "text", id = "info", text = shots[1].name,
                textColor = TEXT, textSize = 11,
                frame = { x = cx + PAD, y = cy + PAD + previewH + 4, w = PREVIEW_W, h = 15 } }
  c[#c + 1] = { type = "text", id = "when", text = ago(shots[1].at) .. "  ·  click a tile to copy",
                textColor = SUBTLE, textSize = 10,
                frame = { x = cx + PAD, y = cy + PAD + previewH + 19, w = PREVIEW_W, h = 15 } }

  local gx = cx + PAD * 2 + PREVIEW_W
  for i, shot in ipairs(shots) do
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local x = gx + col * (TILE + GAP)
    local y = cy + PAD + row * (TILE + GAP)
    c[#c + 1] = { type = "rectangle", action = "fill", fillColor = TILE_BG,
                  roundedRectRadii = { xRadius = 6, yRadius = 6 },
                  frame = { x = x, y = y, w = TILE, h = TILE } }
    -- The thumbnail is already a cropped square (see downsample), so it lands
    -- in the square frame exactly and the grid stays uniform whatever shape the
    -- capture was.
    c[#c + 1] = { type = "image", id = "tile:" .. i, image = thumbnail(shot.path),
                  imageScaling = "scaleProportionally",
                  trackMouseDown = true, trackMouseEnterExit = true,
                  frame = { x = x, y = y, w = TILE, h = TILE } }
    c[#c + 1] = { type = "rectangle", action = "stroke", id = "ring:" .. i,
                  strokeColor = { white = 1, alpha = 0 }, strokeWidth = 2,
                  roundedRectRadii = { xRadius = 6, yRadius = 6 },
                  frame = { x = x, y = y, w = TILE, h = TILE } }
  end

  -- Element ids are stable, so the callback mutates elements in place rather
  -- than rebuilding the canvas on every hover — same approach as the dictation
  -- border's animation.
  c:mouseCallback(function(_, event, id)
    if type(id) ~= "string" then return end
    if event == "mouseDown" then
      if id == "backdrop" then
        closeLibrary()
      else
        local i = tonumber(id:match("^tile:(%d+)$"))
        if i and shots[i] then
          copyToClipboard(shots[i].path)
          closeLibrary()
        end
      end
    elseif event == "mouseEnter" then
      local i = tonumber(id:match("^tile:(%d+)$"))
      if i and shots[i] then
        c["preview"].image = previewImage(shots[i].path, PREVIEW_W, previewH)
        c["info"].text = shots[i].name
        c["when"].text = ago(shots[i].at) .. "  ·  click a tile to copy"
        c["ring:" .. i].strokeColor = HILITE
      end
    elseif event == "mouseExit" then
      local i = tonumber(id:match("^tile:(%d+)$"))
      if i then c["ring:" .. i].strokeColor = { white = 1, alpha = 0 } end
    end
  end)

  screenshotLibrary = c
  c:show()

  if not screenshotLibraryEsc then
    screenshotLibraryEsc = hs.hotkey.new({}, "escape", closeLibrary)
  end
  screenshotLibraryEsc:enable()
end

-- Exposed for debugging: `hs -c 'screenshotsLibrary.open()'` renders the window
-- without a keypress, which is how its layout gets checked.
screenshotsLibrary = { open = openLibrary, close = closeLibrary }

hyper.bind("x", "Screenshot library", function()
  if screenshotLibrary then closeLibrary() else openLibrary() end
end)

hyper.bind("c", "Copy latest screenshot", function()
  local newest = newestScreenshot()
  if newest then
    copyToClipboard(newest)
  else
    hs.alert.show("No screenshots in " .. folder)
  end
end)

log.i("watching " .. folder .. " (FSEvents + " .. POLL_INTERVAL .. "s poll)")
