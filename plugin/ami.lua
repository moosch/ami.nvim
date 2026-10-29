-- Auto-sourced by Neovim at startup when this directory is on the runtimepath
-- (e.g. via a plugin manager). Registers the :Ami* commands so they exist
-- before setup() is called. When the plugin is added to the runtimepath at
-- runtime instead, call require("ami").setup() to register them.
if vim.g.loaded_ami then
  return
end
vim.g.loaded_ami = true

require("ami").register_commands()
