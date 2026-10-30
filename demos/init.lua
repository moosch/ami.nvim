-- Minimal Neovim config for recording ami demos with VHS.
--
--   nvim -u demos/init.lua <file>
--
-- Point it at your LM Studio with env vars (defaults assume localhost):
--   AMI_ENDPOINT=http://192.168.68.100:1234/v1 AMI_CHAT_MODEL=qwen3-coder \
--   AMI_FIM_MODEL=qwen3-coder nvim -u demos/init.lua demo.go
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:append(root)
-- Inline completion now lives in its own repo; append the sibling checkout so the
-- inline demo can load it. (Installed via a plugin manager in real use.)
vim.opt.runtimepath:append(vim.fn.fnamemodify(root, ":h") .. "/ami-inline.nvim")

vim.o.termguicolors = true
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.laststatus = 0
vim.o.cmdheight = 1
vim.o.swapfile = false

local endpoint = os.getenv("AMI_ENDPOINT") or "http://localhost:1234/v1"

-- Load the inline extension if its repo is on the runtimepath.
local extensions = {}
local ok, inline = pcall(require, "ami-inline")
if ok then
  extensions[#extensions + 1] = inline
end

require("ami").setup({
  -- Dedicated port so the demo never reuses (or clashes with) a real ami daemon.
  daemon_url = "http://127.0.0.1:8799",
  -- The default model slot; chat inherits it unless overridden.
  model = { endpoint = endpoint, model = os.getenv("AMI_CHAT_MODEL") or "qwen3-coder" },
  extensions = extensions,
  -- Inline extension options (used when ami-inline is loaded above).
  inline = {
    endpoint = endpoint,
    model = os.getenv("AMI_FIM_MODEL") or "qwen3-coder",
    prewarm = true,
  },
})
