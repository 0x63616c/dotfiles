-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- <leader>p → jump straight to the Projects picker (switch codebases fast)
vim.keymap.set("n", "<leader>p", function()
  Snacks.picker.projects()
end, { desc = "Projects" })
