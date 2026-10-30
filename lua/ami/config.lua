-- ami.config: plugin defaults merged with user-supplied options.
local M = {}

---@class AmiContextConfig
---@field lsp_deps boolean Resolve dependency files via LSP (default true).
---@field dep_max_files integer Max dependency files to send (default 5).
---@field dep_timeout_ms integer Max time to wait for LSP before sending (default 1500).
---@field dep_max_positions integer Max symbol positions to query per turn (default 30).
---@field token_budget integer Max tokens of assembled context to send (default 8000).

---@class AmiModelConfig
---@field endpoint string Default provider base URL (OpenAI-compatible).
---@field model string Default model name — the fallback every model slot uses.

---@class AmiConfig
---@field model AmiModelConfig The default model slot every slot falls back to.
---@field context AmiContextConfig
---@field extensions (table|string)[] Extension specs, or module names to require().
---@field disable_extensions string[] Names of extensions to skip registering.
M.defaults = {
  -- The default model slot: the base OpenAI-compatible provider + model that every
  -- model slot (chat, and any extension's slot) falls back to. ami talks to this
  -- provider directly (no daemon). Pick models live per slot with :AmiModel.
  model = {
    endpoint = "http://localhost:1234/v1",
    model = "qwen3-coder",
  },
  context = {
    lsp_deps = true,
    dep_max_files = 5,
    dep_timeout_ms = 1500,
    dep_max_positions = 30,
    token_budget = 8000,
  },
  -- Extensions: optional capabilities that hook ami's lifecycle. Each entry is an
  -- extension spec table or a module name to require() (e.g. an installed
  -- ami-*.nvim repo). See docs/extensions.md. ami core ships no active extensions;
  -- chat lives in ami-chat.nvim, inline in ami-inline.nvim. An extension's own
  -- options live under its name (e.g. chat = { ui = {...} }, inline = {...}).
  extensions = {},
  -- Names of extensions to skip registering (e.g. a built-in you don't want).
  disable_extensions = {},
}

---@type AmiConfig
M.options = vim.deepcopy(M.defaults)

--- Merge user options over the defaults.
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  return M.options
end

return M
