-- Hide Godot .uid sidecar files in the explorer and file pickers.
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        explorer = {
          exclude = { "*.uid" },
        },
      },
    },
  },
}
