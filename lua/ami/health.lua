-- :checkhealth ami
local M = {}

local function exe(name)
  return vim.fn.executable(name) == 1
end

local function sync_get(url)
  local res = vim.system({ "curl", "-sS", "-m", "3", url }, { text = true }):wait()
  return res.code == 0, res.stdout or ""
end

function M.check()
  local h = vim.health
  h.start("ami")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Neovim 0.10+ is required (uses vim.system / vim.uv / vim.fs.root)")
  end

  if exe("curl") then
    h.ok("curl found")
  else
    h.error("curl not found on PATH (required for all requests)")
  end

  local cfg = require("ami.config").options

  -- Check each registered model slot's provider endpoint, de-duplicated.
  local models = require("ami.models")
  local checked = {}
  local function check_ep(label, ep)
    ep = ep or ""
    if ep ~= "" and not checked[ep] then
      checked[ep] = true
      if sync_get(ep .. "/models") then
        h.ok(("%s provider reachable at %s"):format(label, ep))
      else
        h.error(("%s provider not reachable at %s — start it or fix the endpoint"):format(label, ep))
      end
    end
  end
  local names = models.slot_names()
  if #names == 0 then
    check_ep("default", (cfg.model or {}).endpoint)
  else
    for _, name in ipairs(names) do
      check_ep(name, models.effective(name).endpoint)
    end
  end
end

return M
