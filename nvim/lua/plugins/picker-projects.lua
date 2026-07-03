-- Show both the short name and the full (home-relative) path in the Projects picker.
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        projects = {
          format = function(item)
            local path = item.file or item.text or ""
            local name = vim.fn.fnamemodify(path, ":t")
            local full = vim.fn.fnamemodify(path, ":~") -- ~/code/... instead of /Users/...
            return {
              { name, "SnacksPickerLabel" },
              { "  ", "Normal" },
              { full, "SnacksPickerDir" },
            }
          end,
        },
      },
    },
  },
}
