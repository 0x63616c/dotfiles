-- Resolve this file through any symlink (~/.config/nvim -> dotfiles/nvim) so the
-- dashboard reports the dotfiles repo's SHA regardless of where the repo is cloned.
local function dotfiles_sha()
  local this_file = debug.getinfo(1, "S").source:sub(2)
  local real = vim.uv.fs_realpath(this_file)
  if not real then
    return nil
  end
  local dir = vim.fs.dirname(real)

  local out = vim.system({ "git", "-C", dir, "rev-parse", "--short", "HEAD" }):wait()
  if out.code ~= 0 then
    return nil
  end
  return vim.trim(out.stdout)
end

local art = {
  [[ ██████╗ █████╗ ██╗     ██╗   ██╗███╗   ███╗]],
  [[██╔════╝██╔══██╗██║     ██║   ██║████╗ ████║]],
  [[██║     ███████║██║     ██║   ██║██╔████╔██║]],
  [[██║     ██╔══██║██║     ██║   ██║██║╚██╔╝██║]],
  [[╚██████╗██║  ██║███████╗╚██████╔╝██║ ╚═╝ ██║]],
  [[ ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝]],
}

local width = vim.fn.strdisplaywidth(art[1])
local header = table.concat(art, "\n")

local sha = dotfiles_sha()
if sha then
  local tag = "#" .. sha
  local pad = math.floor((width - #tag) / 2)
  header = header .. "\n\n" .. string.rep(" ", pad) .. tag
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
