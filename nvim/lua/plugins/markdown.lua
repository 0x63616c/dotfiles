-- Point markdownlint-cli2 at a global base config so MD013 (line-length) is off everywhere.
-- markdownlint-cli2 only searches from the file up to cwd, so a ~/.markdownlint-cli2.jsonc is
-- never found when nvim's cwd is a repo root. Passing --config makes it the base config;
-- any repo-local .markdownlint* still layers on top and can re-enable rules.
return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    opts.linters = opts.linters or {}
    opts.linters["markdownlint-cli2"] = {
      args = { "--config", vim.fn.expand("~/.markdownlint-cli2.jsonc"), "-" },
    }
    return opts
  end,
}
