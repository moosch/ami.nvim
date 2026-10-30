-- ami: a small runtime for an IDE-resident AI pair programmer (advisor, not actor).
--
-- Core is a pure-Lua runtime: an OpenAI-compatible LLM client, context assembly,
-- the model registry, the event bus, and the extension system. There is no daemon.
-- User-facing features are extensions — chat lives in ami-chat.nvim, inline in
-- ami-inline.nvim, history in ami-history.nvim.
local config = require("ami.config")
local models = require("ami.models")
local events = require("ami.events")
local extensions = require("ami.extensions")

local M = {}

-- Version. Source of truth: the VERSION file at the repo root.
M.version = (function()
  local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local fd = io.open(root .. "/VERSION", "r")
  if not fd then
    return "0.0.0"
  end
  local v = vim.trim(fd:read("*a") or "")
  fd:close()
  return v ~= "" and v or "0.0.0"
end)()

-- Re-export sub-APIs: require("ami").models, .extensions, .events.
M.models = models
M.events = events
M.extensions = extensions

--- Register the :Ami* user commands. Safe to call more than once (later calls
--- overwrite). Called by setup() and by plugin/ami.lua so the commands exist
--- whether the plugin loads at startup or is required live.
function M.register_commands()
  vim.api.nvim_create_user_command("AmiHealth", function()
    vim.cmd("checkhealth ami")
  end, { desc = "Run :checkhealth ami (provider reachability)" })

  vim.api.nvim_create_user_command("AmiModel", function(opts)
    local m = require("ami.models")
    if opts.args ~= "" then
      m.select(opts.args)
    else
      m.pick()
    end
  end, {
    nargs = "?",
    complete = function() return require("ami.models").slot_names() end,
    desc = "Select a model for a registered slot (no arg = choose which)",
  })

  vim.api.nvim_create_user_command("AmiModels", function()
    require("ami.models").show()
  end, { desc = "Show each model slot's current model" })

  vim.api.nvim_create_user_command("AmiExtensions", function()
    local names = require("ami.extensions").list()
    if #names == 0 then
      vim.notify("ami: no extensions loaded", vim.log.levels.INFO)
    else
      vim.notify("ami extensions: " .. table.concat(names, ", "), vim.log.levels.INFO)
    end
  end, { desc = "List the loaded ami extensions" })

  vim.api.nvim_create_user_command("AmiLog", function()
    require("ami.log").open()
  end, { desc = "Open the ami log viewer" })

  vim.api.nvim_create_user_command("AmiDebug", function()
    require("ami.log").toggle_debug()
  end, { desc = "Toggle verbose ami debug logging" })
end

--- Configure the plugin.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  M.register_commands()
  events.install()
  models.setup() -- register the default model slot

  -- Extensions: skip any the user disabled, register the rest (specs or module
  -- names), then run their setup(). ami core ships no active extensions itself.
  extensions.disable(config.options.disable_extensions)
  for _, spec in ipairs(config.options.extensions or {}) do
    extensions.register(spec)
  end
  extensions.setup_all()
end

return M
