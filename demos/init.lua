-- Minimal Neovim config for recording ami demos with VHS.
--
--   nvim -u demos/init.lua <file>
--
-- Point it at your LM Studio with env vars (defaults assume localhost):
--   AMI_ENDPOINT=http://192.168.68.100:1234/v1 AMI_CHAT_MODEL=qwen3-coder \
--   AMI_FIM_MODEL=qwen3-coder nvim -u demos/init.lua demo.go
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:append(root)

vim.o.termguicolors = true
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.laststatus = 0
vim.o.cmdheight = 1
vim.o.swapfile = false

local endpoint = os.getenv("AMI_ENDPOINT") or "http://localhost:1234/v1"
require("ami").setup({
  chat = { endpoint = endpoint, model = os.getenv("AMI_CHAT_MODEL") or "qwen3-coder" },
  inline = {
    endpoint = endpoint,
    model = os.getenv("AMI_FIM_MODEL") or "qwen3-coder",
    prewarm = true,
  },
})
