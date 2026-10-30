# ami

*ami — "friend" in French.* A pair programmer that sits with you, not ahead of you.

> ⚠️ **Status: early / experimental (v0.11.0).** It works day to day but hasn't been
> widely battle-tested — expect sharp edges, and pin a commit if you depend on it.
> Feedback and issues welcome.

An IDE-resident AI pair programmer for Neovim — **advisor, not actor**. It
discusses problems, surfaces trade-offs, completes code inline, and offers the
occasional proactive suggestion, but it **never edits your files**. Built to keep
you in control and in practice, backed entirely by local models via
[LM Studio](https://lmstudio.ai/).

It's **pure Lua** — no daemon, no build step. ami talks to LM Studio directly over
the OpenAI-compatible API (via `curl`), so it's model-agnostic. The core is a small
runtime; every feature is an extension.

## Features

- **Chat advisor panel** — a floating transcript + prompt. Discuss your thinking
  and get streamed, advice-only feedback grounded in your open file, selection,
  `README.md`/`PLAN.md`, and — via LSP — the files your code depends on. Plus a
  **branching history tree** (branch/switch/summarize). Ships as the
  [`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim) extension; its panel is
  swappable (e.g. a split layout via
  [`ami-chat-split.nvim`](https://github.com/moosch/ami-chat-split.nvim)).
- **Inline completion** — native Copilot-style FIM ghost text, manual by default
  (or debounced auto). Accept/dismiss; nothing is written until you accept. Ships
  as the [`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) extension.
- **A small pure-Lua runtime core** with a lifecycle + capability + model-registry
  API, so every feature is a self-contained extension (in your config or its own
  repo). Core is just the LLM client, context engine, model registry, event bus, and
  extension system; chat, inline, and proactive suggestions are first-party
  extensions. History (the branching tree) is its own extension too.
- **Runtime model registry** — a default model every feature inherits; each feature
  is a *slot* you can point at any model LM Studio has loaded, via `:AmiModel`.

## Requirements

- Neovim ≥ 0.10 (`vim.system`, `vim.uv`, `vim.fs.root`)
- `curl` on `PATH`
- [LM Studio](https://lmstudio.ai/) (or any OpenAI-compatible server) with a
  model loaded — a FIM-capable code model (Qwen Coder, DeepSeek-Coder,
  StarCoder2, CodeLlama) is recommended for inline completion
- Linux and macOS. Windows is untested but no longer architecturally excluded
  (pure Lua + `curl`); reports welcome.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

ami core is a runtime; install the feature extensions you want alongside it:

```lua
{
  "moosch/ami.nvim",            -- pure Lua, no build step
  dependencies = {
    "moosch/ami-chat.nvim",              -- chat advisor panel
    "moosch/ami-history.nvim",           -- branching history tree (multi-turn + :AmiTree)
    "moosch/ami-inline.nvim",            -- inline (FIM) completion
    -- "moosch/ami-chat-split.nvim",        -- optional: split-window chat UI
    -- "moosch/ami-proactive.nvim",         -- optional: proactive suggestions
  },
  config = function()
    require("ami").setup({
      -- point ami at your LM Studio if it isn't on localhost:
      -- model = { endpoint = "http://localhost:1234/v1", model = "qwen3-coder" },
      extensions = {
        require("ami-chat"),
        require("ami-history"),
        require("ami-inline"),
      },
    })
  end,
}
```

No build step — ami is pure Lua. Without any feature extensions, core alone is just
the model registry + runtime; install `ami-chat.nvim` for the chat panel and
`ami-history.nvim` for persistent, branchable multi-turn history.

## Quick start

1. Start LM Studio and load a model (defaults assume `http://localhost:1234/v1`).
2. Open a project in Neovim.
3. `:AmiChat`, type a question, `<Esc>` then `<Enter>` to send.
4. In insert mode, `<C-g>` requests an inline completion; `<Tab>` accepts it.
5. `:checkhealth ami` if anything looks off.

## Demos

These are **examples of core + the first-party extensions working together** — each
demo uses the extension linked beside it (installed in `demos/init.lua`), not core
alone.

Inline, comment-driven completion — write a comment, trigger, accept
([`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim)):

![inline completion demo](demos/inline.gif)

Chat advisor — discuss a problem, get advice-only feedback
([`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim)):

![chat advisor demo](demos/chat.gif)

Runtime model registry — pick the model for any slot
(core `:AmiModel`; the `chat`/`fim` slots come from
[`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim) /
[`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim)):

![model selector demo](demos/model.gif)

> These GIFs are rendered from [VHS](https://github.com/charmbracelet/vhs) tapes in
> `demos/`, which load core plus the extensions above via `demos/init.lua`.
> Regenerate them with `make demos` (needs `vhs`, a running LM Studio, and the
> extension repos checked out next to this one; set `AMI_ENDPOINT` for a
> non-localhost server). Tune the `Sleep` lines in each `.tape` to your model's
> latency.

## Commands

Core itself provides only a few commands; features add their own.

| Command | What it does | From |
| --- | --- | --- |
| `:AmiModel [slot]` | Pick a model for a registered slot (no arg = choose which) | core |
| `:AmiModels` | Show each model slot's current model | core |
| `:AmiExtensions` | List the loaded extensions | core |
| `:AmiHealth` / `:AmiLog` / `:AmiDebug` | Health check / log viewer / verbose logging | core |
| `:AmiChat` | Toggle the chat panel (`<CR>` normal = send, `<C-n>` new, `q`/`<Esc>` hide) | ami-chat |
| `:AmiAsk {text}` | One-shot question; visual mode sends the selection + its deps | ami-chat |
| `:AmiNewSession [name]` | Start a fresh conversation | ami-chat |
| `:AmiTree` | Conversation tree — branch/switch/summarize | ami-history |
| `:AmiComplete` / `:AmiInlineAuto` | Request a completion / toggle auto-trigger | ami-inline |
| `:AmiProactive` / `:AmiNudge` | Toggle proactive / request a suggestion now | ami-proactive |

Inline keys (from `ami-inline`, configurable): `<C-g>` request, `<Tab>` accept
(falls back to a real Tab when none shown), `<C-]>` dismiss. **Comment-driven
completion** works like the original Copilot — write a comment, put the cursor on
the line below, and trigger; the comment is the FIM prefix and code after the cursor
is the suffix, so it fills in context-aware.

## Configuration

Defaults shown; pass overrides to `setup()`:

```lua
require("ami").setup({
  -- Default model slot: the base OpenAI-compatible provider + model that every
  -- model slot (chat, and any extension's) falls back to. ami talks to this
  -- provider directly. Pick per slot live with :AmiModel.
  model = { endpoint = "http://localhost:1234/v1", model = "qwen3-coder" },
  context = {
    lsp_deps = true, dep_max_files = 5, dep_timeout_ms = 1500, dep_max_positions = 30,
    token_budget = 8000,           -- max tokens of assembled context sent per turn
  },
  -- Features live in extensions (their own repos); each registers its own config,
  -- commands, and model slot. Their options go under their own key, e.g.:
  extensions = { require("ami-chat"), require("ami-history"), require("ami-inline") },
  -- chat   = { ui = { position = "right", opacity = 0.8, ... } },  -- ami-chat
  -- inline = { auto = true, model = "deepseek-coder-6.7b-instruct" }, -- ami-inline
})
```

**Models are a registry.** Core owns the default `model` slot; every feature — chat,
inline, proactive — registers a *slot* that overrides it or inherits it. `:AmiModel`
lists every registered slot (`default`, plus `chat`/`fim`/`proactive` as their
extensions load) and lets you pick a model for one from that slot's provider;
`:AmiModels` shows the current picks. An extension's own options live under its key
(e.g. `chat = { ui = ... }`, `inline = { ... }`) — see each extension's README.

## Where history is stored

Conversation history (the branching tree + multi-turn context) is the
[`ami-history.nvim`](https://github.com/moosch/ami-history.nvim) extension — install
it to get persistent, branchable history and `:AmiTree`. It saves under
`stdpath("data")/ami/<project>/sessions/` by default, **outside your repositories**;
see its README for options. Without it, chat still works but history is in-memory
for the current session only.

## Extensions

ami core is a **runtime**; every feature is an **extension** — a self-contained Lua
spec that hooks the lifecycle (`context_assembled`, `chat_turn_pre/post`,
`buf_write`, …), registers commands, a **model slot**, a **capability** (like `chat`
itself), or a **UI surface** (like the chat panel), all through a stable API rather
than core internals. Register them in `setup()`:

```lua
require("ami").setup({
  extensions = {
    require("ami-chat"),               -- a spec table
    "my-org.ami-notes",                -- or a module name to require()
  },
  -- disable_extensions = { "inline" },
})
```

ami ships **no active extensions** itself. First-party ones, each in their own repo:

- [`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim) — the chat advisor
  panel; provides the `chat` capability and a `chat` model slot.
- [`ami-history.nvim`](https://github.com/moosch/ami-history.nvim) — the branching
  history tree + persistence + `:AmiTree`; provides the `history` capability
  (prior-turn context) by listening to the chat events.
- [`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) — inline (FIM)
  completion; registers a `fim` model slot.
- [`ami-proactive.nvim`](https://github.com/moosch/ami-proactive.nvim) —
  proactive suggestions; registers a `proactive` model slot.
- [`ami-chat-split.nvim`](https://github.com/moosch/ami-chat-split.nvim) — a
  split-window chat UI (a `chat_ui` provider that replaces ami-chat's panel).

`:AmiExtensions` lists what's loaded. Writing your own (including publishing it as
its own `ami-*.nvim` repo) is documented in
[`docs/extensions.md`](docs/extensions.md), with the full API, events, the model
registry, the `chat`/`chat_ui` contracts, and the roadmap.

## How it works

```
Neovim (Lua) ──curl (HTTP + SSE)──▶ LM Studio
  ami core: LLM client, context assembly, model registry, event bus, extensions
  extensions: chat (builds the request + streams), history, inline, proactive
```

ami talks to LM Studio **directly** over the OpenAI-compatible API — no daemon, no
separate process, no build step. The chat extension assembles each request (system
prompt + context + prior turns from the history provider + your message) and streams
the reply straight from the model.

## Development

Pure Lua — nothing to build.

```sh
make check   # verify VERSION == README badge
make demos   # render the README demo GIFs (needs vhs + LM Studio)
```

The plugin lives in `lua/ami` (core runtime) plus the first-party extension repos.
CI runs the version check.

## License

[MIT](LICENSE)
