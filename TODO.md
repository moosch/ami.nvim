# ami — improvement backlog

Ideas worth doing, roughly in bang-for-buck order. Each is self-contained; pick
one at a time. Spans several repos (`ami.nvim`, `ami-chat.nvim`, `ami-doc.nvim`, …) —
noted per item.

## 1. Interrupt / cancel a streaming reply — *in progress*

Stop an in-flight reply mid-stream (wrong model, typo, runaway length).

- [x] chat: `:AmiStop`, `<C-c>` (normal + insert), `M.cancel()` kills the request,
      renders `_[stopped]_`. (already present)
- [ ] **generic cancel registry on the chat capability** so any producer streaming
      into the panel can be stopped by the same `<C-c>` / `:AmiStop`.
- [ ] **ami-doc**: register its in-flight stream so `/doc` is cancellable; on cancel,
      fold the partial stream away and *don't* write the file.

Repos: `ami-chat.nvim`, `ami-doc.nvim`.

## 2. `@file` references in chat input

Type `@path/to/file` to pull a specific file into the request context. Reuses the
`/` completion-popup machinery (swap the source from commands to a project-root
file walker). The natural third member alongside `/command` and `!shell`.

Repos: `ami-chat.nvim` (+ a `context.extra` style seam in core if needed).

## 3. Bridge advisor → action (user-initiated, keeps "advise, don't act")

The advisor never writes — good. But the user often wants the output:
- `/yank` (or a keymap) to copy the Nth fenced code block from the transcript.
- A confirm-gated "apply this suggestion as a diff" preview.

Both are user-triggered, so the guarantee holds (same shape as `!shell` / ami-doc).

Repos: `ami-chat.nvim`.

## 4. Extend the test suite to the extensions' pure functions

The headless harness (ai-harness/tests) covers core only. Juicy untested pure
functions: `ami-chat.ui._recall` (up/down state machine), `controller.parse_command`,
and especially **`ami-doc.resolve_path`** — it's a security boundary (the project-root
sandbox) and deserves regression coverage — plus `strip_outer_fence`.

Repos: `ami-chat.nvim`, `ami-doc.nvim` (per-repo `tests/` + a `make test`).

## 5. Context-budget indicator

Now that `/compact` exists, show what's being compacted: an approximate token count
in the chat header (`~3.2k / 8k`). `context.estimate_tokens` already exists; mostly
plumbing it to the window title.

Repos: `ami-chat.nvim` (+ expose `estimate_tokens` via `api.context` if not already).

## 6. Diagnostics-aware context / `/fix`

A `/fix` command (or auto-including the current buffer's LSP diagnostics via the
`context.extra` collector) turns "why is this erroring" into one keystroke. Fits the
collector-hook model; could be its own `ami-context-lsp.nvim` mirroring
`ami-context-git.nvim`.

Repos: new `ami-context-lsp.nvim`, or `ami-chat.nvim`.
