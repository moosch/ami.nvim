-- ami: an IDE-resident AI pair programmer for Neovim (advisor, not actor).
--
-- Stage 1 provides the chat advisor panel (see ami.chat). The Stage 0
-- health check and echo-stream transport probe are retained for debugging.
local config = require("ami.config")
local client = require("ami.client")
local chat = require("ami.chat")
local inline = require("ami.inline")
local tree = require("ami.tree")
local models = require("ami.models")
local daemon = require("ami.daemon")
local proactive = require("ami.proactive")

local M = {}

-- Re-export sub-APIs: require("ami").chat.toggle(), .inline.trigger() etc.
M.chat = chat
M.inline = inline
M.tree = tree
M.models = models
M.daemon = daemon
M.proactive = proactive

--- Register the :Ami* user commands. Safe to call more than once
--- (later calls overwrite). Called by setup() and by plugin/ami.lua so the
--- commands exist whether the plugin loads at startup or is required live.
function M.register_commands()
  vim.api.nvim_create_user_command("AmiHealth", function()
    require("ami").health()
  end, { desc = "Check the amid daemon status" })

  vim.api.nvim_create_user_command("AmiEcho", function(opts)
    require("ami").echo(opts.args)
  end, { nargs = "+", desc = "Stream text back from the daemon (transport test)" })

  vim.api.nvim_create_user_command("AmiChat", function()
    require("ami.chat").toggle()
  end, { desc = "Toggle the advisor prompt (shows the chat panel)" })

  vim.api.nvim_create_user_command("AmiAsk", function(opts)
    local chat = require("ami.chat")
    local selection, range = nil, nil
    if opts.range > 0 then
      selection = require("ami.context").last_selection()
      range = { opts.line1, opts.line2 }
    end
    chat.ask(opts.args, selection, range)
  end, { nargs = "+", range = true, desc = "Ask the advisor (visual range sends the selection + its deps)" })

  vim.api.nvim_create_user_command("AmiNewSession", function(opts)
    require("ami.chat").new_session(opts.args)
  end, { nargs = "?", desc = "Start a fresh advisor session" })

  vim.api.nvim_create_user_command("AmiTree", function()
    require("ami.tree").open(false)
  end, { desc = "Open the conversation tree (branch/switch/summarize)" })

  vim.api.nvim_create_user_command("AmiModel", function(opts)
    local m = require("ami.models")
    if opts.args == "chat" or opts.args == "fim" then
      m.select(opts.args)
    else
      m.pick()
    end
  end, {
    nargs = "?",
    complete = function() return { "chat", "fim" } end,
    desc = "Select the chat or FIM model (no arg = choose which)",
  })

  vim.api.nvim_create_user_command("AmiModels", function()
    require("ami.models").show()
  end, { desc = "Show the current chat and FIM models" })

  vim.api.nvim_create_user_command("AmiProactive", function()
    require("ami.proactive").toggle()
  end, { desc = "Toggle proactive suggestions on/off" })

  vim.api.nvim_create_user_command("AmiNudge", function()
    require("ami.proactive").nudge(true)
  end, { desc = "Request a proactive suggestion now" })

  vim.api.nvim_create_user_command("AmiDaemon", function(opts)
    local d = require("ami.daemon")
    local action = opts.args ~= "" and opts.args or "restart"
    if action == "start" then
      d.start()
    elseif action == "stop" then
      d.force_stop()
    else
      d.restart()
    end
  end, {
    nargs = "?",
    complete = function() return { "start", "stop", "restart" } end,
    desc = "Control the amid daemon (start|stop|restart; default restart)",
  })

  vim.api.nvim_create_user_command("AmiLog", function()
    require("ami.log").open()
  end, { desc = "Open the ami log viewer" })

  vim.api.nvim_create_user_command("AmiDebug", function()
    require("ami.log").toggle_debug()
  end, { desc = "Toggle verbose ami debug logging" })

  vim.api.nvim_create_user_command("AmiComplete", function()
    require("ami.inline").trigger()
  end, { desc = "Request an inline (ghost-text) completion" })

  vim.api.nvim_create_user_command("AmiInlineAuto", function()
    require("ami.inline").toggle_auto()
  end, { desc = "Toggle inline auto-trigger on/off" })
end

--- Configure the plugin.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  M.register_commands()
  inline.setup()
  daemon.setup()
  proactive.setup()
end

--- Ping the daemon and report its status.
function M.health()
  client.health(function(ok, data)
    if not ok then
      vim.notify("ami: daemon unreachable — " .. tostring(data), vim.log.levels.ERROR)
      return
    end
    vim.notify(
      ("ami: daemon ok (model=%s, lmstudio=%s)"):format(data.model or "?", data.lmstudio or "?"),
      vim.log.levels.INFO
    )
  end)
end

-- Open (or reuse) a throwaway scratch buffer in a split for streamed output.
-- Stage 1 replaces this with the real chat panel in ami.chat.
local scratch_buf = nil
local function scratch_window()
  if not (scratch_buf and vim.api.nvim_buf_is_valid(scratch_buf)) then
    scratch_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[scratch_buf].bufhidden = "hide"
    vim.api.nvim_buf_set_name(scratch_buf, "ami://scratch")
  end
  -- Show it in a window if not already visible.
  local shown = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == scratch_buf then
      shown = true
      break
    end
  end
  if not shown then
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, scratch_buf)
  end
  return scratch_buf
end

local function append(buf, text)
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local last_line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1] or ""
  local parts = vim.split(last_line .. text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, last, last + 1, false, parts)
end

--- Stream `text` back from the daemon's /echo endpoint into a scratch buffer.
---@param text string
function M.echo(text)
  local buf = scratch_window()
  append(buf, "\n> " .. text .. "\n")
  client.stream("/echo", { text = text }, {
    on_token = function(content)
      append(buf, content)
    end,
    on_done = function()
      append(buf, "\n")
    end,
    on_error = function(msg)
      vim.notify("ami: " .. msg, vim.log.levels.ERROR)
    end,
  })
end

return M
