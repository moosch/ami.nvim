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

## 2. `@file` references in chat input — *done*

Type `@path/to/file` to pull a specific file into the request context, with a
file-completion popup reusing the `/` machinery.

- [x] core: `assemble` reads `refs.explicit_paths` → "Referenced file" sections,
      ranked above auto-resolved deps, de-duped against active/deps.
- [x] controller: `_resolve_refs` (parse `@tokens`, sandbox to project root, skip
      non-files/prose), `file_list` (cached, ignore-pruned walk), "attached" note.
- [x] ui: `@` trigger + `_complete` serves files as well as commands.
- Possible later: fuzzy/substring matching (native pum filters by prefix), and an
  opt-in to reference files *outside* the project root.

Repos: `ami.nvim` (core), `ami-chat.nvim`.

## 3. Bridge advisor → action (user-initiated, keeps "advise, don't act") — *done*

The advisor never writes — good. These let the user act on a snippet, always as the
one who commits the change:

- [x] `/yank [N]` (and `:AmiYank`): copy the Nth fenced code block to the clipboard.
- [x] `/apply [N] [path]` (and `:AmiApply`): open the block in a diff against a file
      (chat source by default, or a sandboxed `path`); user merges with `do`/`dp` and
      `:w` — ami writes nothing.
- [x] optional `transcript_lines()` on the `chat_ui` contract so the controller can
      read code blocks back out of the transcript.

Both are user-triggered, so the guarantee holds (same shape as `!shell` / ami-doc).
Possible later: apply a ```diff/patch block directly via `git apply` (confirm-gated).

Repos: `ami-chat.nvim`.

## 4. Extend the test suite to the extensions' pure functions

The headless harness (ai-harness/tests) covers core only. Juicy untested pure
functions: `ami-chat.ui._recall` (up/down state machine), `controller.parse_command`,
and especially **`ami-doc.resolve_path`** — it's a security boundary (the project-root
sandbox) and deserves regression coverage — plus `strip_outer_fence`.

Repos: `ami-chat.nvim`, `ami-doc.nvim` (per-repo `tests/` + a `make test`).

## 5. Context-budget indicator — *done*

Shows what's being compacted: a running estimate of the request size.

- [x] header indicator in the panel title (`~3.2k`, or `~3.2k/32k` with
      `chat.context_window` set), updated each turn.
- [x] `/tokens` prints a breakdown (instructions / context / history / message /
      total) — history flagged as what `/compact` reduces.
- [x] optional `set_tokens(total, window?)` on the `chat_ui` contract.

Repos: `ami-chat.nvim`.

## 6. Diagnostics-aware context / `/fix`

A `/fix` command (or auto-including the current buffer's LSP diagnostics via the
`context.extra` collector) turns "why is this erroring" into one keystroke. Fits the
collector-hook model; could be its own `ami-context-lsp.nvim` mirroring
`ami-context-git.nvim`.

Repos: new `ami-context-lsp.nvim`, or `ami-chat.nvim`.
