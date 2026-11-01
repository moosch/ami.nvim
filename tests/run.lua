-- Headless test runner. Invoked via:  nvim --clean --headless -l tests/run.lua
--
-- Puts the plugin's lua/ and the repo root on package.path (so require("ami.x")
-- and require("tests.x") resolve without a plugin manager), loads every
-- tests/*_spec.lua, runs them, and exits non-zero on any failure so CI fails.
local here = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fs.dirname(here)
local root = vim.fs.dirname(tests_dir)

package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua", -- so require("tests.minitest") works
  package.path,
}, ";")

local T = require("tests.minitest")

-- Load every spec (sorted for stable order).
local specs = vim.fn.glob(tests_dir .. "/*_spec.lua", false, true)
table.sort(specs)
for _, path in ipairs(specs) do
  local name = vim.fn.fnamemodify(path, ":t:r")
  require("tests." .. name)
end

local ok = T.run()
-- Quit with the right exit code so CI fails on a red suite. `:cquit N` exits with
-- code N; a plain `:qa!` always exits 0, which would hide failures.
if ok then
  vim.cmd("qa!")
else
  vim.cmd("cquit 1")
end
