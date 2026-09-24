-- Hyper+D opens a local snapshot of the disk history. The Python helper reads
-- SQLite and writes HTML; Hammerspoon never blocks on a database or shell call.
-- Keep the webview for its interactive charts, but give it the same frameless
-- modal placement, fade and dismissal as the canvas overlays.
local hyper = require("hyper")
local log = hs.logger.new("diagnostics", "info")
local page, renderTask, escapeKey
local wantedOpen = false
local FADE = 0.14

local function close()
  wantedOpen = false
  if escapeKey then escapeKey:disable() end
  if page then
    local old = page
    page = nil
    old:delete(false, FADE)
  end
end

local function open()
  if wantedOpen then close(); return end
  wantedOpen = true
  if renderTask then return end
  local script = hs.configdir .. "/scripts/diagnostics.py"
  renderTask = hs.task.new("/usr/bin/python3", function(code, stdout, stderr)
    renderTask = nil
    if not wantedOpen then return end
    if code ~= 0 then
      wantedOpen = false
      log.e("render failed: " .. tostring(stderr))
      hs.alert.show("Diagnostics could not load")
      return
    end
    local url = stdout:gsub("%s+$", "")
    page = hs.webview.new(hs.screen.mainScreen():frame())
      :allowTextEntry(true)
      :windowStyle(0)
      :transparent(true)
      :shadow(false)
      :level(hs.canvas.windowLevels.screenSaver)
      :behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
      :policyCallback(function(action, _, request)
        if action == "navigationAction" and request.request
           and tostring(request.request.URL):match("^diagnostics://close/?$") then
          close()
          return false
        end
        return true
      end)
      :windowCallback(function(action, view)
        if action == "closing" and page == view then
          page = nil
          wantedOpen = false
          if escapeKey then escapeKey:disable() end
        end
      end)
      :url(url)
      :show(FADE)
    if not escapeKey then escapeKey = hs.hotkey.new({}, "escape", close) end
    escapeKey:enable()
  end, { script, "render" })
  if not renderTask:start() then
    renderTask = nil
    wantedOpen = false
    hs.alert.show("Diagnostics could not start")
  end
end

hyper.bind("d", "Diagnostics", open)
return { open = open, close = close }
