-- ami.client: an OpenAI-compatible (LM Studio) HTTP client, using the system
-- `curl` binary via vim.system. Chat streaming is consumed as SSE. There is no
-- daemon any more — ami talks to the provider directly.
local log = require("ami.log")

local M = {}

local function base(endpoint)
  return (endpoint or ""):gsub("/+$", "")
end

--- GET <endpoint>/models directly from an OpenAI-compatible provider.
--- cb(ok, { ids }). Used by the model selector.
---@param endpoint string base URL, e.g. "http://localhost:1234/v1"
---@param cb fun(ok: boolean, ids: string[]|string)
function M.models_from(endpoint, cb)
  local url = base(endpoint) .. "/models"
  vim.system(
    { "curl", "-sS", "-m", "10", url },
    { text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          cb(false, "curl exit " .. res.code .. ": " .. (res.stderr or ""))
          return
        end
        local ok, data = pcall(vim.json.decode, res.stdout)
        if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
          cb(false, "bad JSON from " .. url .. ": " .. tostring(res.stdout))
          return
        end
        local ids = {}
        for _, mdl in ipairs(data.data) do
          if mdl.id then
            ids[#ids + 1] = mdl.id
          end
        end
        cb(true, ids)
      end)
    end
  )
end

--- POST <endpoint>/chat/completions and stream the reply.
---@param endpoint string provider base URL
---@param body table { model, messages, temperature?, ... } (stream is forced on)
---@param callbacks table { on_token=fun(content), on_done=fun(), on_error=fun(msg) }
---@param opts table|nil { timeout_ms=number } idle timeout (no new token); default 120000
---@return vim.SystemObj handle (supports :kill())
function M.stream_chat(endpoint, body, callbacks, opts)
  opts = opts or {}
  local timeout_ms = opts.timeout_ms or 120000
  local on_token = callbacks.on_token or function() end
  local on_done = callbacks.on_done or function() end
  local on_error = callbacks.on_error or function() end

  body.stream = true
  local url = base(endpoint) .. "/chat/completions"
  local payload = vim.json.encode(body)
  log.info(("stream_chat: POST %s (%d bytes)"):format(url, #payload))

  local pending = ""
  local tokens = 0
  local settled, timer, handle = false, nil, nil

  local function stop_timer()
    if timer then
      timer:stop()
      timer = nil
    end
  end
  -- Idle watchdog: if no new token arrives within timeout_ms, give up (covers a
  -- cold model that never responds, and a mid-stream stall). Reset on each token.
  local function arm_timer()
    stop_timer()
    timer = vim.defer_fn(function()
      if settled then
        return
      end
      pcall(function()
        if handle then
          handle:kill("sigterm")
        end
      end)
      settled = true
      on_error(("no reply within %ds — is the model loading? raise chat.timeout_ms, or try again once it's warm")
        :format(math.floor(timeout_ms / 1000)))
    end, timeout_ms)
  end
  local function finish(err)
    if settled then
      return
    end
    settled = true
    stop_timer()
    if err then
      on_error(err)
    else
      on_done()
    end
  end

  -- Parse one SSE line (OpenAI format: `data: {json}` / `data: [DONE]`).
  local function handle_line(line)
    local data = line:gsub("\r$", ""):match("^data:%s?(.*)$")
    if not data or data == "" or data == "[DONE]" then
      return
    end
    local ok, obj = pcall(vim.json.decode, data)
    if not ok or type(obj) ~= "table" then
      return
    end
    if obj.error then
      local e = obj.error
      finish(type(e) == "table" and (e.message or vim.inspect(e)) or tostring(e))
      return
    end
    local choice = obj.choices and obj.choices[1]
    local content = choice and choice.delta and choice.delta.content
    if content and content ~= "" then
      tokens = tokens + 1
      arm_timer() -- saw a token; reset the idle watchdog
      on_token(content)
    end
  end

  handle = vim.system(
    {
      "curl", "-sS", "-N", "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", payload, url,
    },
    {
      text = true,
      stdout = function(err, chunk)
        if err or not chunk then
          return
        end
        vim.schedule(function()
          pending = pending .. chunk
          while true do
            local nl = pending:find("\n", 1, true)
            if not nl then
              break
            end
            handle_line(pending:sub(1, nl - 1))
            pending = pending:sub(nl + 1)
          end
        end)
      end,
    },
    function(res)
      vim.schedule(function()
        if pending ~= "" then
          handle_line(pending)
          pending = ""
        end
        local sig = res.signal or 0
        log.debug(("stream_chat: curl exit=%d signal=%d, tokens=%d"):format(res.code, sig, tokens))
        if sig ~= 0 then
          -- Killed (e.g. cancelled or the idle watchdog) — not a normal completion.
          finish(("interrupted (signal %d)"):format(sig))
        elseif res.code ~= 0 then
          finish(("curl exit %d: %s"):format(res.code, (res.stderr or ""):gsub("%s+$", "")))
        else
          finish(nil)
        end
      end)
    end
  )
  arm_timer()
  return handle
end

--- POST <endpoint>/completions (non-streaming) and call cb(ok, text|errmsg).
--- For FIM / raw completion callers.
---@param endpoint string
---@param body table { model, prompt, max_tokens, ... }
---@param cb fun(ok: boolean, text: string)
---@param opts table|nil { timeout_s = number }
function M.complete(endpoint, body, cb, opts)
  opts = opts or {}
  body.stream = false
  local url = base(endpoint) .. "/completions"
  vim.system(
    {
      "curl", "-sS", "-m", tostring(opts.timeout_s or 30),
      "-X", "POST", "-H", "Content-Type: application/json",
      "-d", vim.json.encode(body), url,
    },
    { text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          cb(false, ("curl exit %d: %s"):format(res.code, (res.stderr or ""):gsub("%s+$", "")))
          return
        end
        local ok, data = pcall(vim.json.decode, res.stdout)
        if not ok or type(data) ~= "table" then
          cb(false, "bad JSON from " .. url .. ": " .. tostring(res.stdout))
          return
        end
        if data.error then
          local e = data.error
          cb(false, type(e) == "table" and (e.message or vim.inspect(e)) or tostring(e))
          return
        end
        local text = data.choices and data.choices[1] and data.choices[1].text
        cb(true, text or "")
      end)
    end
  )
end

return M
