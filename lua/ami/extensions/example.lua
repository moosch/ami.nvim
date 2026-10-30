-- ami.extensions.example: a minimal reference extension.
--
-- It is NOT registered by default. Copy it as a starting point, or register it to
-- try the system:  require("ami").setup({ extensions = { require("ami.extensions.example") } })
--
-- All it does is log each chat turn and expose :AmiExamplePing. See
-- docs/extensions.md for the full API + event reference.
return {
  name = "example",

  -- Defaults for this extension, exposed to the user as config.options.example
  -- and to setup() as api.config. User overrides (ami.setup({ example = {...} }))
  -- win over these.
  config = {
    enabled = true,
  },

  -- Declarative command registration (sugar for api.command in setup()).
  commands = {
    AmiExamplePing = {
      desc = "ami example extension: log a ping",
      fn = function()
        require("ami.log").info("example: ping")
        vim.notify("ami example: pong", vim.log.levels.INFO)
      end,
    },
  },

  -- Declarative event hooks (sugar for api.on in setup()).
  events = {
    chat_turn_pre = function(req)
      require("ami.log").debug(("example: chat turn (session=%s, %d chars)")
        :format(tostring(req.session_id), #tostring(req.message or "")))
    end,
  },

  setup = function(api)
    api.log.debug("example: setup (enabled=" .. tostring(api.config.enabled) .. ")")
  end,
}
