-- ami.chat: the advisor chat *controller*. It owns the session, streams turns to
-- the daemon, assembles context, and emits lifecycle events — but it does not draw
-- anything itself. All UI goes through a "chat_ui" renderer: the built-in floating
-- panel (ami.chat_ui) by default, or one an extension registers with
-- api.provide("chat_ui", impl). See ami.chat_ui for the renderer contract.
local client = require("ami.client")
local context = require("ami.context")
local config = require("ami.config")
local events = require("ami.events")
local extensions = require("ami.extensions")
local log = require("ami.log")

local STATUS = "⏳ waiting for the model… (the first reply can be slow while it loads)"

local M = {
  session_id = "default",
  source_buf = nil, -- the code buffer context is gathered from
  source_win = nil,
  streaming = false,
}

-- The active renderer: an extension-provided "chat_ui", else the built-in panel.
-- Resolved lazily so a late-registered provider is still honoured.
local function ui()
  return extensions.resolve("chat_ui") or require("ami.chat_ui")
end

-- Controller callbacks the renderer wires to its keymaps/input.
local function ctl()
  return {
    submit = M.submit,
    new_session = function() M.new_session() end,
    close = M.close,
  }
end

-- Remember the code buffer/window to gather context from — but never the panel's
-- own buffers.
local function capture_source()
  local cur_buf = vim.api.nvim_get_current_buf()
  if not ui().owns_buf(cur_buf) then
    M.source_buf = cur_buf
    M.source_win = vim.api.nvim_get_current_win()
  end
end

local function do_open()
  capture_source()
  ui().open(ctl())
end

-- Public API -----------------------------------------------------------------

--- Hide the panel. Preserves the transcript and any draft.
function M.close()
  ui().close()
end

--- Toggle the whole chat UI.
function M.toggle()
  if ui().is_open() then
    ui().close()
  else
    do_open()
  end
end

--- Open the chat panel if it isn't already visible (never closes it). Part of the
--- extension-facing API (api.chat.open).
function M.open()
  if ui().is_open() then
    return
  end
  do_open()
end

--- Append raw text to the transcript (extension-facing; api.chat.append).
---@param text string
function M.append(text)
  ui().append(text)
end

-- Stream one turn to the daemon and render it into the transcript.
local function send(message, selection, range)
  if M.streaming then
    vim.notify("ami: still streaming the previous reply", vim.log.levels.WARN)
    return
  end
  M.streaming = true -- claim the turn now, before the async context gather
  local r = ui()
  r.show()
  r.append("\n\n### You\n\n" .. message .. "\n\n### Advisor\n\n")
  r.set_status(STATUS)

  context.gather_async(M.source_buf, M.source_win, selection, range, function(ctx)
    log.debug(("chat: sending turn (session=%s, project=%s, active=%s, deps=%d, %d chars)"):format(
      M.session_id, ctx.project_root, ctx.active_path ~= "" and ctx.active_path or "(none)",
      #(ctx.dep_paths or {}), #message))

    -- The outgoing request. Extensions may mutate it (e.g. inject a persona or
    -- extra context) via the chat_turn_pre event before it is sent.
    local req = {
      session_id = M.session_id,
      message = message,
      model = (config.options.chat or {}).model,
      context = ctx,
    }
    events.emit("chat_turn_pre", req)

    client.stream("/chat", req, {
      on_token = function(c)
        r.set_status(nil)
        r.append(c)
      end,
      on_done = function()
        M.streaming = false
        r.set_status(nil)
        r.append("\n")
        events.emit("chat_turn_post", { ok = true, session_id = req.session_id })
      end,
      on_error = function(e)
        M.streaming = false
        r.set_status(nil)
        r.append("\n_[error: " .. e .. "]_\n")
        events.emit("chat_turn_post", { ok = false, session_id = req.session_id, error = e })
      end,
    })
  end)
end

--- Submit the current draft. Clears it; keeps the chat open.
function M.submit()
  local message = vim.trim(ui().read_input() or "")
  log.debug(("submit: invoked (%d chars)"):format(#message))
  if message == "" then
    return
  end
  ui().clear_input()
  send(message)
end

--- One-shot ask (e.g. from :AmiAsk), optionally with a selection/range.
---@param message string
---@param selection string|nil
---@param range integer[]|nil {line1, line2} (1-indexed) of a visual selection
function M.ask(message, selection, range)
  message = vim.trim(message or "")
  if message == "" then
    return
  end
  capture_source()
  send(message, selection, range)
end

--- Project root for the code buffer the chat is attached to.
function M.project_root()
  return context.project_root(M.source_buf or 0)
end

--- Rebuild the transcript from a list of conversation nodes (used when the
--- active branch changes). Collapsed/summarized nodes get a summary marker.
---@param nodes table[]
function M.render_nodes(nodes)
  local r = ui()
  r.clear()
  for _, n in ipairs(nodes or {}) do
    local header = (n.role == "assistant") and "### Advisor" or "### You"
    r.append("\n\n" .. header .. "\n\n" .. (n.content or ""))
    if n.collapsed and n.summary and n.summary ~= "" then
      r.append("\n\n> _summary:_ " .. n.summary)
    end
  end
  r.show()
end

--- Append an unsolicited proactive suggestion to the transcript (does not steal
--- focus or force the panel open).
---@param text string
function M.add_proactive(text)
  ui().append("\n\n### 💡 Suggestion\n\n" .. text .. "\n")
end

--- Start a fresh session (new history), keeping the panel open.
---@param name string|nil
function M.new_session(name)
  M.session_id = (name and vim.trim(name) ~= "") and vim.trim(name)
    or ("session-" .. os.date("%Y%m%d-%H%M%S"))
  local r = ui()
  r.show()
  r.append("\n\n---\n\n_New session: `" .. M.session_id .. "`_\n")
  log.info("chat: new session '" .. M.session_id .. "'")
end

return M
