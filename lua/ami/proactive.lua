-- ami.proactive: occasional unsolicited suggestions (Stage 5).
--
-- OFF by default. When enabled, it asks the daemon for one brief suggestion after
-- the editor has been idle for a while or just after a save, rate-limited and
-- never while you're mid-typing. Suggestions land in the chat transcript (they
-- don't steal focus or pop a window) with a low-key notification. Ignore them
-- freely, or open :AmiChat to respond — exactly like a colleague's aside.
local config = require("ami.config")
local client = require("ami.client")
local context = require("ami.context")
local chat = require("ami.chat")
local log = require("ami.log")

local P = {
  pending = false,
  last = 0,        -- os.time() of the last fired request (for rate limiting)
  last_text = nil, -- most recent suggestion
  timer = nil,
}

local function cfg()
  return config.options.proactive or {}
end

local function in_insert()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

local function first_line(s)
  local line = (s:gsub("\n.*$", ""))
  if #line > 70 then
    line = line:sub(1, 70) .. "…"
  end
  return line
end

--- Request a proactive suggestion. With force=true, bypasses the enabled flag
--- and the rate limit (used by :AmiNudge).
---@param force boolean|nil
function P.nudge(force)
  local c = cfg()
  if not force then
    if not c.enabled then
      return
    end
    local now = os.time()
    if (now - P.last) < (c.min_interval_s or 180) then
      return
    end
    if c.require_normal_mode and in_insert() then
      return
    end
  end
  if P.pending or chat.streaming then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  if vim.bo[buf].buftype ~= "" then
    return -- only normal file buffers
  end

  P.pending = true
  P.last = os.time()
  chat.source_buf, chat.source_win = buf, win

  context.gather_async(buf, win, nil, nil, function(ctx)
    client.post_json("/nudge", {
      session_id = chat.session_id,
      model = config.options.chat_model,
      context = ctx,
    }, function(ok, data)
      P.pending = false
      if not ok then
        log.debug("nudge: " .. tostring(data))
        return
      end
      local s = type(data) == "table" and data.suggestion or nil
      if s and vim.trim(s) ~= "" then
        P.last_text = s
        log.info("nudge: suggestion offered")
        chat.add_proactive(s)
        if cfg().notify then
          vim.notify("💡 ami: " .. first_line(s), vim.log.levels.INFO)
        end
      else
        log.debug("nudge: no suggestion")
      end
    end, { timeout_s = 90 })
  end)
end

local function reset_idle()
  local c = cfg()
  if not (c.enabled and c.on_idle) then
    return
  end
  if P.timer then
    P.timer:stop()
    P.timer = nil
  end
  P.timer = vim.defer_fn(function()
    P.nudge(false)
  end, c.idle_ms or 20000)
end

--- Toggle proactive mode at runtime.
function P.toggle()
  local c = cfg()
  c.enabled = not c.enabled
  log.info("proactive: " .. (c.enabled and "ENABLED" or "disabled"))
  vim.notify("ami proactive: " .. (c.enabled and "on" or "off"), vim.log.levels.INFO)
  if c.enabled then
    reset_idle()
  elseif P.timer then
    P.timer:stop()
    P.timer = nil
  end
end

--- Install autocmds (idle + on-save). Gating is checked at fire time, so this is
--- safe to call even while disabled.
function P.setup()
  local grp = vim.api.nvim_create_augroup("AmiProactive", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function()
      if cfg().enabled and cfg().on_save then
        P.nudge(false)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = grp,
    callback = reset_idle,
  })
  if cfg().enabled then
    reset_idle()
  end
end

return P
