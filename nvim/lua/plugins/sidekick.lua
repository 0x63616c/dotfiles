-- Sidekick: AI CLIs (claude, codex, ...) in a split inside nvim.
-- NES (next-edit suggestions) disabled — it needs Copilot, which we don't use.
return {
  "folke/sidekick.nvim",
  opts = {
    nes = { enabled = false },
  },
  keys = {
    {
      "<leader>aa",
      function()
        require("sidekick.cli").toggle({ focus = true })
      end,
      mode = { "n", "v" },
      desc = "Sidekick toggle CLI",
    },
    {
      "<leader>ac",
      function()
        require("sidekick.cli").toggle({ name = "claude", focus = true })
      end,
      mode = { "n", "v" },
      desc = "Sidekick Claude",
    },
    {
      "<leader>ax",
      function()
        require("sidekick.cli").toggle({ name = "codex", focus = true })
      end,
      mode = { "n", "v" },
      desc = "Sidekick Codex",
    },
    {
      "<leader>as",
      function()
        require("sidekick.cli").select()
      end,
      desc = "Sidekick select CLI",
    },
    {
      "<leader>at",
      function()
        require("sidekick.cli").send({ msg = "{this}" })
      end,
      mode = { "n", "x" },
      desc = "Sidekick send this (file/selection + position)",
    },
    {
      "<leader>av",
      function()
        require("sidekick.cli").send({ msg = "{selection}" })
      end,
      mode = { "x" },
      desc = "Sidekick send selection",
    },
    {
      "<leader>ap",
      function()
        require("sidekick.cli").prompt()
      end,
      mode = { "n", "x" },
      desc = "Sidekick prompt picker",
    },
    {
      "<c-.>",
      function()
        require("sidekick.cli").focus()
      end,
      mode = { "n", "x", "i", "t" },
      desc = "Sidekick switch focus",
    },
  },
}
