-- ami.extensions: the extension registry and the stable API handed to each
-- extension's setup().
--
-- ami's core is deliberately small; optional capabilities are *extensions* —
-- self-contained Lua tables that hook the lifecycle through this API instead of
-- reaching into core internals. An extension can live in this repo or, more
-- usefully, in its own Neovim plugin repo that returns a spec (see
-- docs/extensions.md). Register them by passing specs (or module names to
-- require) to ami.setup({ extensions = { ... } }).
--
-- A spec looks like:
--   {
--     name = "proactive",                  -- unique; namespaces config + commands
--     config = { ... },                    -- defaults, merged UNDER user config
--     commands = { AmiFoo = { desc=, nargs=, range=, complete=, fn= } },
--     events = { buf_write = function(bufnr) ... end },
--     setup = function(api) ... end,
--   }
local config = require("ami.config")
local events = require("ami.events")
local log = require("ami.log")

local M = {}

---@type table<string, table>  name -> spec
local by_name = {}
---@type table[] registration order
local order = {}
---@type table<string, boolean> names the user asked to skip
local disabled = {}
---@type table<string, any> capability -> provider impl
local providers = {}
---@type table[] { name, fn } health checks contributed by extensions
local health_checks = {}

--- Mark extensions (by name) to skip at registration. Called by ami.setup().
---@param names string[]|nil
function M.disable(names)
  for _, n in ipairs(names or {}) do
    disabled[n] = true
  end
end

--- Register one extension: a spec table, or a string module name to require().
--- Idempotent per name; duplicates and disabled names are ignored.
---@param spec table|string
function M.register(spec)
  if type(spec) == "string" then
    local ok, mod = pcall(require, spec)
    if not ok then
      log.error("extensions: could not require '" .. spec .. "' — " .. tostring(mod))
      return
    end
    spec = mod
  end
  if type(spec) ~= "table" or type(spec.name) ~= "string" or spec.name == "" then
    log.error("extensions: invalid spec (an extension needs a non-empty string `name`)")
    return
  end
  if disabled[spec.name] then
    log.debug("extensions: '" .. spec.name .. "' disabled — skipping")
    return
  end
  if by_name[spec.name] then
    log.warn("extensions: '" .. spec.name .. "' already registered — ignoring duplicate")
    return
  end
  by_name[spec.name] = spec
  order[#order + 1] = spec
  log.debug("extensions: registered '" .. spec.name .. "'")
end

-- The curated surface an extension sees. Core modules are required lazily to
-- avoid load-order cycles and so an extension only pulls in what it touches.
local function make_api(spec)
  local api = {}
  api.name = spec.name
  api.log = log

  -- Per-extension config subtable (config.options[name]), defaults merged under
  -- any user-supplied override so the user always wins.
  config.options[spec.name] =
    vim.tbl_deep_extend("force", vim.deepcopy(spec.config or {}), config.options[spec.name] or {})
  api.config = config.options[spec.name]

  function api.notify(msg, level)
    vim.notify("ami: " .. msg, level or vim.log.levels.INFO)
  end

  function api.on(event, fn)
    return events.on(event, fn)
  end

  --- Register a user command (:name). `cspec` = { desc, nargs, range, complete, fn }.
  function api.command(name, cspec)
    vim.api.nvim_create_user_command(name, function(o)
      cspec.fn(o)
    end, {
      desc = cspec.desc,
      nargs = cspec.nargs,
      range = cspec.range,
      complete = cspec.complete,
      bang = cspec.bang,
    })
  end

  --- Offer an implementation for a named capability (e.g. "chat", "chat_ui").
  --- Core, or another extension, looks it up with api.resolve / extensions.resolve.
  function api.provide(cap, impl)
    if providers[cap] then
      log.warn(("extensions: '%s' overrides the existing provider for '%s'"):format(spec.name, cap))
    end
    providers[cap] = impl
  end

  --- Look up a capability provider (or nil).
  function api.resolve(cap)
    return M.resolve(cap)
  end

  --- Emit a lifecycle event (e.g. a chat extension emits chat_turn_pre/post).
  function api.emit(event, ...)
    return require("ami.events").emit(event, ...)
  end

  --- Emit a collector hook and return each handler's non-nil return (see
  --- ami.events.emit_collect). For "contribution" points like chat.system /
  --- context.extra where the caller composes the returned pieces itself.
  function api.emit_collect(event, ...)
    return require("ami.events").emit_collect(event, ...)
  end

  --- Contribute a :checkhealth ami section. `fn(report)` receives a reporter with
  --- ok/warn/error/info; each call renders a line under this extension's heading.
  function api.health(fn)
    health_checks[#health_checks + 1] = { name = spec.name, fn = fn }
  end

  -- Curated access to chat, which is itself a capability provided by a chat
  -- extension (e.g. ami-chat.nvim). These proxy to whatever registered "chat";
  -- they are safe no-ops when no chat extension is loaded.
  local function chat_cap()
    return M.resolve("chat")
  end
  api.chat = {
    add_proactive = function(text)
      local c = chat_cap()
      if c then c.add_proactive(text) end
    end,
    append = function(text)
      local c = chat_cap()
      if c then c.append(text) end
    end,
    open = function()
      local c = chat_cap()
      if c then c.open() end
    end,
    session = function()
      local c = chat_cap()
      return c and c.session() or "default"
    end,
    model = function()
      return require("ami.models").effective("chat").model
    end,
    source = function()
      local c = chat_cap()
      if c then return c.source() end
    end,
    set_source = function(buf, win)
      local c = chat_cap()
      if c then c.set_source(buf, win) end
    end,
    is_streaming = function()
      local c = chat_cap()
      return c and c.is_streaming() or false
    end,
  }

  -- LM Studio / OpenAI-compatible client (ami talks to the provider directly).
  api.client = {
    stream_chat = function(...)
      return require("ami.client").stream_chat(...)
    end,
    complete = function(...)
      return require("ami.client").complete(...)
    end,
    models_from = function(...)
      return require("ami.client").models_from(...)
    end,
  }

  -- Context assembly.
  api.context = {
    gather_async = function(...)
      return require("ami.context").gather_async(...)
    end,
    project_root = function(...)
      return require("ami.context").project_root(...)
    end,
    last_selection = function(...)
      return require("ami.context").last_selection(...)
    end,
    assemble = function(...)
      return require("ami.context").assemble(...)
    end,
    estimate_tokens = function(...)
      return require("ami.context").estimate_tokens(...)
    end,
  }

  -- Model registry: register a selectable model slot, read the default, or resolve
  -- a slot's effective { endpoint, model }. See ami.models.
  api.models = {
    register = function(slot)
      return require("ami.models").register(slot)
    end,
    default = function()
      return require("ami.models").default()
    end,
    effective = function(name)
      return require("ami.models").effective(name)
    end,
  }

  return api
end

local function setup_one(spec)
  local api = make_api(spec)
  for name, cspec in pairs(spec.commands or {}) do
    api.command(name, cspec)
  end
  for event, fn in pairs(spec.events or {}) do
    api.on(event, fn)
  end
  if type(spec.setup) == "function" then
    spec.setup(api)
  end
end

--- Build the API for, and run setup() on, every registered extension. Then emit
--- the `setup` lifecycle event. Call once, from ami.setup().
function M.setup_all()
  for _, spec in ipairs(order) do
    local ok, err = pcall(setup_one, spec)
    if not ok then
      log.error(("extensions: '%s' setup failed — %s"):format(spec.name, tostring(err)))
    end
  end
  events.emit("setup")
end

--- Names of the registered extensions, in registration order.
---@return string[]
function M.list()
  local names = {}
  for _, spec in ipairs(order) do
    names[#names + 1] = spec.name
  end
  return names
end

--- Look up a capability provider offered via api.provide (or nil).
---@param cap string
function M.resolve(cap)
  return providers[cap]
end

--- Health checks contributed by extensions, in registration order. Consumed by
--- the :checkhealth ami handler.
---@return table[] { name, fn }
function M.health_checks()
  return health_checks
end

--- Reset all registry state. For tests only.
function M._reset()
  by_name, order, disabled, providers, health_checks = {}, {}, {}, {}, {}
end

return M
