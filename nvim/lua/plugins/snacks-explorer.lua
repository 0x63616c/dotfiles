-- Hide Godot .uid sidecar files in the explorer and all pickers (files, grep, ...).
-- Show dotfiles and gitignored files everywhere, but always carve out .git and node_modules.
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      exclude = {
        "*.uid",
        "**/.git/*",
        "**/node_modules/*",
        "**/.DS_Store",
        "**/.venv/*",
        "**/__pycache__/*",
        "**/.cache/*",
      },
      sources = {
        explorer = { hidden = true, ignored = true },
        files = { hidden = true, ignored = true },
      },
    },
  },
}
