-- Small recurring-job registry. lastRun lives in hs.settings so a config reload
-- or a sleeping Mac cannot keep pushing the next run into the future.
local jobs = {}
local registered = {}
local log = hs.logger.new("jobs", "info")

function jobs.register(job)
  assert(type(job.id) == "string" and type(job.every) == "number" and type(job.run) == "table")
  registered[#registered + 1] = job
end

jobs.register({
  id = "diagnostics-sample",
  every = 60,
  run = { "/usr/bin/python3", hs.configdir .. "/scripts/diagnostics.py", "sample" },
})

local function tick()
  local now = os.time()
  for _, job in ipairs(registered) do
    local key = "jobs.lastRun." .. job.id
    if not job.task and now - (hs.settings.get(key) or 0) >= job.every then
      local args = {}
      for i = 2, #job.run do args[#args + 1] = job.run[i] end
      job.task = hs.task.new(job.run[1], function(code, _, stderr)
        job.task = nil
        hs.settings.set(key, os.time())
        if code ~= 0 then log.e(job.id .. ": " .. tostring(stderr)) end
      end, args)
      if not job.task or not job.task:start() then
        job.task = nil
        hs.settings.set(key, now)
        log.e("could not start " .. job.id)
      end
    end
  end
end

jobs.timer = hs.timer.doEvery(15, tick)
tick()
return jobs
