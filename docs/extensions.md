# Writing ami extensions

ami's core is deliberately small. Optional capabilities are **extensions**:
self-contained Lua tables that hook into the agent's lifecycle through a stable
API, instead of reaching into core internals. An extension can live in this repo
or — more usefully — in its own Neovim plugin repo that returns a spec.

The reference extension is [`ami-custom-proactive.nvim`](https://github.com/moosch/ami-custom-proactive.nvim)
(proactive suggestions). A tiny in-tree template lives at
`lua/ami/extensions/example.lua`.

## Registering an extension

Pass specs — or module names to `require()` — to `setup()`:

```lua
require("ami").setup({
  extensions = {
    require("ami-custom-proactive"),   -- a spec table
    "my-org.ami-notes",                -- or a module name ami will require()
  },
  -- Skip a specific extension by name:
  -- disable_extensions = { "proactive" },
})
```

An extension installed as its own plugin just needs to be on the runtimepath
(your plugin manager handles that) so `require` resolves it. ami ships **no active
extensions** of its own.

- `:AmiExtensions` lists what's loaded.

## The spec

```lua
return {
  name = "proactive",                  -- required, unique; namespaces config + shown in :AmiExtensions
  config = { enabled = false, ... },   -- defaults, merged UNDER the user's config (user wins)
  commands = {                         -- user commands, registered at setup
    AmiProactive = { desc = "...", fn = function(opts) ... end,
                     nargs = "?", range = false, complete = nil },
  },
  events = {                           -- lifecycle hooks (sugar for api.on in setup)
    buf_write = function(bufnr) ... end,
  },
  setup = function(api) ... end,       -- called once, after config is merged
}
```

User config for an extension lives under its `name`
(`require("ami").setup({ proactive = { enabled = true } })`) and is exposed to
`setup` as `api.config`. The user's values always win over the spec's `config`.

## The API (`api` passed to `setup`)

| Field | What it does |
| --- | --- |
| `api.name` | this extension's name |
| `api.config` | this extension's merged config table (`config.options[name]`) |
| `api.log` | ami's logger (`.debug/.info/.warn/.error`) |
| `api.notify(msg, level?)` | `vim.notify` prefixed with `ami:` |
| `api.on(event, fn)` | subscribe to a lifecycle event; returns an unsubscribe fn |
| `api.command(name, spec)` | register a `:Name` command (`{desc,nargs,range,complete,fn}`) |
| `api.provide(cap, impl)` | offer a provider for a named capability (see below) |
| `api.chat` | `add_proactive`, `append`, `open`, `session()`, `model()`, `source()`, `set_source(buf,win)`, `is_streaming()` |
| `api.client` | `stream(path, body, cbs)`, `post_json(path, body, cb, opts)` — talk to the daemon |
| `api.context` | `gather_async(bufnr, win, selection, range, cb)`, `project_root(bufnr)` |

## Lifecycle events

| Event | Payload | When |
| --- | --- | --- |
| `setup` | — | after `ami.setup()` finishes |
| `context_assembled` | `(ctx, meta)` | context ready (chat **and** proactive); handlers may **mutate `ctx`** (add `dep_paths`, notes, …) |
| `chat_turn_pre` | `(req)` | before a chat turn streams; handlers may **mutate `req`** (`{session_id, message, model, context}`) |
| `chat_turn_post` | `(res)` | after a turn finishes/errors (`{ok, session_id, error?}`) |
| `buf_write` | `(bufnr)` | a buffer was written (`BufWritePost`) |

Handlers run in registration order, each under `pcall` — a throwing handler is
logged and the rest still run.

## Capability providers (UI and beyond)

`api.provide(cap, impl)` registers an implementation for a named capability;
core or another extension looks it up with `require("ami.extensions").resolve(cap)`.
This is how UI surfaces become swappable. `"chat_ui"` is **reserved** as the first
UI capability (see the roadmap) — the mechanism ships now; routing the chat panel
through it is the next step.

## Publishing as its own repo

Structure it like any Neovim plugin:

```
your-ami-ext.nvim/
  lua/your-ami-ext/init.lua   -- returns the spec
  README.md
  LICENSE
```

Users install it with their plugin manager and add `require("your-ami-ext")` to
`extensions`. Reach ami only through `api.*` (and, if needed, the daemon via
`api.client`) so you don't couple to internals. By convention, name the repo
`ami-*.nvim`.

---

## Roadmap / candidate extensions

Tracked here until done. PRs/ideas welcome.

1. **Chat UI as a swappable `chat_ui` renderer** — the flagship UI extension.
   Define the renderer interface (`open`/`close`/`append`/`render_nodes`/
   `add_proactive`/`status`) and route `ami.chat` through `resolve("chat_ui")`,
   falling back to the built-in floating panel. Would let an extension replace the
   panel's layout entirely (e.g. a sidebar split).
2. **Inline completion** as an extension.
3. **Model selector** as an extension.
4. **Persona / prompt-injection** (e.g. "respond to me tersely", a house style).
   Doable via `chat_turn_pre` once the daemon accepts an optional `instructions`
   field and merges it into the system prompt (`internal/prompt/system.go`).
5. **Context-provider extensions** via `context_assembled`: git diff/blame,
   test/build output, LSP diagnostics, a project-conventions file.
6. **Daemon-side provider protocol** (investigate): Go can't hot-load plugins, so
   likely an out-of-process HTTP protocol for context/prompt middleware.
7. **rtp auto-discovery** of installed extensions, and **project-local
   `.ami/extensions/`** loaded only after a trust prompt (Pi's project-trust model).
8. **Packaging convention**: extensions as their own `ami-*.nvim` repos exposing a
   spec (proven by `ami-custom-proactive.nvim`).
