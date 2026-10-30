-- ami.chat_ui: the built-in chat renderer — two stacked floating windows, a
-- transcript "stream" on top and an input prompt below it. The prompt reuses its
-- buffer, so an unsent draft survives being hidden.
--
-- This is the default provider for the "chat_ui" capability. An extension can
-- replace the whole panel (e.g. a sidebar split) by implementing this same
-- interface and registering it with api.provide("chat_ui", impl); the chat
-- controller (ami.chat) then drives that instead. The contract:
--
--   open(ctl)            show the full interactive panel and focus the input.
--                        ctl = { submit, new_session, close } — wire these to keys.
--   show()               ensure the transcript is visible WITHOUT stealing focus.
--   close()              hide the panel; MUST preserve transcript + any draft.
--   is_open() -> bool    is the panel (transcript or input) currently visible?
--   owns_buf(b) -> bool  is buffer `b` one of the panel's own buffers?
--   append(text)         append text (may contain \n) to the transcript; pin to bottom.
--   clear()              empty the transcript.
--   set_status(text|nil) show a transient status line; nil clears it.
--   read_input() -> str  the current draft text.
--   clear_input()        clear the draft.
local config = require("ami.config")

local M = {
  transcript_buf = nil,
  transcript_win = nil,
  prompt_buf = nil,
  prompt_win = nil,
  _status_text = nil,
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

-- Prompt ---------------------------------------------------------------------

local function ensure_prompt_buf()
  if M.prompt_buf and vim.api.nvim_buf_is_valid(M.prompt_buf) then
    return
  end
  M.prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.prompt_buf].bufhidden = "hide"
  vim.bo[M.prompt_buf].filetype = "markdown"
end

-- Interface ------------------------------------------------------------------

--- Ensure the transcript window is visible (does not steal focus).
function M.show()
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

--- Append text (which may contain newlines), keeping the view pinned to bottom.
---@param text string
function M.append(text)
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

--- Empty the transcript.
function M.clear()
  ensure_transcript_buf()
  vim.api.nvim_buf_set_lines(M.transcript_buf, 0, -1, false, {})
end

--- Show a transient status line (text), or clear it (nil). Implemented by
--- appending/removing a single line at the bottom of the transcript.
---@param text string|nil
function M.set_status(text)
  if text then
    M.append(text)
    M._status_text = text
    return
  end
  if not M._status_text then
    return
  end
  local want = M._status_text
  M._status_text = nil
  ensure_transcript_buf()
  local buf = M.transcript_buf
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1] or ""
  if line == want then
    vim.api.nvim_buf_set_lines(buf, last, last + 1, false, { "" })
  end
end

--- Is any part of the panel visible?
function M.is_open()
  return transcript_visible() or (M.prompt_win and vim.api.nvim_win_is_valid(M.prompt_win)) or false
end

--- Does this buffer belong to the panel?
---@param bufnr integer
function M.owns_buf(bufnr)
  return bufnr == M.transcript_buf or bufnr == M.prompt_buf
end

--- The current draft text.
---@return string
function M.read_input()
  if not (M.prompt_buf and vim.api.nvim_buf_is_valid(M.prompt_buf)) then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(M.prompt_buf, 0, -1, false), "\n")
end

--- Clear the draft.
function M.clear_input()
  if M.prompt_buf and vim.api.nvim_buf_is_valid(M.prompt_buf) then
    vim.api.nvim_buf_set_lines(M.prompt_buf, 0, -1, false, {})
  end
end

--- Hide the panel. Preserves the transcript buffer and the prompt draft.
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

--- Open the full interactive panel and focus the input.
---@param ctl table { submit, new_session, close } controller callbacks
function M.open(ctl)
  ensure_prompt_buf()
  M.show()

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
  vim.keymap.set("n", "<CR>", ctl.submit, opts)
  vim.keymap.set({ "n", "i" }, "<C-s>", ctl.submit, opts)
  vim.keymap.set({ "n", "i" }, "<C-n>", ctl.new_session, opts)
  vim.keymap.set("n", "q", ctl.close, opts)
  vim.keymap.set("n", "<Esc>", ctl.close, opts)

  vim.cmd("startinsert")
end

return M
