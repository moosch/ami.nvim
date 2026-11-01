-- Specs for the ami.events pub/sub bus: on/emit, unsubscribe, order, pcall
-- isolation, and the emit_collect contribution variant.
local T = require("tests.minitest")
local events = require("ami.events")

T.describe("events.on / emit", function()
  T.it("calls a handler with the emitted args", function()
    events.clear()
    local got
    events.on("ping", function(a, b) got = { a, b } end)
    events.emit("ping", 1, "two")
    T.eq(got, { 1, "two" })
  end)

  T.it("calls handlers in registration order", function()
    events.clear()
    local seen = {}
    events.on("e", function() seen[#seen + 1] = "a" end)
    events.on("e", function() seen[#seen + 1] = "b" end)
    events.on("e", function() seen[#seen + 1] = "c" end)
    events.emit("e")
    T.eq(seen, { "a", "b", "c" })
  end)

  T.it("emitting an event with no handlers is a no-op", function()
    events.clear()
    events.emit("nobody-listening", 1, 2, 3) -- must not raise
  end)

  T.it("unsubscribe removes just that handler", function()
    events.clear()
    local n = 0
    local off = events.on("e", function() n = n + 1 end)
    events.emit("e")
    off()
    events.emit("e")
    T.eq(n, 1)
  end)

  T.it("a throwing handler is isolated; the rest still run", function()
    events.clear()
    local ran_after = false
    events.on("e", function() error("boom") end)
    events.on("e", function() ran_after = true end)
    events.emit("e") -- must not propagate the error
    T.ok(ran_after, "handler after a throwing one should still run")
  end)

  T.it("handlers mutate a shared payload table in place", function()
    events.clear()
    events.on("context_assembled", function(ctx) ctx.note = "added" end)
    local ctx = {}
    events.emit("context_assembled", ctx)
    T.eq(ctx.note, "added")
  end)

  T.it("on rejects a non-function handler", function()
    T.raises(function() events.on("e", "not a fn") end, "must be a function")
  end)
end)

T.describe("events.emit_collect", function()
  T.it("gathers non-nil returns in registration order", function()
    events.clear()
    events.on("c", function() return "first" end)
    events.on("c", function() return nil end) -- skipped
    events.on("c", function() return "second" end)
    T.eq(events.emit_collect("c"), { "first", "second" })
  end)

  T.it("returns an empty list when there are no handlers", function()
    events.clear()
    T.eq(events.emit_collect("c"), {})
  end)

  T.it("passes args through to collectors", function()
    events.clear()
    events.on("c", function(info) return info.n * 2 end)
    T.eq(events.emit_collect("c", { n = 21 }), { 42 })
  end)

  T.it("a throwing collector is skipped, not fatal", function()
    events.clear()
    events.on("c", function() return "ok" end)
    events.on("c", function() error("nope") end)
    events.on("c", function() return "also ok" end)
    T.eq(events.emit_collect("c"), { "ok", "also ok" })
  end)
end)

T.describe("events.clear", function()
  T.it("clears one event without touching others", function()
    events.clear()
    local a, b = 0, 0
    events.on("a", function() a = a + 1 end)
    events.on("b", function() b = b + 1 end)
    events.clear("a")
    events.emit("a")
    events.emit("b")
    T.eq({ a, b }, { 0, 1 })
  end)
end)
