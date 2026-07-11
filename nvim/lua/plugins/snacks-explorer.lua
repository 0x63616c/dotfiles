-- Hide Godot .uid sidecar files in the explorer and all pickers (files, grep, ...).
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      exclude = { "*.uid" },
    },
  },
}
