-- ami.models: the model registry and a generic runtime selector.
--
-- Core owns one *default* model slot (config.model: base provider + model). Any
-- feature that uses a model registers a *slot* describing its provider and how to
-- read/write its chosen model; a slot with no model of its own falls back to the
-- default. The selector (:AmiModel) is generic — it lists every registered slot,
-- so installing an extension that uses a model makes it selectable automatically.
--
-- A slot:
--   { name = "fim", label = "Inline (FIM)",     -- unique id (+ optional label)
--     endpoint = function() return url|nil end,  -- provider base URL, nil -> default
--     get      = function() return model|nil end,-- current override, nil -> default
--     set      = function(model) ... end }        -- persist the choice
local client = require("ami.client")
local config = require("ami.config")
local log = require("ami.log")

local M = {}

---@type table<string, table>
local slots = {}
---@type string[] registration order
local order = {}

--- The default model slot (base provider + model).
function M.default()
  return config.options.model or {}
end

--- Register (or replace) a model slot.
---@param slot table
function M.register(slot)
  if type(slot) ~= "table" or type(slot.name) ~= "string" or slot.name == "" then
    log.error("models: invalid slot (needs a non-empty string `name`)")
    return
  end
  if not slots[slot.name] then
    order[#order + 1] = slot.name
  end
  slots[slot.name] = slot
  log.debug("models: registered slot '" .. slot.name .. "'")
end

--- Resolve a slot's effective { endpoint, model }, falling back to the default for
--- anything the slot leaves unset.
---@param name string
---@return table {endpoint, model}
function M.effective(name)
  local d = M.default()
  local s = slots[name]
  if not s then
    return { endpoint = d.endpoint, model = d.model }
  end
  local ep = s.endpoint and s.endpoint() or nil
  local m = s.get and s.get() or nil
  return {
    endpoint = (ep and ep ~= "") and ep or d.endpoint,
    model = (m and m ~= "") and m or d.model,
  }
end

--- Registered slot names, in registration order.
---@return string[]
function M.slot_names()
  return vim.list_slice(order)
end

--- Pick a model for the named slot from its provider's live list.
---@param name string
function M.select(name)
  local slot = slots[name]
  if not slot then
    vim.notify("ami: no such model slot '" .. tostring(name) .. "'", vim.log.levels.WARN)
    return
  end
  local eff = M.effective(name)
  client.models_from(eff.endpoint, function(ok, ids)
    if not ok then
      log.error("models: " .. tostring(ids))
      return
    end
    if type(ids) ~= "table" or #ids == 0 then
      vim.notify("ami: no models reported by " .. tostring(eff.endpoint), vim.log.levels.WARN)
      return
    end
    vim.ui.select(ids, {
      prompt = ("Select %s model (current: %s):"):format(name, eff.model or "unset"),
      format_item = function(item)
        -- Mark the effective current model so it stands out.
        return (item == eff.model and "● " or "  ") .. item
      end,
    }, function(choice)
      if not choice then
        return
      end
      if slot.set then
        slot.set(choice)
      end
      log.info(("models: %s model → %s"):format(name, choice))
      vim.notify(("ami: %s model → %s"):format(name, choice), vim.log.levels.INFO)
    end)
  end)
end

--- Two-step picker: choose a slot, then a model.
function M.pick()
  if #order == 0 then
    vim.notify("ami: no model slots registered", vim.log.levels.WARN)
    return
  end
  vim.ui.select(M.slot_names(), {
    prompt = "Set model for:",
    format_item = function(name)
      local s = slots[name]
      return (s and s.label) or name
    end,
  }, function(name)
    if name then
      M.select(name)
    end
  end)
end

--- Report every slot's effective model.
function M.show()
  local parts = {}
  for _, name in ipairs(order) do
    parts[#parts + 1] = ("%s: %s"):format(name, M.effective(name).model or "(unset)")
  end
  local body = (#parts > 0) and table.concat(parts, " · ") or "(no slots)"
  vim.notify("ami models — " .. body, vim.log.levels.INFO)
end

--- Register the core default model slot. Features (including chat, via
--- ami-chat.nvim) register their own slots on top of this.
function M.setup()
  M.register({
    name = "default",
    label = "Default (base provider)",
    endpoint = function() return M.default().endpoint end,
    get = function() return M.default().model end,
    set = function(m)
      config.options.model = config.options.model or {}
      config.options.model.model = m
    end,
  })
end

return M
