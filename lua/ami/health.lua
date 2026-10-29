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

  if exe("go") then
    h.ok("go found (daemon can be auto-built)")
  else
    h.warn("go not found; the daemon must be prebuilt (`make build`)")
  end

  local src = debug.getinfo(1, "S").source:sub(2)
  local bin = vim.fn.fnamemodify(src, ":h:h:h") .. "/bin/amid"
  if vim.fn.executable(bin) == 1 then
    h.ok("amid binary present: " .. bin)
  else
    h.warn("amid not built yet (" .. bin .. ") — runs `make build` / auto-builds on start")
  end

  local cfg = require("ami.config").options
  local ok_d, body = sync_get(cfg.daemon_url .. "/health")
  if ok_d then
    local okj, data = pcall(vim.json.decode, body)
    local ver = (okj and type(data) == "table" and data.version) or "?"
    h.ok(("daemon responding at %s (version %s)"):format(cfg.daemon_url, ver))
  else
    h.info("daemon not running yet — it starts on setup()")
  end

  local ep = (cfg.inline or {}).endpoint or ""
  if sync_get(ep .. "/models") then
    h.ok("LM Studio reachable at " .. ep)
  else
    h.error("LM Studio not reachable at " .. ep .. " — start LM Studio or fix the endpoint")
  end
end

return M
