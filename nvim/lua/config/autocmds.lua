-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Kill spellcheck everywhere. LazyVim enables spell (+wrap) for text/markdown/gitcommit via the
-- lazyvim_wrap_spell group; drop that group, then re-enable wrap only (no spell squiggles).
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")
vim.opt.spell = false
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("blackout_wrap_no_spell", { clear = true }),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = false
  end,
})
