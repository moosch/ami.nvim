# Tests

Headless spec suite for ami's pure-Lua core. **No plenary, no busted, no LM
Studio** — just Neovim, so CI needs nothing else.

```sh
make test          # from the repo root
# or directly:
nvim --clean --headless -l tests/run.lua
```

Exits non-zero if any case fails (CI runs it on every push / PR). Output is TAP-ish:

```
ok 3 - context.assemble › wraps the active file in a fenced section …
not ok 7 - …                 # with the failure message indented beneath
# 43 passed, 0 failed, 43 total
```

## Layout

- `minitest.lua` — a tiny framework: `describe` / `it` and assertions
  (`eq` deep-compare, `ok`, `falsy`, `contains`, `excludes`, `raises`).
- `run.lua` — puts `lua/` and the repo root on `package.path`, loads every
  `*_spec.lua`, runs them, and quits with `:cquit 1` on failure.
- `*_spec.lua` — one per core module:
  - `events_spec` — pub/sub: on/emit, unsubscribe, order, pcall isolation, `emit_collect`.
  - `context_spec` — `estimate_tokens` + `assemble` (section order, fences, relative
    paths, the `context.extra` collector, budget trimming).
  - `models_spec` — the model registry: default slot, `effective()` fallback, dedupe.
  - `extensions_spec` — the registry + the `api` facade (config merge, commands,
    events, provide/resolve, `emit_collect`, health, the chat no-op proxy), setup
    isolation, `_reset`.

These cover the **in-editor logic** (no network). The chat/history/inline/proactive
extensions live in their own repos; their live behaviour is exercised against a
running LM Studio by hand (and the gif demos).

## Adding a spec

Drop a `tests/<name>_spec.lua` that `require("tests.minitest")`, declares cases, and
lets the runner pick it up — no registration needed. Reset shared module state at
the top of a case where it matters (`require("ami.extensions")._reset()`,
`require("ami.events").clear()`).
