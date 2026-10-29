-- ami.client: talks to the amid daemon over HTTP, using the system
-- `curl` binary via vim.system. Streaming endpoints are consumed as SSE.
local config = require("ami.config")
local log = require("ami.log")

local M = {}

local function daemon_url()
  return config.options.daemon_url
end

--- GET /health. Calls cb(ok, data) on the main loop.
---@param cb fun(ok: boolean, data: table|string)
---@param opts table|nil { quiet = boolean } suppress the failure warning
function M.health(cb, opts)
  opts = opts or {}
  local url = daemon_url() .. "/health"
  log.debug("health: GET " .. url)
  vim.system(
    { "curl", "-sS", "-m", "5", url },
    { text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          local msg = ("health: curl exit %d — %s"):format(res.code, (res.stderr or ""):gsub("%s+$", ""))
          if opts.quiet then
            log.debug(msg)
          else
            log.warn(msg)
          end
          cb(false, "curl failed (code " .. res.code .. "): " .. (res.stderr or ""))
          return
        end
        local ok, decoded = pcall(vim.json.decode, res.stdout)
        if not ok then
          log.warn("health: invalid JSON — " .. tostring(res.stdout))
          cb(false, "invalid JSON from daemon: " .. tostring(res.stdout))
          return
        end
        log.debug("health: ok " .. vim.inspect(decoded))
        cb(true, decoded)
      end)
    end
  )
end

--- GET /models (LM Studio list via the daemon). cb(ok, { ids }, default).
---@param cb fun(ok: boolean, ids: string[]|string, default: string|nil)
function M.models(cb)
  vim.system(
    { "curl", "-sS", "-m", "10", daemon_url() .. "/models" },
    { text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          cb(false, "curl exit " .. res.code .. ": " .. (res.stderr or ""))
          return
        end
        local ok, data = pcall(vim.json.decode, res.stdout)
        if not ok or type(data) ~= "table" then
          cb(false, "bad JSON from daemon: " .. tostring(res.stdout))
          return
        end
        cb(true, data.models or {}, data.default)
      end)
    end
  )
end

--- POST a JSON body and decode a single JSON response. cb(ok, data|errmsg).
---@param path string
---@param body table
---@param cb fun(ok: boolean, data: table|string)
---@param opts table|nil { timeout_s = number }
function M.post_json(path, body, cb, opts)
  opts = opts or {}
  local url = daemon_url() .. path
  log.debug("post: POST " .. url)
  vim.system(
    {
      "curl", "-sS", "-m", tostring(opts.timeout_s or 60),
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
        if not ok then
          cb(false, "bad JSON from daemon: " .. tostring(res.stdout))
          return
        end
        cb(true, data)
      end)
    end
  )
end

-- Parse any complete SSE event blocks from `buffer`, invoking `on_event` for
-- each. Returns the unparsed remainder (a partial trailing block).
local function drain_events(buffer, on_event)
  while true do
    local sep = buffer:find("\n\n", 1, true)
    if not sep then
      return buffer
    end
    local block = buffer:sub(1, sep - 1)
    buffer = buffer:sub(sep + 2)

    local event, data = nil, nil
    for line in (block .. "\n"):gmatch("(.-)\n") do
      local ev = line:match("^event:%s?(.*)$")
      local da = line:match("^data:%s?(.*)$")
      if ev then
        event = ev
      elseif da then
        data = da
      end
    end
    if event then
      local decoded = nil
      if data and data ~= "" then
        local ok, v = pcall(vim.json.decode, data)
        decoded = ok and v or nil
      end
      on_event(event, decoded)
    end
  end
end

--- POST a JSON body to `path` and consume the SSE response.
---@param path string e.g. "/chat"
---@param body table encoded as JSON request body
---@param callbacks table { on_token=fun(content), on_done=fun(), on_error=fun(msg) }
---@return vim.SystemObj handle (supports :kill() to cancel)
function M.stream(path, body, callbacks)
  local on_token = callbacks.on_token or function() end
  local on_done = callbacks.on_done or function() end
  local on_error = callbacks.on_error or function() end

  local url = daemon_url() .. path
  local payload = vim.json.encode(body)
  log.info(("stream: POST %s (%d bytes)"):format(url, #payload))

  local pending = ""
  local counts = { token = 0, done = 0, error = 0, other = 0 }
  local first_token_logged = false
  local errored = false

  local function handle_event(event, data)
    if event == "token" then
      counts.token = counts.token + 1
      if not first_token_logged then
        first_token_logged = true
        log.debug("stream: first token received")
      end
      on_token(data and data.content or "")
    elseif event == "done" then
      counts.done = counts.done + 1
      log.info(("stream: done (%d tokens)"):format(counts.token))
      on_done()
    elseif event == "error" then
      counts.error = counts.error + 1
      errored = true
      local m = data and data.message or "unknown error"
      log.error("stream: server error — " .. m)
      on_error(m)
    else
      counts.other = counts.other + 1
      log.debug("stream: unknown event '" .. tostring(event) .. "'")
    end
  end

  return vim.system(
    {
      "curl", "-sS", "-N", "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", payload,
      url,
    },
    {
      text = true,
      stdout = function(err, chunk)
        if err then
          log.debug("stream: stdout err " .. tostring(err))
          return
        end
        if not chunk then
          return -- end of stdout
        end
        vim.schedule(function()
          pending = drain_events(pending .. chunk, handle_event)
        end)
      end,
    },
    function(res)
      vim.schedule(function()
        log.debug(("stream: curl exited code=%d, events token=%d done=%d error=%d other=%d")
          :format(res.code, counts.token, counts.done, counts.error, counts.other))
        if res.code ~= 0 then
          on_error(("curl exit %d: %s"):format(res.code, (res.stderr or ""):gsub("%s+$", "")))
        elseif counts.done == 0 and not errored then
          -- Clean exit but no terminating event: surface it so the UI doesn't hang silently.
          on_error("stream ended without a 'done' event (daemon reachable? model loaded?)")
        end
      end)
    end
  )
end

return M
