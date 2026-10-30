-- ami.daemon: manage the amid lifecycle with cross-process reference
-- counting, so the daemon survives while *any* Neovim instance is using it and
-- stops only when the last one leaves.
--
-- A registry file (per daemon address) under stdpath("state") tracks the
-- attached instance PIDs and the managed daemon PID. A mkdir-based lock
-- serializes access across processes. The daemon is spawned detached so it
-- outlives the instance that started it; the last instance to leave kills it by
-- PID. Dead instance PIDs are pruned (via kill(pid,0)) so a crashed editor can't
-- pin the daemon forever. A daemon you run yourself (no managed PID recorded) is
-- never killed.
local config = require("ami.config")
local client = require("ami.client")
local log = require("ami.log")

local uv = vim.uv or vim.loop

local M = { proc = nil }

local function dcfg()
  return config.options.daemon or {}
end

-- Paths ----------------------------------------------------------------------

local function state_dir()
  local d = vim.fs.joinpath(vim.fn.stdpath("state"), "ami")
  vim.fn.mkdir(d, "p")
  return d
end

local function key()
  return (config.options.daemon_url or "default"):gsub("%W", "_")
end

local function reg_file() return vim.fs.joinpath(state_dir(), key() .. ".json") end
local function lock_dir() return vim.fs.joinpath(state_dir(), key() .. ".lock") end
local function log_file() return vim.fs.joinpath(state_dir(), key() .. ".log") end

local function bin_path()
  local c = dcfg()
  if c.bin and c.bin ~= "" then
    return vim.fn.expand(c.bin)
  end
  local src = debug.getinfo(1, "S").source:sub(2) -- .../lua/ami/daemon.lua
  return vim.fn.fnamemodify(src, ":h:h:h") .. "/bin/amid"
end

-- Process liveness -----------------------------------------------------------

local function is_alive(pid)
  if not pid then
    return false
  end
  local ok, res = pcall(uv.kill, pid, 0)
  return ok and res == 0
end

-- Registry (locked) ----------------------------------------------------------

local function acquire_lock()
  local deadline = uv.now() + 2000
  while true do
    local ok, res = pcall(uv.fs_mkdir, lock_dir(), 448) -- 0700
    if ok and res then
      return true
    end
    -- Steal an obviously stale lock (holder crashed mid-section).
    local st = uv.fs_stat(lock_dir())
    if st and (os.time() - st.mtime.sec) > 10 then
      pcall(uv.fs_rmdir, lock_dir())
    end
    if uv.now() > deadline then
      return false
    end
    uv.sleep(20)
  end
end

local function release_lock()
  pcall(uv.fs_rmdir, lock_dir())
end

local function read_reg()
  local fd = io.open(reg_file(), "r")
  if not fd then
    return { instances = {}, managed_pid = nil }
  end
  local content = fd:read("*a")
  fd:close()
  local ok, t = pcall(vim.json.decode, content)
  if not ok or type(t) ~= "table" then
    return { instances = {}, managed_pid = nil }
  end
  t.instances = t.instances or {}
  return t
end

local function write_reg(t)
  local fd = io.open(reg_file(), "w")
  if not fd then
    return
  end
  fd:write(vim.json.encode(t))
  fd:close()
end

-- Drop dead instance PIDs and a dead managed PID.
local function prune(reg)
  for pidstr in pairs(reg.instances) do
    if not is_alive(tonumber(pidstr)) then
      reg.instances[pidstr] = nil
    end
  end
  if reg.managed_pid and not is_alive(reg.managed_pid) then
    reg.managed_pid = nil
  end
  return reg
end

-- Run fn while holding the cross-process lock. Proceeds without the lock (with a
-- warning) rather than deadlocking if it can't be acquired.
local function with_lock(fn)
  local locked = acquire_lock()
  if not locked then
    log.warn("daemon: could not acquire registry lock; proceeding unlocked")
  end
  local ok, res = pcall(fn)
  if locked then
    release_lock()
  end
  if not ok then
    error(res)
  end
  return res
end

-- Spawning -------------------------------------------------------------------

local function build_env()
  local env = {}
  local addr = (config.options.daemon_url or ""):gsub("^%w+://", ""):gsub("/+$", "")
  if addr ~= "" then
    env.AMI_ADDR = addr
  end
  -- Resolve the chat provider through the model registry (chat slot overrides,
  -- else the default model slot).
  local chat = require("ami.models").effective("chat")
  if chat.endpoint and chat.endpoint ~= "" then
    env.AMI_LMSTUDIO_URL = chat.endpoint
  end
  if chat.model and chat.model ~= "" then
    env.AMI_CHAT_MODEL = chat.model
  end
  -- Session storage: nil -> stdpath("data")/ami (out of the user's repos);
  -- "" -> leave unset so the daemon uses each project's own .ami dir.
  local sdir = config.options.session_dir
  if sdir == nil then
    sdir = vim.fs.joinpath(vim.fn.stdpath("data"), "ami")
  end
  if sdir ~= "" then
    vim.fn.mkdir(sdir, "p")
    env.AMI_DATA_DIR = sdir
  end
  return env
end

local function try_build(bin)
  if dcfg().auto_build == false then
    return false
  end
  local root = vim.fn.fnamemodify(bin, ":h:h")
  if vim.fn.executable("go") == 0 or vim.fn.filereadable(root .. "/go.mod") == 0 then
    return false
  end
  log.info("daemon: building amid…")
  local res = vim.system({ "go", "build", "-o", bin, "./cmd/amid" }, { cwd = root }):wait()
  if res.code ~= 0 then
    log.error("daemon: build failed: " .. (res.stderr or ""))
    return false
  end
  return vim.fn.executable(bin) == 1
end

-- Launch a detached daemon (survives this instance's exit); returns its PID.
local function spawn()
  local bin = bin_path()
  if vim.fn.executable(bin) == 0 and not try_build(bin) then
    log.error("daemon: binary not found at " .. bin .. " (run `make build`)")
    return nil
  end
  local lf = log_file()
  -- `exec` keeps the PID == amid's; redirect its output to a persistent log.
  local cmd = { "sh", "-c", "exec " .. vim.fn.shellescape(bin) .. " > " .. vim.fn.shellescape(lf) .. " 2>&1" }
  log.info("daemon: starting " .. bin .. " (log: " .. lf .. ")")
  M.proc = vim.system(cmd, { env = build_env(), detach = true })
  return M.proc.pid
end

local function external_present()
  local res = vim.system({ "curl", "-sS", "-m", "2", (config.options.daemon_url or "") .. "/health" }, { text = true }):wait()
  return res.code == 0
end

local function wait_ready(n)
  if n > 20 then
    log.warn("daemon: started but not responding yet")
    return
  end
  client.health(function(ok)
    if ok then
      log.info("daemon: ready")
      vim.notify("ami: daemon started", vim.log.levels.INFO)
    else
      vim.defer_fn(function() wait_ready(n + 1) end, 300)
    end
  end, { quiet = true })
end

local function me()
  return tostring(vim.fn.getpid())
end

-- Public API -----------------------------------------------------------------

--- Ensure a daemon is running and register this instance (ref++).
function M.ensure()
  if dcfg().auto_start == false then
    return
  end
  local started = false
  with_lock(function()
    local reg = prune(read_reg())
    reg.instances[me()] = os.time()
    if not reg.managed_pid then
      if external_present() then
        log.debug("daemon: using an externally-run daemon")
      else
        local pid = spawn()
        if pid then
          reg.managed_pid = pid
          started = true
        end
      end
    else
      log.debug("daemon: reusing managed daemon pid=" .. reg.managed_pid)
    end
    write_reg(reg)
  end)
  if started then
    wait_ready(0)
  end
end

--- Release this instance (ref--); kill the managed daemon if we were the last.
function M.release()
  with_lock(function()
    local reg = prune(read_reg())
    reg.instances[me()] = nil
    if vim.tbl_count(reg.instances) == 0 and reg.managed_pid then
      log.info("daemon: last instance leaving — stopping pid=" .. reg.managed_pid)
      pcall(uv.kill, reg.managed_pid, "sigterm")
      reg.managed_pid = nil
    end
    write_reg(reg)
  end)
end

--- Manually (re)ensure a managed daemon, registering this instance.
function M.start()
  local started = false
  with_lock(function()
    local reg = prune(read_reg())
    reg.instances[me()] = os.time()
    if reg.managed_pid then
      vim.notify("ami: daemon already running (pid=" .. reg.managed_pid .. ")", vim.log.levels.INFO)
    elseif external_present() then
      vim.notify("ami: a daemon is already running (not managed)", vim.log.levels.INFO)
    else
      local pid = spawn()
      if pid then
        reg.managed_pid = pid
        started = true
      end
    end
    write_reg(reg)
  end)
  if started then
    wait_ready(0)
  end
end

--- Force-stop the managed daemon regardless of other instances.
function M.force_stop()
  with_lock(function()
    local reg = prune(read_reg())
    if reg.managed_pid then
      pcall(uv.kill, reg.managed_pid, "sigterm")
      reg.managed_pid = nil
      vim.notify("ami: daemon stopped", vim.log.levels.INFO)
    else
      vim.notify("ami: no managed daemon to stop", vim.log.levels.WARN)
    end
    write_reg(reg)
  end)
end

--- Restart the managed daemon (stop then start a fresh one).
function M.restart()
  with_lock(function()
    local reg = prune(read_reg())
    if reg.managed_pid then
      pcall(uv.kill, reg.managed_pid, "sigterm")
      reg.managed_pid = nil
    end
    reg.instances[me()] = os.time()
    write_reg(reg)
  end)
  vim.defer_fn(function()
    local pid = spawn()
    if pid then
      with_lock(function()
        local reg = prune(read_reg())
        reg.managed_pid = pid
        write_reg(reg)
      end)
      wait_ready(0)
    end
  end, 400)
end

--- Set up lifecycle: register + ensure on setup, release on exit.
function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("AmiDaemon", { clear = true }),
    callback = function() M.release() end,
  })
  M.ensure()
end

return M
