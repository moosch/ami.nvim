# ami

*ami — "friend" in French.* A pair programmer that sits with you, not ahead of you.

> ⚠️ **Status: early / experimental (v0.7.0).** It works and is covered by tests,
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
  `README.md`/`PLAN.md`, and — via LSP — the files your code depends on.
- **Inline completion** — native Copilot-style FIM ghost text, manual by default
  (or debounced auto). Accept/dismiss; nothing is written until you accept. Ships
  as the [`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) extension.
- **Branching history tree** — every message is a node; branch from any point and
  switch between branches. Summarize an old branch to shrink context
  non-destructively.
- **Extensions** — a small core with a lifecycle + capability + model-registry API,
  so optional features live as self-contained extensions (in your config or their
  own repo). Inline completion and proactive suggestions are the reference ones
  ([`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim),
  [`ami-custom-proactive.nvim`](https://github.com/moosch/ami-custom-proactive.nvim)).
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

```lua
{
  "moosch/ami.nvim",
  build = "make build",        -- compiles the Go daemon (amid)
  dependencies = {
    "moosch/ami-inline.nvim",          -- inline (FIM) completion (optional)
    -- "moosch/ami-custom-proactive.nvim", -- proactive suggestions (optional)
  },
  config = function()
    require("ami").setup({
      -- point the daemon at your LM Studio if it isn't on localhost:
      -- model = { endpoint = "http://localhost:1234/v1", model = "qwen3-coder" },
      extensions = { require("ami-inline") },
    })
  end,
}
```

The `build` step compiles `amid`. If you skip it, the plugin auto-builds the
binary on first run when `go` is available.

## Quick start

1. Start LM Studio and load a model (defaults assume `http://localhost:1234/v1`).
2. Open a project in Neovim — `amid` starts automatically.
3. `:AmiChat`, type a question, `<Esc>` then `<Enter>` to send.
4. In insert mode, `<C-g>` requests an inline completion; `<Tab>` accepts it.
5. `:checkhealth ami` if anything looks off.

## Demos

Inline, comment-driven completion — write a comment, trigger, accept:

![inline completion demo](demos/inline.gif)

Chat advisor — discuss a problem, get advice-only feedback:

![chat advisor demo](demos/chat.gif)

Runtime model selector — swap chat/FIM models on the fly:

![model selector demo](demos/model.gif)

> These GIFs are rendered from [VHS](https://github.com/charmbracelet/vhs) tapes in
> `demos/`. Regenerate them with `make demos` (needs `vhs` and a running LM Studio;
> set `AMI_ENDPOINT` for a non-localhost server). Tune the `Sleep` lines in each
> `.tape` to match your model's latency.

## Commands

| Command | What it does |
| --- | --- |
| `:AmiChat` | Toggle the chat panel (prompt: `<CR>` normal-mode = send, `<C-n>` new session, `q`/`<Esc>` hide) |
| `:AmiAsk {text}` | One-shot question; visual mode sends the selection + its deps |
| `:AmiNewSession [name]` | Start a fresh conversation |
| `:AmiTree` | Conversation tree — branch/switch/summarize |
| `:AmiModel [slot]` | Pick a model for a registered slot (no arg = choose which) |
| `:AmiModels` | Show each model slot's current model |
| `:AmiExtensions` | List the loaded extensions |
| `:AmiDaemon [start\|stop\|restart]` | Control the managed daemon |
| `:AmiHealth` / `:AmiLog` / `:AmiDebug` | Status / log viewer / verbose logging |

Extensions add their own commands — e.g.
[`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) adds `:AmiComplete`
and `:AmiInlineAuto` (insert-mode keys, configurable: `<C-g>` request, `<Tab>`
accept, `<C-]>` dismiss), and
[`ami-custom-proactive.nvim`](https://github.com/moosch/ami-custom-proactive.nvim)
adds `:AmiProactive` and `:AmiNudge`.

**Comment-driven completion** works like the original Copilot: write a comment
describing what you want, put the cursor on the line below it, and press `<C-g>` —
the comment is part of the FIM prefix, so the model completes the function. (Code
*after* the cursor is sent as the FIM suffix too, so it fills in context-aware.)
Set `inline.auto = true` for debounced ghost text as you type instead of on
keypress.

## Configuration

Defaults shown; pass overrides to `setup()`:

```lua
require("ami").setup({
  daemon_url = "http://127.0.0.1:8787",
  -- Default model slot: the base OpenAI-compatible provider + model that every
  -- model slot (chat, and any extension's) falls back to. Pick per slot live
  -- with :AmiModel.
  model = { endpoint = "http://localhost:1234/v1", model = "qwen3-coder" },
  -- Chat/advisor provider. Omit endpoint/model to inherit the default `model`
  -- slot above; set them to point chat at a different provider/model.
  chat = {
    -- endpoint = "http://localhost:1234/v1",
    -- model = "qwen3-coder",
    ui = {
      position = "right",          -- "right" | "left" | "center"
      width = 0.4,                 -- fraction of columns (<=1) or absolute cols (>1)
      height = 0.9,                -- fraction of lines   (<=1) or absolute lines (>1)
      opacity = 0.8,               -- 0..1; lower = more see-through (via 'winblend')
      margin = 2,                  -- columns of gap from the screen edge
    },
  },
  session_dir = nil,               -- nil = stdpath("data")/ami (out of your repos)
                                   --  "" = each project's ./.ami/sessions
  daemon = { auto_start = true, auto_build = true, bin = nil },
  context = { lsp_deps = true, dep_max_files = 5, dep_timeout_ms = 1500, dep_max_positions = 30 },
  -- Optional capabilities live in extensions (their own repos); each registers its
  -- own config, commands, and model slot. See the Extensions section.
  extensions = {
    -- require("ami-inline"),           -- inline (FIM) completion
    -- require("ami-custom-proactive"), -- proactive suggestions
  },
})
```

**Models are a registry.** Core owns the default `model` slot; chat — and any
extension that uses a model — is a *slot* that either overrides it or inherits it.
`:AmiModel` lists every registered slot (`default`, `chat`, plus e.g. `fim` once
`ami-inline` is installed, `proactive` with `ami-custom-proactive`) and lets you
pick a model for one from that slot's provider; `:AmiModels` shows the current
picks. An extension's options live under its own key (e.g. `inline = { ... }`).

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

ami keeps a small core and moves optional features into **extensions** —
self-contained Lua specs that hook the lifecycle (`context_assembled`,
`chat_turn_pre/post`, `buf_write`, …), register commands, a **model slot**, or a
**UI surface** (like the chat panel), all through a stable API rather than core
internals. Register them in `setup()`:

```lua
require("ami").setup({
  extensions = {
    require("ami-inline"),             -- a spec table
    "my-org.ami-notes",                -- or a module name to require()
  },
  -- disable_extensions = { "inline" },
})
```

ami ships **no active extensions** itself. First-party ones, each in their own repo:

- [`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) — inline (FIM)
  completion; registers a `fim` model slot.
- [`ami-custom-proactive.nvim`](https://github.com/moosch/ami-custom-proactive.nvim) —
  proactive suggestions; registers a `proactive` model slot.
- [`ami-chat-split.nvim`](https://github.com/moosch/ami-chat-split.nvim) — a
  split-window chat UI (a `chat_ui` provider).

`:AmiExtensions` lists what's loaded. Writing your own (including publishing it as
its own `ami-*.nvim` repo) is documented in
[`docs/extensions.md`](docs/extensions.md), with the full API, events, the model
registry, the `chat_ui` contract, and the roadmap.

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
