-- Hyper+D opens a local snapshot of the disk history. The Python helper reads
-- SQLite and writes HTML; Hammerspoon never blocks on a database or shell call.
local hyper = require("hyper")
local log = hs.logger.new("diagnostics", "info")
local page, renderTask

local function open()
  if page then page:show(); page:bringToFront() end
  if renderTask then return end
  local script = hs.configdir .. "/scripts/diagnostics.py"
  renderTask = hs.task.new("/usr/bin/python3", function(code, stdout, stderr)
    renderTask = nil
    if code ~= 0 then
      log.e("render failed: " .. tostring(stderr))
      hs.alert.show("Diagnostics could not load")
      return
    end
    local url = stdout:gsub("%s+$", "")
    if not page then
      local screen = hs.screen.mainScreen():frame()
      local w, h = math.min(screen.w - 100, 1120), math.min(screen.h - 90, 790)
      page = hs.webview.new({ x = screen.x + (screen.w - w) / 2,
                              y = screen.y + (screen.h - h) / 2, w = w, h = h })
        :windowTitle("Diagnostics")
        :allowTextEntry(true)
        :windowStyle({ "titled", "closable", "miniaturizable", "resizable" })
        :closeOnEscape(true)
        :show()
    end
    page:url(url)
    page:bringToFront()
  end, { script, "render" })
  if not renderTask:start() then
    renderTask = nil
    hs.alert.show("Diagnostics could not start")
  end
end

hyper.bind("d", "Diagnostics", open)
return { open = open }
