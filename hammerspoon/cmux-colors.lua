-- Direct save bridge for the interpreted cmux sidebar. Its cmux() callbacks
-- run in-process and don't emit the socket's workspace.action event, so an
-- event-only saver misses clicks and later restores the old colour.
-- openURL is supported by that sidebar runtime: this handler sends an explicit
-- request to the Python helper, which saves the tracked config BEFORE applying
-- colours. No polling, synthetic notifications, shell interpolation or Git.

local log = hs.logger.new("cmux-colors", "info")
local M = { queue = {}, task = nil }
local script = os.getenv("HOME") .. "/.config/cmux/directory-colors.py"

local function validWorkspace(id)
  return type(id) == "string" and #id == 36
    and id:sub(9, 9) == "-" and id:sub(14, 14) == "-"
    and id:sub(19, 19) == "-" and id:sub(24, 24) == "-"
    and #id:gsub("-", "") == 32 and id:gsub("-", ""):match("^%x+$") ~= nil
end

local function startNext()
  if M.task or #M.queue == 0 then return end
  local request = table.remove(M.queue, 1)
  M.task = hs.task.new("/usr/bin/python3", function(code, _, stderr)
    M.task = nil
    if code ~= 0 then
      log.e("colour save failed: " .. tostring(stderr))
      hs.alert.show("cmux colour could not be saved; see Hammerspoon console")
    end
    startNext()
  end, { script, "--workspace", request.workspace, "--color", request.color })
  if not M.task or not M.task:start() then
    M.task = nil
    log.e("could not start directory colour helper")
    hs.alert.show("cmux colour helper could not start")
    startNext()
  end
end

function M.request(params)
  local color = params.color
  if not validWorkspace(params.workspace) or type(color) ~= "string"
    or (color ~= "default" and not color:match("^%x%x%x%x%x%x$")) then
    log.w("ignored invalid directory colour request")
    return false
  end
  M.queue[#M.queue + 1] = { workspace = params.workspace, color = color }
  startNext()
  return true
end

hs.urlevent.bind("cmux-directory-color", function(_, params)
  M.request(params)
end)

return M
