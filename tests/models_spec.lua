-- Specs for ami.models: the default slot, slot registration, and effective()
-- resolution (a slot's own endpoint/model, else the default fallback).
local T = require("tests.minitest")
local models = require("ami.models")
local config = require("ami.config")

-- Pin a known default for these specs.
config.options.model = { endpoint = "http://base:1234/v1", model = "base-model" }

T.describe("models.default", function()
  T.it("returns the configured default slot", function()
    T.eq(models.default(), { endpoint = "http://base:1234/v1", model = "base-model" })
  end)
end)

T.describe("models.effective", function()
  T.it("falls back to the default for an unregistered slot", function()
    T.eq(models.effective("does-not-exist"), { endpoint = "http://base:1234/v1", model = "base-model" })
  end)

  T.it("uses a slot's own endpoint and model when set", function()
    models.register({
      name = "fim",
      endpoint = function() return "http://fim:5000/v1" end,
      get = function() return "coder-model" end,
    })
    T.eq(models.effective("fim"), { endpoint = "http://fim:5000/v1", model = "coder-model" })
  end)

  T.it("falls back per-field when the slot leaves one unset", function()
    models.register({
      name = "chat",
      endpoint = function() return nil end, -- inherit default endpoint
      get = function() return "chat-model" end, -- but override the model
    })
    T.eq(models.effective("chat"), { endpoint = "http://base:1234/v1", model = "chat-model" })
  end)

  T.it("treats an empty-string override as unset", function()
    models.register({
      name = "blank",
      endpoint = function() return "" end,
      get = function() return "" end,
    })
    T.eq(models.effective("blank"), { endpoint = "http://base:1234/v1", model = "base-model" })
  end)
end)

T.describe("models.register / slot_names", function()
  T.it("records registration order and de-dupes a re-register", function()
    local before = #models.slot_names()
    models.register({ name = "slot_a", get = function() return "a" end })
    models.register({ name = "slot_b", get = function() return "b" end })
    models.register({ name = "slot_a", get = function() return "a2" end }) -- replace, not re-add
    local names = models.slot_names()
    T.eq(#names, before + 2)
    T.eq(models.effective("slot_a").model, "a2") -- latest definition wins
  end)

  T.it("ignores an invalid slot (no name)", function()
    local before = #models.slot_names()
    models.register({ get = function() return "x" end })
    T.eq(#models.slot_names(), before)
  end)
end)
