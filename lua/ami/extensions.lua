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

  --- Offer an implementation for a named capability (e.g. "chat_ui"). Core, or
  --- another extension, can look it up with extensions.resolve(cap).
  function api.provide(cap, impl)
    if providers[cap] then
      log.warn(("extensions: '%s' overrides the existing provider for '%s'"):format(spec.name, cap))
    end
    providers[cap] = impl
  end

  -- Curated access to the chat panel.
  api.chat = {
    add_proactive = function(text)
      require("ami.chat").add_proactive(text)
    end,
    append = function(text)
      require("ami.chat").append(text)
    end,
    open = function()
      require("ami.chat").open()
    end,
    session = function()
      return require("ami.chat").session_id
    end,
    model = function()
      return (require("ami.config").options.chat or {}).model
    end,
    source = function()
      local c = require("ami.chat")
      return c.source_buf, c.source_win
    end,
    set_source = function(buf, win)
      local c = require("ami.chat")
      c.source_buf, c.source_win = buf, win
    end,
    is_streaming = function()
      return require("ami.chat").streaming == true
    end,
  }

  -- Daemon access (same client core uses).
  api.client = {
    stream = function(...)
      return require("ami.client").stream(...)
    end,
    post_json = function(...)
      return require("ami.client").post_json(...)
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

--- Reset all registry state. For tests only.
function M._reset()
  by_name, order, disabled, providers = {}, {}, {}, {}
end

return M
