# Writing ami extensions

ami's core is deliberately small. Optional capabilities are **extensions**:
self-contained Lua tables that hook into the agent's lifecycle through a stable
API, instead of reaching into core internals. An extension can live in this repo
or — more usefully — in its own Neovim plugin repo that returns a spec.

ami core is a runtime; every feature is an extension. Reference extensions, each in
its own repo:
[`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim) (the chat panel + tree —
provides the `chat` capability and a model slot),
[`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) (inline/FIM
completion — a model slot),
[`ami-proactive.nvim`](https://github.com/moosch/ami-proactive.nvim)
(proactive suggestions — events, commands, daemon calls, a model slot), and
[`ami-chat-split.nvim`](https://github.com/moosch/ami-chat-split.nvim)
(a split-window chat UI — a full `chat_ui` provider). A tiny in-tree template
lives at `lua/ami/extensions/example.lua`.

## Registering an extension

Pass specs — or module names to `require()` — to `setup()`:

```lua
require("ami").setup({
  extensions = {
    require("ami-proactive"),   -- a spec table
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
| `api.emit(event, ...)` | emit a lifecycle event (e.g. a chat extension emits `chat_turn_pre/post`) |
| `api.command(name, spec)` | register a `:Name` command (`{desc,nargs,range,complete,fn}`) |
| `api.provide(cap, impl)` | offer a provider for a named capability (see below) |
| `api.resolve(cap)` | look up a capability provider (or nil) |
| `api.chat` | proxies the `chat` capability (from a chat extension; no-ops if none): `add_proactive`, `append`, `open`, `session()`, `model()`, `source()`, `set_source(buf,win)`, `is_streaming()` |
| `api.client` | `stream(path, body, cbs)`, `post_json(path, body, cb, opts)` — talk to the daemon |
| `api.context` | `gather_async(bufnr, win, selection, range, cb)`, `project_root(bufnr)` |
| `api.models` | `register(slot)`, `default()`, `effective(name)` — the model registry (below) |

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

## Capability providers (swappable UI)

`api.provide(cap, impl)` registers an implementation for a named capability;
core or another extension looks it up with `require("ami.extensions").resolve(cap)`.
This is how UI surfaces become swappable.

### `chat` — the chat panel itself

Chat is an extension ([`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim)): it
`provide`s the `chat` capability — a controller exposing `toggle`, `open`, `close`,
`append`, `add_proactive`, `session()`, `source()`, `set_source()`, `is_streaming()`
and more. Core's `api.chat` proxies to it, so other extensions (e.g. proactive)
reach the panel without depending on ami-chat directly; the calls are safe no-ops if
no chat extension is loaded.

### `chat_ui` — replace the chat panel

The chat **controller** (in `ami-chat.nvim`) owns the session, streaming, and events
but draws nothing itself: it drives whatever `chat_ui` provider is registered,
falling back to its bundled floating panel. Register your own to replace the panel
entirely — e.g. a sidebar split, a bottom dock, or a custom transcript:

```lua
setup = function(api)
  api.provide("chat_ui", my_renderer)
end
```

`my_renderer` must implement the full contract:

| Method | Contract |
| --- | --- |
| `open(ctl)` | show the full interactive panel and focus the input. `ctl = { submit, new_session, close }` — wire these to your keymaps |
| `show()` | ensure the transcript is visible **without** stealing focus |
| `close()` | hide the panel; **must preserve** the transcript contents and any draft |
| `is_open()` | `true` if the panel (transcript or input) is currently visible |
| `owns_buf(bufnr)` | `true` if `bufnr` is one of the panel's own buffers (so the controller won't treat it as the source file) |
| `append(text)` | append text (may contain `\n`) to the transcript; pin to the bottom; must work even when hidden |
| `clear()` | empty the transcript |
| `set_status(text)` | show a transient status line; `set_status(nil)` clears it |
| `read_input()` | return the current draft text |
| `clear_input()` | clear the draft |

Implement every method — the controller assumes the whole contract and does not
mix a custom renderer with the bundled one (they wouldn't share buffers). Use
ami-chat's bundled `lua/ami-chat/ui.lua` (floating panel) as the reference, or
[`ami-chat-split.nvim`](https://github.com/moosch/ami-chat-split.nvim) for a
split-window `chat_ui` packaged as its own repo.

## Model registry

Core owns a single **default** model slot (`config.model` = base provider + model).
Any feature that uses a model registers its own **slot** via `api.models.register`;
a slot that leaves its model unset falls back to the default. The `:AmiModel`
selector lists every registered slot, so your extension's model becomes selectable
automatically.

```lua
setup = function(api)
  api.models.register({
    name = "fim",                 -- unique; shown in :AmiModel
    label = "Inline (FIM)",       -- optional display label
    endpoint = function() return api.config.endpoint end,  -- nil ⇒ default provider
    get      = function() return api.config.model end,     -- nil ⇒ default model
    set      = function(m) api.config.model = m end,       -- persist the pick
  })
end
```

- `api.models.default()` → the default slot `{ endpoint, model }`.
- `api.models.effective(name)` → a slot's resolved `{ endpoint, model }` (its
  overrides, else the default). Use this when you actually make a request, so you
  honour both the user's per-slot pick and the default fallback.

`ami-inline.nvim` is the reference: it registers a `fim` slot and resolves its
provider with `api.models.effective("fim")` on each completion.

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

1. **Persona / prompt-injection** (e.g. "respond to me tersely", a house style).
   Doable via `chat_turn_pre` once the daemon accepts an optional `instructions`
   field and merges it into the system prompt (`internal/prompt/system.go`).
2. **Context-provider extensions** via `context_assembled`: git diff/blame,
   test/build output, LSP diagnostics, a project-conventions file.
3. **Daemon-side provider protocol** (investigate): Go can't hot-load plugins, so
   likely an out-of-process HTTP protocol for context/prompt middleware.
4. **rtp auto-discovery** of installed extensions, and **project-local
   `.ami/extensions/`** loaded only after a trust prompt (Pi's project-trust model).

**Done:** core is now a pure runtime — chat (`ami-chat.nvim`), inline
(`ami-inline.nvim`), and proactive are all extensions; the `chat`/`chat_ui`
capabilities (swappable panel), the model registry + generic selector, and the
packaging convention (`ami-*.nvim` repos exposing a spec).
