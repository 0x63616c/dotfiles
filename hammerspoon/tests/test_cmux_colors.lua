-- Run with hs -c 'dofile("/path/to/dotfiles/hammerspoon/tests/test_cmux_colors.lua")'.
-- Isolated environment: never replace the live hs globals or start real tasks.
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/")
local tasks, alerts, bound = {}, {}, {}
local stub = {
  logger = { new = function() return { e = function() end, w = function() end } end },
  alert = { show = function(text) alerts[#alerts + 1] = text end },
  urlevent = { bind = function(name, callback) bound[name] = callback end },
  task = { new = function(path, callback, args)
    local task = { path = path, callback = callback, args = args }
    function task:start() tasks[#tasks + 1] = self; return true end
    return task
  end },
}
local env = setmetatable({ hs = stub }, { __index = _G })
local module = assert(loadfile(root .. "/cmux-colors.lua", "t", env))()
local uuid = "635F1369-8950-449C-9365-640300B40E9C"
assert(bound["cmux-directory-color"])
assert(not module.request({ workspace = "invalid", color = "7DCFFF" }))
assert(not module.request({ workspace = uuid, color = "7DCFFF; touch /tmp/no" }))
assert(#tasks == 0)
bound["cmux-directory-color"]("cmux-directory-color", { workspace = uuid, color = "7DCFFF" })
assert(#tasks == 1 and module.task == tasks[1])
assert(tasks[1].path == "/usr/bin/python3")
assert(tasks[1].args[2] == "--workspace" and tasks[1].args[3] == uuid)
assert(tasks[1].args[4] == "--color" and tasks[1].args[5] == "7DCFFF")
assert(module.request({ workspace = uuid, color = "default" }))
assert(#tasks == 1 and #module.queue == 1)
tasks[1].callback(0, "", "")
assert(#tasks == 2 and module.task == tasks[2] and #module.queue == 0)
assert(tasks[2].args[5] == "default")
tasks[2].callback(1, "", "write failed")
assert(module.task == nil and #alerts == 1)
print("PASS: URL bridge validates inputs, keeps async tasks alive, serialises choices and surfaces failures")
