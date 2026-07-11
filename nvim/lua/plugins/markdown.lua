-- Point markdownlint-cli2 at a global base config so MD013 (line-length) is off everywhere.
-- markdownlint-cli2 only searches from the file up to cwd, so a ~/.markdownlint-cli2.jsonc is
-- never found when nvim's cwd is a repo root. Passing --config makes it the base config;
-- any repo-local .markdownlint* still layers on top and can re-enable rules.
return {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters = opts.linters or {}
      opts.linters["markdownlint-cli2"] = {
        args = { "--config", vim.fn.expand("~/.markdownlint-cli2.jsonc"), "-" },
      }
      return opts
    end,
  },

  -- Kill marksman: no LSP attach, no "link to non existing doc" diagnostics.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = { marksman = { enabled = false } },
      setup = {
        marksman = function()
          return true -- LazyVim skips default setup when this returns true
        end,
      },
    },
  },

  -- Don't let Mason auto-install the marksman binary.
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = vim.tbl_filter(function(pkg)
        return pkg ~= "marksman"
      end, opts.ensure_installed or {})
    end,
  },
}
