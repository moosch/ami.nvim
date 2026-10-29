-- ami.log: lightweight in-memory log with a viewer buffer.
-- Debug level is off by default; :AmiDebug toggles it. :AmiLog opens
-- the viewer. Warnings/errors are always recorded (and surfaced via notify).
local M = {
  entries = {},
  max = 1000,
  debug_enabled = false,
  buf = nil,
  win = nil,
}

local function render_lines()
  local out = {}
  for _, e in ipairs(M.entries) do
    out[#out + 1] = string.format("%s  %-5s  %s", e.time, e.level:upper(), e.msg)
  end
  if #out == 0 then
    out = { "(no log entries yet)" }
  end
  return out
end

local function refresh()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return
  end
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, render_lines())
  vim.bo[M.buf].modifiable = false
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_set_cursor(M.win, { vim.api.nvim_buf_line_count(M.buf), 0 })
  end
end

local function add(level, msg)
  if type(msg) ~= "string" then
    msg = vim.inspect(msg)
  end
  M.entries[#M.entries + 1] = { time = os.date("%H:%M:%S"), level = level, msg = msg }
  if #M.entries > M.max then
    table.remove(M.entries, 1)
  end
  vim.schedule(refresh)
end

function M.debug(msg)
  if M.debug_enabled then
    add("debug", msg)
  end
end

function M.info(msg)
  add("info", msg)
end

function M.warn(msg)
  add("warn", msg)
  vim.schedule(function() vim.notify("ami: " .. tostring(msg), vim.log.levels.WARN) end)
end

function M.error(msg)
  add("error", msg)
  vim.schedule(function() vim.notify("ami: " .. tostring(msg), vim.log.levels.ERROR) end)
end

function M.set_debug(on)
  M.debug_enabled = on
  M.info("debug logging " .. (on and "ENABLED" or "disabled"))
end

function M.toggle_debug()
  M.set_debug(not M.debug_enabled)
end

--- Open (or focus) the log viewer in a bottom split.
function M.open()
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].bufhidden = "hide"
    vim.bo[M.buf].filetype = "log"
    vim.api.nvim_buf_set_name(M.buf, "ami://log")
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_set_current_win(M.win)
  else
    vim.cmd("botright split")
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    vim.api.nvim_win_set_height(M.win, 14)
    vim.wo[M.win].wrap = false
    vim.wo[M.win].number = false
  end
  refresh()
end

return M
