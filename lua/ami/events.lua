-- ami.events: a tiny synchronous publish/subscribe bus that lets extensions hook
-- into the agent lifecycle without reaching into core internals.
--
-- Core emits a small, stable set of events (see docs/extensions.md):
--   setup                       -- after ami.setup() finishes
--   context_assembled(ctx,meta) -- context ready; handlers may MUTATE ctx in place
--   chat_turn_pre(req)          -- before a chat turn streams; handlers may MUTATE req
--   chat_turn_post(res)         -- after a chat turn finishes or errors
--   buf_write(bufnr)            -- a buffer was written (BufWritePost)
--
-- Handlers run in registration order and each is wrapped in pcall, so one
-- misbehaving extension can't break a chat turn or stop the others.
local log = require("ami.log")

local M = {}

---@type table<string, function[]>
local handlers = {}

--- Subscribe `fn` to `event`. Returns an unsubscribe function.
---@param event string
---@param fn fun(...)
---@return fun() unsubscribe
function M.on(event, fn)
  if type(fn) ~= "function" then
    error("ami.events.on: handler for '" .. tostring(event) .. "' must be a function", 2)
  end
  handlers[event] = handlers[event] or {}
  local list = handlers[event]
  list[#list + 1] = fn
  return function()
    for i, h in ipairs(list) do
      if h == fn then
        table.remove(list, i)
        return
      end
    end
  end
end

--- Emit `event`, calling every subscribed handler with the given arguments.
--- Handlers are called for their side effects and for mutating any table passed
--- in (that is how context_assembled / chat_turn_pre let extensions contribute).
---@param event string
function M.emit(event, ...)
  local list = handlers[event]
  if not list then
    return
  end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, ...)
    if not ok then
      log.warn(("events: handler for '%s' errored — %s"):format(event, tostring(err)))
    end
  end
end

--- Emit `event` and collect each handler's non-nil return value into a list, in
--- registration order. This is the "contribution" variant of emit: a feature
--- declares a collector hook (e.g. "chat.system", "context.extra") and extensions
--- register handlers that RETURN a value, which the feature composes itself —
--- cleaner than everyone mutating a shared payload. Handlers run synchronously, so
--- keep them fast/pure (precompute async work out-of-band and return it here).
---@param event string
---@return any[] contributions
function M.emit_collect(event, ...)
  local out = {}
  local list = handlers[event]
  if not list then
    return out
  end
  for _, fn in ipairs(list) do
    local ok, res = pcall(fn, ...)
    if not ok then
      log.warn(("events: collector for '%s' errored — %s"):format(event, tostring(res)))
    elseif res ~= nil then
      out[#out + 1] = res
    end
  end
  return out
end

--- Remove all handlers for `event`, or all handlers entirely when `event` is nil.
--- (Mainly for tests.)
---@param event string|nil
function M.clear(event)
  if event then
    handlers[event] = nil
  else
    handlers = {}
  end
end

local installed = false

--- Install the core autocmds that translate editor events into bus events.
--- Idempotent.
function M.install()
  if installed then
    return
  end
  installed = true
  local grp = vim.api.nvim_create_augroup("AmiEvents", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function(args)
      M.emit("buf_write", args.buf)
    end,
  })
end

return M
