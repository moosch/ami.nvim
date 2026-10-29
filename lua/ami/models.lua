-- ami.models: runtime model selector for the chat and FIM (inline) models.
--
-- Models are chosen at runtime (they change often), not pinned in config — the
-- config values are only the defaults/fallbacks. Selection uses vim.ui.select,
-- so it inherits whatever picker the user has (telescope/fzf/snacks/built-in).
local client = require("ami.client")
local config = require("ami.config")
local log = require("ami.log")

local M = {}

--- Current models: chat (fallback to daemon default) and FIM.
function M.get()
  return {
    chat = config.options.chat_model,
    fim = (config.options.inline or {}).model,
  }
end

local function set(target, choice)
  if target == "fim" then
    config.options.inline = config.options.inline or {}
    config.options.inline.model = choice
  else
    config.options.chat_model = choice
  end
  log.info(("models: %s model → %s"):format(target, choice))
  vim.notify(("ami: %s model → %s"):format(target, choice), vim.log.levels.INFO)
end

--- Pick a model for `target` ("chat" or "fim") from the live LM Studio list.
---@param target "chat"|"fim"
function M.select(target)
  client.models(function(ok, ids)
    if not ok then
      log.error("models: " .. tostring(ids))
      return
    end
    if type(ids) ~= "table" or #ids == 0 then
      vim.notify("ami: no models reported by LM Studio", vim.log.levels.WARN)
      return
    end
    local current = M.get()[target]
    vim.ui.select(ids, {
      prompt = ("Select %s model (current: %s):"):format(target, current or "daemon default"),
      format_item = function(item)
        -- Mark the currently selected model so it stands out in the picker.
        return (item == current and "● " or "  ") .. item
      end,
    }, function(choice)
      if choice then
        set(target, choice)
      end
    end)
  end)
end

--- Two-step picker: choose target (chat/fim), then model.
function M.pick()
  vim.ui.select({ "chat", "fim" }, { prompt = "Set model for:" }, function(target)
    if target then
      M.select(target)
    end
  end)
end

--- Report the current selections.
function M.show()
  local m = M.get()
  vim.notify(("ami models — chat: %s · fim: %s"):format(
    m.chat or "(daemon default)", m.fim or "(none)"), vim.log.levels.INFO)
end

return M
