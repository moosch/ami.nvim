-- ami.inline: native Copilot-style ghost-text completion via a FIM model.
--
-- Talks directly to LM Studio's /v1/completions endpoint (not through amid)
-- to keep latency low. Manual trigger by default; optional debounced auto-trigger.
-- Advisor ethos preserved: suggestions are shown as ghost text you explicitly
-- accept or dismiss — nothing is written to the buffer until you accept.
local config = require("ami.config")
local log = require("ami.log")

local M = {}

local ns = vim.api.nvim_create_namespace("ami_inline")
local augroup = nil

-- Current suggestion state.
local state = {
  text = nil,   -- the suggestion string (possibly multi-line)
  bufnr = nil,  -- buffer it was computed for
  row = nil,    -- 0-indexed cursor row at request time
  col = nil,    -- 0-indexed cursor col (byte) at request time
}
local gen = 0        -- request generation, to drop stale responses
local inflight = nil -- in-flight vim.system handle
local auto_timer = nil

local function cfg()
  return config.options.inline or {}
end

-- Ghost text -----------------------------------------------------------------

function M.clear()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  end
  state.text, state.bufnr, state.row, state.col = nil, nil, nil, nil
end

function M.has_suggestion()
  return state.text ~= nil
end

-- Render `text` as ghost text at (row,col) [0-indexed] in bufnr.
function M.show(bufnr, row, col, text)
  M.clear()
  local lines = vim.split(text, "\n", { plain = true })
  local opts = {
    virt_text = { { lines[1], "AmiInlineGhost" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  }
  if #lines > 1 then
    local vlines = {}
    for i = 2, #lines do
      vlines[#vlines + 1] = { { lines[i], "AmiInlineGhost" } }
    end
    opts.virt_lines = vlines
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, opts)
  state.text, state.bufnr, state.row, state.col = text, bufnr, row, col
end

-- FIM request ----------------------------------------------------------------

-- Build (prefix, suffix) around the cursor, bounded by the configured line
-- windows. Exposed for testing.
function M._context(bufnr, win)
  local c = cfg()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local total = vim.api.nvim_buf_line_count(bufnr)

  local first = math.max(0, row - (c.context_before_lines or 120))
  local last = math.min(total, row + 1 + (c.context_after_lines or 60))

  local cur = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local before = vim.api.nvim_buf_get_lines(bufnr, first, row, false)
  local after = vim.api.nvim_buf_get_lines(bufnr, row + 1, last, false)

  local prefix = table.concat(before, "\n")
  if #before > 0 then
    prefix = prefix .. "\n"
  end
  prefix = prefix .. cur:sub(1, col)

  local suffix = cur:sub(col + 1)
  if #after > 0 then
    suffix = suffix .. "\n" .. table.concat(after, "\n")
  end
  return prefix, suffix, row, col
end

-- Keep at most max_lines lines (0 = unlimited) and drop a purely-empty result.
local function postprocess(text, max_lines)
  if max_lines and max_lines > 0 then
    local lines = vim.split(text, "\n", { plain = true })
    if #lines > max_lines then
      lines = vim.list_slice(lines, 1, max_lines)
      text = table.concat(lines, "\n")
    end
  end
  return text
end

-- Request a completion and call cb(text|nil). No mode/position gating here;
-- callers decide whether to render. `silent` keeps failures to debug-level (used
-- by auto-trigger so it never spams); manual triggers surface errors. Exposed for
-- testing.
function M._request(bufnr, win, cb, silent)
  local c = cfg()
  local prefix, suffix, row, col = M._context(bufnr, win)
  local fim = c.fim or {}
  local prompt = (fim.prefix or "") .. prefix .. (fim.suffix or "") .. suffix .. (fim.middle or "")

  local body = {
    model = c.model,
    prompt = prompt,
    max_tokens = c.max_tokens or 128,
    temperature = c.temperature or 0.2,
    stop = c.stop,
    stream = false,
  }
  local url = (c.endpoint or ""):gsub("/$", "") .. "/completions"
  local timeout_s = math.max(1, math.floor((c.timeout_ms or 20000) / 1000))
  log.debug(("inline: POST %s (prefix=%d, suffix=%d bytes, timeout=%ds)"):format(url, #prefix, #suffix, timeout_s))

  if inflight then
    pcall(function() inflight:kill(9) end)
    inflight = nil
  end

  -- Report a failure: quiet (debug) for auto-trigger, loud (notify) for manual.
  local function fail(reason)
    if silent then
      log.debug("inline: " .. reason)
    else
      log.warn("inline: " .. reason) -- log.warn also notifies
    end
    cb(nil, row, col)
  end

  local uv = vim.uv or vim.loop
  local start = uv.hrtime()

  inflight = vim.system(
    {
      "curl", "-sS", "-m", tostring(timeout_s),
      "-X", "POST", "-H", "Content-Type: application/json",
      "-d", vim.json.encode(body), url,
    },
    { text = true },
    function(res)
      vim.schedule(function()
        inflight = nil
        local ms = math.floor((uv.hrtime() - start) / 1e6)
        if res.code ~= 0 then
          if res.code == 28 then
            return fail(("request timed out after %ds — is the model loaded? The first completion can be slow while LM Studio loads it; try again once it's warm, raise inline.timeout_ms, or use a smaller FIM model."):format(timeout_s))
          elseif res.code == 7 then
            return fail("could not connect to " .. url .. " — check inline.endpoint (your LM Studio address)")
          end
          return fail(("curl exit %d: %s"):format(res.code, (res.stderr or ""):gsub("%s+$", "")))
        end
        local ok, data = pcall(vim.json.decode, res.stdout)
        if ok and type(data) == "table" and data.error then
          local em = type(data.error) == "table" and (data.error.message or vim.inspect(data.error)) or tostring(data.error)
          return fail("server error: " .. em)
        end
        if not ok or not (data.choices and data.choices[1]) then
          return fail("unexpected response: " .. tostring(res.stdout):sub(1, 200))
        end
        local text = postprocess(data.choices[1].text or "", c.max_lines)
        if vim.trim(text) == "" then
          log.debug(("inline: empty completion (%dms)"):format(ms))
          return cb(nil, row, col)
        end
        log.debug(("inline: completion in %dms (%d chars)"):format(ms, #text))
        cb(text, row, col)
      end)
    end
  )
  return inflight
end

-- Public actions -------------------------------------------------------------

--- Request a suggestion for the current buffer and show it as ghost text.
--- `silent` (used by auto-trigger) keeps failures quiet.
---@param silent boolean|nil
function M.trigger(silent)
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  if vim.bo[bufnr].buftype ~= "" then
    return -- only normal file buffers
  end

  M.clear()
  gen = gen + 1
  local my = gen

  M._request(bufnr, win, function(text, row, col)
    if not text or my ~= gen then
      return -- stale or empty
    end
    -- Only show if we're still in insert mode at the same spot.
    if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
      return
    end
    if vim.api.nvim_get_current_buf() ~= bufnr then
      return
    end
    local cur = vim.api.nvim_win_get_cursor(win)
    if cur[1] - 1 ~= row or cur[2] ~= col then
      return
    end
    M.show(bufnr, row, col, text)
  end, silent)
end

--- Accept the current suggestion, inserting it at the cursor. Returns true if
--- a suggestion was accepted.
function M.accept()
  if not state.text then
    return false
  end
  local text, bufnr = state.text, state.bufnr
  M.clear()

  local win = vim.api.nvim_get_current_win()
  local cur = vim.api.nvim_win_get_cursor(win)
  local row, col = cur[1] - 1, cur[2]
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, lines)

  local new_row = row + #lines - 1
  local last = lines[#lines]
  local new_col = (#lines == 1) and (col + #last) or #last
  vim.api.nvim_win_set_cursor(win, { new_row + 1, new_col })
  return true
end

--- Dismiss the current suggestion.
function M.dismiss()
  M.clear()
end

-- Auto-trigger ---------------------------------------------------------------

local function schedule_auto()
  if auto_timer then
    auto_timer:stop()
    auto_timer = nil
  end
  auto_timer = vim.defer_fn(function()
    if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
      M.trigger(true) -- auto-trigger: keep failures quiet
    end
  end, cfg().debounce_ms or 400)
end

--- Toggle auto-trigger at runtime.
function M.toggle_auto()
  local c = cfg()
  c.auto = not c.auto
  log.info("inline: auto-trigger " .. (c.auto and "ON" or "OFF"))
  vim.notify("ami inline: auto-trigger " .. (c.auto and "on" or "off"), vim.log.levels.INFO)
end

-- Setup ----------------------------------------------------------------------

--- Configure inline completion: highlight, keymaps, and autocmds. Idempotent.
function M.setup()
  local c = cfg()
  if c.enabled == false then
    return
  end

  vim.api.nvim_set_hl(0, "AmiInlineGhost", { link = "Comment", default = true })

  local km = c.keymaps or {}
  if km.trigger then
    vim.keymap.set("i", km.trigger, M.trigger, { desc = "ami: request inline completion" })
  end
  if km.dismiss then
    vim.keymap.set("i", km.dismiss, M.dismiss, { desc = "ami: dismiss inline completion" })
  end
  if km.accept then
    vim.keymap.set("i", km.accept, function()
      if M.accept() then
        return
      end
      -- No suggestion: fall back to the key's normal behaviour.
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(km.accept, true, false, true), "n", false)
    end, { desc = "ami: accept inline completion (or fallback)" })
  end

  augroup = vim.api.nvim_create_augroup("AmiInline", { clear = true })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function() M.clear() end,
  })
  vim.api.nvim_create_autocmd({ "CursorMovedI", "TextChangedI" }, {
    group = augroup,
    callback = function()
      M.clear()
      if cfg().auto then
        schedule_auto()
      end
    end,
  })
end

return M
