-- Specs for ami.context: token estimation and the assemble() context builder
-- (section ordering, fenced blocks, relative paths, the context.extra collector,
-- and token-budget trimming). Ported from the former Go daemon; these pin the
-- output shape.
local T = require("tests.minitest")
local context = require("ami.context")
local events = require("ami.events")

T.describe("context.estimate_tokens", function()
  T.it("is 0 for nil/empty", function()
    T.eq(context.estimate_tokens(nil), 0)
    T.eq(context.estimate_tokens(""), 0)
  end)

  T.it("is roughly chars/4", function()
    T.eq(context.estimate_tokens(("x"):rep(4)), 1)
    T.eq(context.estimate_tokens(("x"):rep(40)), 10)
  end)
end)

T.describe("context.assemble", function()
  T.it("wraps the active file in a fenced section with a relative path", function()
    events.clear()
    local out = context.assemble({
      project_root = "/proj",
      active_path = "/proj/src/main.lua",
      active_content = "local x = 1",
    }, 8000)
    T.contains(out, "## Active file: src/main.lua")
    T.contains(out, "```\nlocal x = 1\n```")
  end)

  T.it("labels an unsaved buffer", function()
    events.clear()
    local out = context.assemble({ active_path = "", active_content = "scratch" }, 8000)
    T.contains(out, "## Active file: (unsaved buffer)")
  end)

  T.it("omits empty selection / content sections", function()
    events.clear()
    local out = context.assemble({ active_path = "/p/a", active_content = "", selection = "  " }, 8000)
    T.excludes(out, "## Selection")
    T.excludes(out, "## Active file")
  end)

  T.it("orders sections: selection → active → deps → context.extra → README", function()
    events.clear()
    -- a temp project with a dependency file and a README
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local dep = root .. "/dep.lua"
    vim.fn.writefile({ "return 42" }, dep)
    vim.fn.writefile({ "# Readme body" }, root .. "/README.md")

    events.on("context.extra", function() return { title = "Extra Bits", body = "hello" } end)

    local out = context.assemble({
      project_root = root,
      active_path = root .. "/main.lua",
      active_content = "print(1)",
      selection = "print(1)",
      cursor_line = 7,
      dep_paths = { dep },
    }, 8000)

    local function pos(h) return (out:find(h, 1, true)) or math.huge end
    local sel = pos("## Selection in main.lua (around line 7)")
    local act = pos("## Active file: main.lua")
    local dp = pos("## Dependency: dep.lua")
    local ex = pos("## Extra Bits")
    local rd = pos("## README.md")

    T.ok(sel < act, "selection before active")
    T.ok(act < dp, "active before dependency")
    T.ok(dp < ex, "dependency before context.extra")
    T.ok(ex < rd, "context.extra before README")
    T.contains(out, "return 42") -- dep body was read from disk
    T.contains(out, "hello") -- the extra contribution
  end)

  T.it("accepts a plain string from a context.extra handler", function()
    events.clear()
    events.on("context.extra", function() return "just a string" end)
    local out = context.assemble({ active_path = "/p/a", active_content = "x" }, 8000)
    T.contains(out, "## Context")
    T.contains(out, "just a string")
  end)

  T.it("a nil contribution adds nothing", function()
    events.clear()
    events.on("context.extra", function() return nil end)
    local out = context.assemble({ active_path = "/p/a", active_content = "x" }, 8000)
    T.excludes(out, "## Context")
  end)

  T.it("trims trailing sections past the token budget", function()
    events.clear()
    local big = ("word "):rep(500) -- ~2500 chars ≈ 625 tokens
    local out = context.assemble({
      project_root = "/p",
      active_path = "/p/a",
      active_content = big,
      selection = big,
    }, 120) -- budget smaller than one section
    T.contains(out, "## Selection") -- first section always kept
    T.contains(out, "further context omitted")
    T.excludes(out, "## Active file") -- dropped to stay in budget
  end)
end)
