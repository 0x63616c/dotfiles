-- Dashboard header: CALUM ASCII art + a status line for this dotfiles repo.
--
-- The repo is located by resolving this file's own path through the
-- ~/.config/nvim -> dotfiles/nvim symlink, so nothing is hardcoded. `git -C`
-- walks up to the repo root on its own.
--
-- The remote indicator reads the *cached* origin ref (instant, no network) and
-- fires a detached background fetch so the next launch is fresh. Fetching
-- synchronously would block startup on the network.

local function repo_dir()
  local this_file = debug.getinfo(1, "S").source:sub(2)
  local real = vim.uv.fs_realpath(this_file)
  return real and vim.fs.dirname(real) or nil
end

local function git(dir, ...)
  local out = vim.system({ "git", "-C", dir, ... }):wait()
  if out.code ~= 0 then
    return nil
  end
  return vim.trim(out.stdout)
end

-- Thresholds are absolute, not chained divisions: dividing seconds -> minutes ->
-- ... -> years through fractional factors (4.35 weeks/month) compounds rounding
-- error and reports an exactly-2-year-old commit as "1y ago".
local MIN, HOUR, DAY = 60, 3600, 86400
local WEEK, MONTH, YEAR = 7 * DAY, 30.44 * DAY, 365 * DAY

local function rel_time(secs)
  local s = math.max(secs, 0)
  local n, suffix
  if s < MIN then
    n, suffix = s, "s"
  elseif s < HOUR then
    n, suffix = s / MIN, "m"
  elseif s < DAY then
    n, suffix = s / HOUR, "h"
  elseif s < WEEK then
    n, suffix = s / DAY, "d"
  elseif s < 30 * DAY then
    n, suffix = s / WEEK, "w"
  elseif s < YEAR then
    n, suffix = s / MONTH, "mo"
  else
    n, suffix = s / YEAR, "y"
  end
  -- max(1, ...) so the low edge of a bucket never renders as "0mo".
  return string.format("%d%s ago", math.max(math.floor(n), 1), suffix)
end

-- Returns the sha (left-aligned) and the age + sync marker (right-aligned),
-- justified to `width`:  "#8253bfe                        30m ago ⇣2"
local function status_line(dir, width)
  local info = git(dir, "log", "-1", "--format=%h %ct")
  if not info then
    return nil
  end
  local sha, ts = info:match("^(%S+)%s+(%d+)$")
  if not sha then
    return nil
  end

  local left = "#" .. sha
  local right = rel_time(os.time() - tonumber(ts))

  local upstream = git(dir, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
  if upstream then
    -- Cached remote-tracking ref: "<behind>\t<ahead>" relative to upstream.
    local counts = git(dir, "rev-list", "--left-right", "--count", upstream .. "...HEAD")
    local behind, ahead = (counts or ""):match("^(%d+)%s+(%d+)$")
    behind, ahead = tonumber(behind) or 0, tonumber(ahead) or 0

    local marks = {}
    if behind > 0 then
      table.insert(marks, "⇣" .. behind) -- remote has commits to pull
    end
    if ahead > 0 then
      table.insert(marks, "⇡" .. ahead) -- local commits not yet pushed
    end
    if #marks == 0 then
      marks = { "✓" }
    end
    right = right .. " " .. table.concat(marks, " ")

    -- Detached: refresh the cached ref for next launch without blocking this one.
    vim.system({ "git", "-C", dir, "fetch", "--quiet" }, { detach = true })
  end

  local gap = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)
  return left .. string.rep(" ", math.max(gap, 1)) .. right
end

local art = {
  [[ ██████╗ █████╗ ██╗     ██╗   ██╗███╗   ███╗]],
  [[██╔════╝██╔══██╗██║     ██║   ██║████╗ ████║]],
  [[██║     ███████║██║     ██║   ██║██╔████╔██║]],
  [[██║     ██╔══██║██║     ██║   ██║██║╚██╔╝██║]],
  [[╚██████╗██║  ██║███████╗╚██████╔╝██║ ╚═╝ ██║]],
  [[ ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝]],
}

local header = table.concat(art, "\n")
local dir = repo_dir()
-- Justified across the art's width so the sha sits under its left edge and the
-- age under its right.
local status = dir and status_line(dir, vim.fn.strdisplaywidth(art[1]))

if status then
  header = header .. "\n\n" .. status
end

return {
  "folke/snacks.nvim",
  opts = {
    dashboard = {
      preset = {
        header = header,
      },
    },
  },
}
