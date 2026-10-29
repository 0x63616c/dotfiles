-- Extra LSP servers with no dedicated LazyVim Extra.
-- Naming a server here makes Mason auto-install the binary and LazyVim auto-attach it.
--   bashls  -> the many .sh scripts across www + the-workflow-engine
--   cssls   -> hand-written CSS design tokens (the tailwind Extra does not cover plain CSS)
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      bashls = {},
      cssls = {},
    },
  },
}
