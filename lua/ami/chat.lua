-- ami.chat: the advisor chat panel, rendered as two stacked floating
-- windows — a transcript "stream" on top and an input prompt below it. The
-- prompt reuses its buffer, so an unsent draft survives being hidden. The chat
-- stays open after you send, so you can watch the reply stream and keep talking.
local client = require("ami.client")
local context = require("ami.context")
local config = require("ami.config")
local events = require("ami.events")
local log = require("ami.log")

local STATUS = "⏳ waiting for the model… (the first reply can be slow while it loads)"

local M = {
  transcript_buf = nil,
  transcript_win = nil,
  prompt_buf = nil,
  prompt_win = nil,
  session_id = "default",
  source_buf = nil, -- the code buffer context is gathered from
  source_win = nil,
  streaming = false,
  _status_active = false,
}

-- Geometry -------------------------------------------------------------------

-- The chat UI config block (position / width / height / opacity / margin).
local function ui_opts()
  return (config.options.chat or {}).ui or {}
end

-- Resolve a dimension given as either a fraction of `total` (0<v<=1) or an
-- absolute cell count (v>1). Falls back to `default_frac` when unset.
local function resolve_dim(v, total, default_frac)
  if not v or v <= 0 then
    return math.floor(total * default_frac)
  end
  if v <= 1 then
    return math.floor(total * v)
  end
  return math.floor(v)
end

local function layout()
  local cols, rows = vim.o.columns, vim.o.lines
  local ui = ui_opts()
  local position = ui.position or "right"
  local margin = ui.margin or 2

  local width = resolve_dim(ui.width, cols, 0.4)
  width = math.max(40, math.min(width, cols - 2))

  local prompt_h = 6
  local total_h = resolve_dim(ui.height, rows, 0.9)
  total_h = math.max(prompt_h + 8, math.min(total_h, rows - 2))
  local trans_h = total_h - prompt_h - 1

  local col
  if position == "left" then
    col = margin
  elseif position == "center" then
    col = math.floor((cols - width) / 2)
  else -- "right" (default)
    col = cols - width - margin
  end
  col = math.max(0, col)

  local top = math.max(1, math.floor((rows - total_h) / 2) - 1)
  return {
    width = width,
    col = col,
    transcript = { row = top, height = trans_h },
    prompt = { row = top + trans_h + 2, height = prompt_h },
  }
end

-- Translate the configured opacity (0..1) into a 'winblend' value (0..100, where
-- 0 is opaque) and apply it so the pane behind the panel shows through.
local function apply_blend(win)
  local opacity = ui_opts().opacity
  if opacity == nil then
    opacity = 1
  end
  local blend = math.floor((1 - opacity) * 100 + 0.5)
  vim.wo[win].winblend = math.max(0, math.min(100, blend))
end

-- Transcript -----------------------------------------------------------------

local function ensure_transcript_buf()
  if M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf) then
    return
  end
  M.transcript_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.transcript_buf].bufhidden = "hide"
  vim.bo[M.transcript_buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(M.transcript_buf, "ami://chat")
end

local function transcript_visible()
  return M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win)
end

local function show_transcript()
  ensure_transcript_buf()
  if transcript_visible() then
    return
  end
  local l = layout()
  M.transcript_win = vim.api.nvim_open_win(M.transcript_buf, false, {
    relative = "editor",
    width = l.width,
    height = l.transcript.height,
    row = l.transcript.row,
    col = l.col,
    style = "minimal",
    border = "rounded",
    title = " ami · advisor ",
    title_pos = "center",
  })
  vim.wo[M.transcript_win].wrap = true
  vim.wo[M.transcript_win].linebreak = true
  apply_blend(M.transcript_win)
end

-- Append text (which may contain newlines) to the transcript, keeping the view
-- pinned to the bottom.
local function append(text)
  ensure_transcript_buf()
  local buf = M.transcript_buf
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local last_line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1] or ""
  local parts = vim.split(last_line .. text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, last, last + 1, false, parts)
  if transcript_visible() then
    vim.api.nvim_win_set_cursor(M.transcript_win, { vim.api.nvim_buf_line_count(buf), 0 })
  end
end

local function show_status()
  append(STATUS)
  M._status_active = true
end

-- Remove the waiting indicator before the first real token arrives.
local function clear_status()
  if not M._status_active then
    return
  end
  M._status_active = false
  local buf = M.transcript_buf
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1] or ""
  if line == STATUS then
    vim.api.nvim_buf_set_lines(buf, last, last + 1, false, { "" })
  end
end

-- Prompt ---------------------------------------------------------------------

local function ensure_prompt_buf()
  if M.prompt_buf and vim.api.nvim_buf_is_valid(M.prompt_buf) then
    return
  end
  M.prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.prompt_buf].bufhidden = "hide"
  vim.bo[M.prompt_buf].filetype = "markdown"
end

local function capture_source()
  local cur_buf = vim.api.nvim_get_current_buf()
  if cur_buf ~= M.transcript_buf and cur_buf ~= M.prompt_buf then
    M.source_buf = cur_buf
    M.source_win = vim.api.nvim_get_current_win()
  end
end

function M.close()
  if M.prompt_win and vim.api.nvim_win_is_valid(M.prompt_win) then
    vim.api.nvim_win_close(M.prompt_win, true)
  end
  M.prompt_win = nil
  if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) then
    vim.api.nvim_win_close(M.transcript_win, true)
  end
  M.transcript_win = nil
end

local function open_prompt()
  capture_source()
  ensure_prompt_buf()
  show_transcript()

  local l = layout()
  M.prompt_win = vim.api.nvim_open_win(M.prompt_buf, true, {
    relative = "editor",
    width = l.width,
    height = l.prompt.height,
    row = l.prompt.row,
    col = l.col,
    style = "minimal",
    border = "rounded",
    title = " Ask  (⏎ in normal mode = send · ⌃n new · q close) ",
    title_pos = "center",
  })
  vim.wo[M.prompt_win].wrap = true
  vim.wo[M.prompt_win].linebreak = true
  apply_blend(M.prompt_win)

  local opts = { buffer = M.prompt_buf, nowait = true, silent = true }
  -- Primary send: <Enter> in NORMAL mode (reliable across terminals). In insert
  -- mode <Enter> adds a newline so multi-line messages work. <C-s> also sends
  -- but some terminals swallow it via flow control (run `stty -ixon`).
  vim.keymap.set("n", "<CR>", M.submit, opts)
  vim.keymap.set({ "n", "i" }, "<C-s>", M.submit, opts)
  vim.keymap.set({ "n", "i" }, "<C-n>", function() M.new_session() end, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  vim.cmd("startinsert")
end

-- Public API -----------------------------------------------------------------

--- Toggle the whole chat UI. Hiding preserves the transcript and any draft.
function M.toggle()
  if transcript_visible() or (M.prompt_win and vim.api.nvim_win_is_valid(M.prompt_win)) then
    M.close()
  else
    open_prompt()
  end
end

--- Open the chat panel if it isn't already visible (never closes it). Part of the
--- extension-facing API (api.chat.open).
function M.open()
  if transcript_visible() or (M.prompt_win and vim.api.nvim_win_is_valid(M.prompt_win)) then
    return
  end
  open_prompt()
end

--- Append raw text to the transcript (extension-facing; api.chat.append).
---@param text string
function M.append(text)
  append(text)
end

-- Stream one turn to the daemon and render it into the transcript.
local function send(message, selection, range)
  if M.streaming then
    vim.notify("ami: still streaming the previous reply", vim.log.levels.WARN)
    return
  end
  M.streaming = true -- claim the turn now, before the async context gather
  show_transcript()
  append("\n\n### You\n\n" .. message .. "\n\n### Advisor\n\n")
  show_status()

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
        clear_status()
        append(c)
      end,
      on_done = function()
        M.streaming = false
        clear_status()
        append("\n")
        events.emit("chat_turn_post", { ok = true, session_id = req.session_id })
      end,
      on_error = function(e)
        M.streaming = false
        clear_status()
        append("\n_[error: " .. e .. "]_\n")
        events.emit("chat_turn_post", { ok = false, session_id = req.session_id, error = e })
      end,
    })
  end)
end

--- Submit the prompt buffer contents. Clears the draft; keeps the chat open.
function M.submit()
  if not (M.prompt_buf and vim.api.nvim_buf_is_valid(M.prompt_buf)) then
    log.debug("submit: no prompt buffer")
    return
  end
  local message = vim.trim(table.concat(vim.api.nvim_buf_get_lines(M.prompt_buf, 0, -1, false), "\n"))
  log.debug(("submit: invoked (%d chars)"):format(#message))
  if message == "" then
    return
  end
  vim.api.nvim_buf_set_lines(M.prompt_buf, 0, -1, false, {})
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
  ensure_transcript_buf()
  vim.api.nvim_buf_set_lines(M.transcript_buf, 0, -1, false, {})
  for _, n in ipairs(nodes or {}) do
    local header = (n.role == "assistant") and "### Advisor" or "### You"
    append("\n\n" .. header .. "\n\n" .. (n.content or ""))
    if n.collapsed and n.summary and n.summary ~= "" then
      append("\n\n> _summary:_ " .. n.summary)
    end
  end
  show_transcript()
end

--- Append an unsolicited proactive suggestion to the transcript (does not steal
--- focus or force the panel open).
---@param text string
function M.add_proactive(text)
  ensure_transcript_buf()
  append("\n\n### 💡 Suggestion\n\n" .. text .. "\n")
end

--- Start a fresh session (new history), keeping the panel open.
---@param name string|nil
function M.new_session(name)
  M.session_id = (name and vim.trim(name) ~= "") and vim.trim(name)
    or ("session-" .. os.date("%Y%m%d-%H%M%S"))
  show_transcript()
  append("\n\n---\n\n_New session: `" .. M.session_id .. "`_\n")
  log.info("chat: new session '" .. M.session_id .. "'")
end

return M
