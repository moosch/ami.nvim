# ami

*ami — "friend" in French.* A pair programmer that sits with you, not ahead of you.

> ⚠️ **Status: early / experimental (v0.10.0).** It works and is covered by tests,
> but it hasn't been battle-tested in day-to-day interactive use — expect sharp
> edges, and pin a commit if you depend on it. Feedback and issues welcome.

An IDE-resident AI pair programmer for Neovim — **advisor, not actor**. It
discusses problems, surfaces trade-offs, completes code inline, and offers the
occasional proactive suggestion, but it **never edits your files**. Built to keep
you in control and in practice, backed entirely by local models via
[LM Studio](https://lmstudio.ai/).

It's a Lua plugin plus a small Go daemon (`amid`). The daemon holds the
intelligence (context assembly, history, LLM proxying, streaming); Neovim stays a
thin client. Everything speaks the OpenAI-compatible API, so it's model-agnostic.

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
- **A small runtime core** with a lifecycle + capability + model-registry API, so
  every feature is a self-contained extension (in your config or its own repo).
  Core is just the daemon, context engine, model registry, and extension system;
  chat, inline, and proactive suggestions are first-party extensions.
- **Runtime model registry** — a default model every feature inherits; each feature
  is a *slot* you can point at any model LM Studio has loaded, via `:AmiModel`.
- **Managed daemon** — started/stopped with Neovim, reference-counted so it's
  shared across instances and stops only when the last one exits.

## Requirements

- Neovim ≥ 0.10 (`vim.system`, `vim.uv`, `vim.fs.root`)
- Go (to build the daemon; auto-built on first run if present)
- `curl` on `PATH`
- [LM Studio](https://lmstudio.ai/) (or any OpenAI-compatible server) with a
  model loaded — a FIM-capable code model (Qwen Coder, DeepSeek-Coder,
  StarCoder2, CodeLlama) is recommended for inline completion
- **Linux** (developed on macOS too; **Windows is not supported** — the daemon is
  launched via `sh` and everything shells out to `curl`)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

ami core is a runtime; install the feature extensions you want alongside it:

```lua
{
  "moosch/ami.nvim",
  build = "make build",        -- compiles the Go daemon (amid)
  dependencies = {
    "moosch/ami-chat.nvim",              -- chat advisor panel + history tree
    "moosch/ami-inline.nvim",            -- inline (FIM) completion
    -- "moosch/ami-chat-split.nvim",        -- optional: split-window chat UI
    -- "moosch/ami-proactive.nvim",  -- optional: proactive suggestions
  },
  config = function()
    require("ami").setup({
      -- point the daemon at your LM Studio if it isn't on localhost:
      -- model = { endpoint = "http://localhost:1234/v1", model = "qwen3-coder" },
      extensions = {
        require("ami-chat"),
        require("ami-inline"),
      },
    })
  end,
}
```

The `build` step compiles `amid`. If you skip it, the plugin auto-builds the
binary on first run when `go` is available. Without any feature extensions, core
alone just manages the daemon and model registry — install `ami-chat.nvim` for the
chat panel.

## Quick start

1. Start LM Studio and load a model (defaults assume `http://localhost:1234/v1`).
2. Open a project in Neovim — `amid` starts automatically.
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
| `:AmiDaemon [start\|stop\|restart]` | Control the managed daemon | core |
| `:AmiHealth` / `:AmiLog` / `:AmiDebug` | Status / log viewer / verbose logging | core |
| `:AmiChat` | Toggle the chat panel (`<CR>` normal = send, `<C-n>` new, `q`/`<Esc>` hide) | ami-chat |
| `:AmiAsk {text}` | One-shot question; visual mode sends the selection + its deps | ami-chat |
| `:AmiNewSession [name]` | Start a fresh conversation | ami-chat |
| `:AmiTree` | Conversation tree — branch/switch/summarize | ami-chat |
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
  daemon_url = "http://127.0.0.1:8787",
  -- Default model slot: the base OpenAI-compatible provider + model that every
  -- model slot (chat, and any extension's) falls back to. Pick per slot live
  -- with :AmiModel.
  model = { endpoint = "http://localhost:1234/v1", model = "qwen3-coder" },
  session_dir = nil,               -- nil = stdpath("data")/ami (out of your repos)
                                   --  "" = each project's ./.ami/sessions
  daemon = { auto_start = true, auto_build = true, bin = nil },
  context = { lsp_deps = true, dep_max_files = 5, dep_timeout_ms = 1500, dep_max_positions = 30 },
  -- Features live in extensions (their own repos); each registers its own config,
  -- commands, and model slot. Their options go under their own key, e.g.:
  extensions = { require("ami-chat"), require("ami-inline") },
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

The daemon also reads these environment variables (the plugin sets them from the
config above — `AMI_LMSTUDIO_URL`/`AMI_CHAT_MODEL` come from the effective chat
model): `AMI_ADDR`, `AMI_LMSTUDIO_URL`, `AMI_CHAT_MODEL`, `AMI_CONTEXT_BUDGET`,
`AMI_DATA_DIR`.

## Where history is stored

Conversation history is a branching tree saved under `session_dir`, which
defaults to `stdpath("data")/ami/<project>/sessions/` — **outside your
repositories**, so nothing leaks into your working tree. Set `session_dir = ""`
to instead keep it in each project's own `.ami/sessions/` (add `.ami/` to
your global gitignore if you do).

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
  panel + history tree; provides the `chat` capability and a `chat` model slot.
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
Neovim (Lua)  ──HTTP+SSE──▶  amid (Go)  ──OpenAI-compatible──▶  LM Studio
 chat UI, inline,             context, history,                     local models
 events, context  ◀────────  tree, LLM proxy  ◀──────────────────
```

Inline completion talks to LM Studio **directly** (not through the daemon) to
keep latency low. The daemon is reference-counted across Neovim instances via a
registry under `stdpath("state")/ami/`, so one `amid` is shared and only
stopped when the last instance exits.

## Development

```sh
make build   # build bin/amid
make test    # go test ./...
make run     # run the daemon in the foreground
```

The Go daemon lives in `cmd/amid` + `internal/`; the plugin in `lua/ami`.
CI runs `go vet` / `go test` / `go build`.

## License

[MIT](LICENSE)
