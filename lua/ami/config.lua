-- ami.config: plugin defaults merged with user-supplied options.
local M = {}

---@class AmiContextConfig
---@field lsp_deps boolean Resolve dependency files via LSP (default true).
---@field dep_max_files integer Max dependency files to send (default 5).
---@field dep_timeout_ms integer Max time to wait for LSP before sending (default 1500).
---@field dep_max_positions integer Max symbol positions to query per turn (default 30).

---@class AmiInlineConfig
---@field enabled boolean Set up inline completion keymaps/autocmds (default true).
---@field endpoint string LM Studio OpenAI-compatible base URL (inline talks to it directly).
---@field model string FIM model name.
---@field auto boolean Auto-trigger (debounced) while typing (default false = manual).
---@field debounce_ms integer Auto-trigger debounce.
---@field max_tokens integer Max completion tokens requested.
---@field max_lines integer Truncate a suggestion to this many lines (0 = unlimited).
---@field temperature number Sampling temperature.
---@field context_before_lines integer Lines of prefix context.
---@field context_after_lines integer Lines of suffix context.
---@field timeout_ms integer Request timeout.
---@field fim table FIM tokens { prefix, suffix, middle }.
---@field stop string[] Stop sequences.
---@field keymaps table { trigger, accept, dismiss } insert-mode keys.

---@class AmiConfig
---@field daemon_url string Base URL of the amid daemon.
---@field context AmiContextConfig
---@field inline AmiInlineConfig
M.defaults = {
  daemon_url = "http://127.0.0.1:8787",
  -- Default chat model (the fallback/initial value; change it live with the
  -- model selector, :AmiModel). Empty string = use the daemon's default.
  chat_model = "qwen3-coder",
  -- Where conversation history is stored. nil = stdpath("data")/ami
  -- (outside your repos). Set to a path to override, or "" to use each project's
  -- own .ami/sessions directory.
  session_dir = nil,
  -- Daemon lifecycle: start amid on setup if not already running, stop it
  -- (only if we started it) on exit.
  daemon = {
    auto_start = true,  -- start the daemon on setup if none is answering
    auto_build = true,  -- `go build` the binary if missing (in the source repo)
    bin = nil,          -- path to amid; nil = <plugin>/bin/amid
  },
  context = {
    lsp_deps = true,
    dep_max_files = 5,
    dep_timeout_ms = 1500,
    dep_max_positions = 30,
  },
  -- Proactive guidance: an occasional unsolicited suggestion in the chat panel.
  -- OFF by default; opt in with proactive.enabled = true or :AmiProactive.
  proactive = {
    enabled = false,
    on_idle = true,       -- suggest after idle_ms of inactivity
    idle_ms = 20000,
    on_save = true,       -- suggest after writing a buffer
    min_interval_s = 180, -- rate limit: minimum seconds between suggestions
    require_normal_mode = true, -- don't interrupt while typing in insert mode
    notify = true,        -- low-key notification when a suggestion arrives
  },
  inline = {
    enabled = true,
    endpoint = "http://localhost:1234/v1",
    model = "qwen3-coder",
    auto = false,
    debounce_ms = 400,
    max_tokens = 128,
    max_lines = 8,
    temperature = 0.2,
    context_before_lines = 120,
    context_after_lines = 60,
    timeout_ms = 20000,
    fim = {
      prefix = "<|fim_prefix|>",
      suffix = "<|fim_suffix|>",
      middle = "<|fim_middle|>",
    },
    stop = { "<|fim_pad|>", "<|endoftext|>", "<|file_sep|>", "<|repo_name|>",
      "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>" },
    keymaps = {
      trigger = "<C-g>",
      accept = "<Tab>",
      dismiss = "<C-]>",
    },
  },
}

---@type AmiConfig
M.options = vim.deepcopy(M.defaults)

--- Merge user options over the defaults.
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
