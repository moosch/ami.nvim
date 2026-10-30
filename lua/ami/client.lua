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
---@return vim.SystemObj handle (supports :kill())
function M.stream_chat(endpoint, body, callbacks)
  local on_token = callbacks.on_token or function() end
  local on_done = callbacks.on_done or function() end
  local on_error = callbacks.on_error or function() end

  body.stream = true
  local url = base(endpoint) .. "/chat/completions"
  local payload = vim.json.encode(body)
  log.info(("stream_chat: POST %s (%d bytes)"):format(url, #payload))

  local pending = ""
  local errored = false
  local tokens = 0

  -- Parse one SSE line (OpenAI format: `data: {json}` / `data: [DONE]`).
  local function handle_line(line)
    local data = line:gsub("\r$", ""):match("^data:%s?(.*)$")
    if not data or data == "" then
      return
    end
    if data == "[DONE]" then
      return
    end
    local ok, obj = pcall(vim.json.decode, data)
    if not ok or type(obj) ~= "table" then
      return
    end
    if obj.error then
      errored = true
      local e = obj.error
      on_error(type(e) == "table" and (e.message or vim.inspect(e)) or tostring(e))
      return
    end
    local choice = obj.choices and obj.choices[1]
    local content = choice and choice.delta and choice.delta.content
    if content and content ~= "" then
      tokens = tokens + 1
      on_token(content)
    end
  end

  return vim.system(
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
        log.debug(("stream_chat: curl exit=%d, tokens=%d"):format(res.code, tokens))
        if errored then
          return -- on_error already fired
        end
        if res.code ~= 0 then
          on_error(("curl exit %d: %s"):format(res.code, (res.stderr or ""):gsub("%s+$", "")))
        else
          on_done()
        end
      end)
    end
  )
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
