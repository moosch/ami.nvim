# ami — improvement backlog

Working through these in order, one at a time.

- [x] **1. Streaming cancellation + chat timeout** (core `client.lua`, `ami-chat`)
      Done: `stream_chat` has an idle watchdog (`chat.timeout_ms`, default 120s) and a
      once-only settle guard; a signal-killed curl now routes to on_error. ami-chat
      keeps the in-flight handle, adds `:AmiStop` + `keymaps.stop` (`<C-c>`), and
      cancels on panel close ("[stopped]" shown, not an error).
- [x] **3. `ami-persona.nvim`** — inject a style/system message via `chat_turn_pre`.
      Done: built-in personas (terse/teacher/reviewer) + user-defined, `:AmiPersona`
      to switch/off, injected as a system message after the advisor prompt.
- [x] **5. Extension health hooks** — `api.health(fn)` aggregated into `:checkhealth ami`.
      Done: core registry + health.lua renders a section per extension; chat/history/
      inline/proactive each contribute one.
- [x] **4. Context-provider extensions** — done, plus the collector refactor it rode
      in on: core `emit_collect`; collector hooks `chat.system` (persona migrated off
      mutating req) and `context.extra` (folded into context.assemble); reference
      provider `ami-context-git.nvim` (uncommitted diff).
- [ ] **2. Automated test suite + CI** — headless specs for context.assemble, the
      session tree, event bus/registry, history provider; run in CI.

Done: pure-Lua core (no daemon), history as an extension, swappable chat_ui,
model registry, syntax-highlighted transcript, configurable keymaps everywhere.
