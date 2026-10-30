-- ami.context: gather editor/project context to send with a chat turn.
--
-- Base context (Stage 1): project root, active buffer path + contents, optional
-- selection, language, cursor line.
-- Dependency expansion (Stage 2): LSP definition locations of the symbols near
-- the cursor (or within a selected range) are resolved to file paths and sent as
-- dep_paths; the daemon reads and trims them.
local config = require("ami.config")
local events = require("ami.events")
local log = require("ami.log")

local M = {}

local ROOT_MARKERS = { ".git", "PLAN.md", "README.md", "go.mod" }

-- True if some LSP client attached to `bufnr` can answer textDocument/definition.
-- Checking the capability up front avoids Neovim's "method ... is not supported
-- by any of the servers" error when the only attached server (e.g. a markdown
-- LSP on a PLAN.md) has no definitionProvider.
local function any_client_supports_definition(bufnr)
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local caps = c.server_capabilities
    if caps and caps.definitionProvider then
      return true
    end
  end
  return false
end

--- Best-effort project root for the given buffer.
---@param bufnr integer|nil
---@return string
function M.project_root(bufnr)
  local root = vim.fs.root(bufnr or 0, ROOT_MARKERS)
  return root or (vim.uv or vim.loop).cwd()
end

-- Base context refs (no dependency resolution).
local function base_refs(bufnr, winid, selection)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local cursor_line = 0
  if winid and vim.api.nvim_win_is_valid(winid) then
    cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
  end

  return {
    project_root = M.project_root(bufnr),
    active_path = name,
    active_content = table.concat(lines, "\n"),
    selection = selection or "",
    language = vim.bo[bufnr].filetype,
    cursor_line = cursor_line,
    dep_paths = {},
  }
end

--- Synchronous base context (no LSP). Kept for callers/tests that don't need deps.
---@param bufnr integer|nil
---@param winid integer|nil
---@param selection string|nil
---@return table
function M.gather(bufnr, winid, selection)
  bufnr = (bufnr and vim.api.nvim_buf_is_valid(bufnr)) and bufnr or vim.api.nvim_get_current_buf()
  return base_refs(bufnr, winid, selection)
end

--- Text of the last visual selection (marks '< '>), or "" if none.
---@return string
function M.last_selection()
  local ok, region = pcall(function()
    return vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
  end)
  if ok and type(region) == "table" and #region > 0 then
    return table.concat(region, "\n")
  end
  return ""
end

-- Collect {line, character} (0-indexed) positions of identifiers on the given
-- 0-indexed buffer lines, capped at `limit`.
local function identifier_positions(bufnr, line_nums, limit)
  local positions = {}
  for _, l in ipairs(line_nums) do
    local line = vim.api.nvim_buf_get_lines(bufnr, l, l + 1, false)[1] or ""
    local init = 1
    while #positions < limit do
      local s, e = line:find("[%a_][%w_]*", init)
      if not s then
        break
      end
      positions[#positions + 1] = { line = l, character = s - 1 }
      init = e + 1
    end
    if #positions >= limit then
      break
    end
  end
  return positions
end

-- Pull file paths out of a textDocument/definition result (Location,
-- Location[], or LocationLink[]).
local function extract_paths(result, into)
  if not result then
    return
  end
  local items = result
  if result.uri or result.targetUri then
    items = { result }
  end
  for _, loc in ipairs(items) do
    local uri = loc.uri or loc.targetUri
    if uri then
      into[#into + 1] = vim.uri_to_fname(uri)
    end
  end
end

--- Gather context including LSP-resolved dependency files, then call cb(refs).
--- Falls back to base context (empty dep_paths) when LSP is unavailable or
--- disabled, or if the LSP round-trip exceeds the configured timeout.
---@param bufnr integer|nil source code buffer
---@param winid integer|nil window showing it (for cursor line)
---@param selection string|nil pre-captured visual selection
---@param range integer[]|nil {line1, line2} (1-indexed) to scan instead of cursor
---@param cb fun(refs: table)
function M.gather_async(bufnr, winid, selection, range, cb)
  bufnr = (bufnr and vim.api.nvim_buf_is_valid(bufnr)) and bufnr or vim.api.nvim_get_current_buf()
  local refs = base_refs(bufnr, winid, selection)

  -- Emit context_assembled just before handing the refs back, whichever path we
  -- return by. Extensions may MUTATE refs here (e.g. add dep_paths or notes).
  do
    local user_cb = cb
    cb = function(r)
      events.emit("context_assembled", r, { bufnr = bufnr, winid = winid })
      user_cb(r)
    end
  end

  local cctx = config.options.context or {}
  if cctx.lsp_deps == false or not any_client_supports_definition(bufnr) then
    return cb(refs)
  end

  -- Which lines to scan for identifiers.
  local line_nums = {}
  if range and range[1] and range[2] then
    for l = range[1] - 1, range[2] - 1 do
      line_nums[#line_nums + 1] = l
    end
  else
    local cl = 0
    if winid and vim.api.nvim_win_is_valid(winid) then
      cl = vim.api.nvim_win_get_cursor(winid)[1] - 1
    end
    line_nums = { cl }
  end

  local positions = identifier_positions(bufnr, line_nums, cctx.dep_max_positions or 30)
  if #positions == 0 then
    return cb(refs)
  end

  local max_files = cctx.dep_max_files or 5
  local seen = { [refs.active_path] = true }
  local order = {}
  local outstanding = #positions
  local finished = false

  local function finish()
    if finished then
      return
    end
    finished = true
    local capped = {}
    for i = 1, math.min(#order, max_files) do
      capped[i] = order[i]
    end
    refs.dep_paths = capped
    log.debug(("context: resolved %d dependency file(s) from %d symbol position(s)"):format(#capped, #positions))
    cb(refs)
  end

  local uri = vim.uri_from_bufnr(bufnr)
  for _, pos in ipairs(positions) do
    local params = { textDocument = { uri = uri }, position = pos }
    vim.lsp.buf_request_all(bufnr, "textDocument/definition", params, function(results)
      local paths = {}
      if results then
        for _, r in pairs(results) do
          extract_paths(r and r.result, paths)
        end
      end
      for _, p in ipairs(paths) do
        if p ~= "" and not seen[p] then
          seen[p] = true
          order[#order + 1] = p
        end
      end
      outstanding = outstanding - 1
      if outstanding <= 0 then
        finish()
      end
    end)
  end

  -- Don't let a slow or unresponsive server stall the turn.
  vim.defer_fn(finish, cctx.dep_timeout_ms or 1500)
end

-- Context assembly -----------------------------------------------------------
-- Build the single context string sent with a chat turn, ordered by importance
-- (selection > active buffer > LSP deps > README/PLAN) and trimmed to a token
-- budget. Ported from the former Go daemon (internal/context/assemble.go).

--- Rough token estimate (~4 chars/token); good enough for budgeting.
---@param s string|nil
---@return integer
function M.estimate_tokens(s)
  return math.floor(#(s or "") / 4)
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local data = fd:read("*a")
  fd:close()
  return data
end

-- Path relative to root, or the original path when it isn't under root.
local function relpath(root, path)
  if root and root ~= "" and path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return path
end

local function display_path(refs)
  if not refs.active_path or refs.active_path == "" then
    return "(unsaved buffer)"
  end
  return relpath(refs.project_root, refs.active_path)
end

-- Concatenate sections into fenced blocks, trimming the last ones that overflow.
local function render(sections, budget)
  local parts, used = {}, 0
  for _, s in ipairs(sections) do
    local block = ("## %s\n\n```\n%s\n```\n\n"):format(s.title, s.body)
    local cost = M.estimate_tokens(block)
    if used + cost > budget and used > 0 then
      parts[#parts + 1] = "_(further context omitted to stay within the token budget)_\n"
      break
    end
    if cost > budget then -- a single section bigger than the whole budget
      local max_chars = budget * 4
      if max_chars < #block then
        block = block:sub(1, max_chars) .. "\n…(truncated)…\n```\n\n"
      end
    end
    parts[#parts + 1] = block
    used = used + cost
  end
  return vim.trim(table.concat(parts))
end

--- Assemble the context block from refs, within `budget` tokens.
---@param refs table from gather/gather_async
---@param budget integer token budget
---@return string
function M.assemble(refs, budget)
  refs = refs or {}
  budget = budget or 8000
  local sections = {}

  local sel = vim.trim(refs.selection or "")
  if sel ~= "" then
    sections[#sections + 1] = {
      title = ("Selection in %s (around line %d)"):format(display_path(refs), refs.cursor_line or 0),
      body = sel,
    }
  end
  local content = vim.trim(refs.active_content or "")
  if content ~= "" then
    sections[#sections + 1] = { title = "Active file: " .. display_path(refs), body = content }
  end

  local seen = { [refs.active_path or ""] = true }
  for _, p in ipairs(refs.dep_paths or {}) do
    if p ~= "" and not seen[p] then
      seen[p] = true
      local data = read_file(p)
      if data then
        sections[#sections + 1] = { title = "Dependency: " .. relpath(refs.project_root, p), body = data }
      end
    end
  end

  if refs.project_root and refs.project_root ~= "" then
    for _, name in ipairs({ "README.md", "PLAN.md" }) do
      local data = read_file(refs.project_root .. "/" .. name)
      if data then
        sections[#sections + 1] = { title = name, body = data }
      end
    end
  end

  return render(sections, budget)
end

return M
