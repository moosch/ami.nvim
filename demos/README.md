# Demo recordings

The `*.tape` files here are [VHS](https://github.com/charmbracelet/vhs) scripts —
the **source** for the GIFs shown in the main README. GitHub does not render a
`.tape`; you render it to a `.gif` and commit the `.gif`.

```
.tape  ──vhs──▶  .gif  ──git add / commit──▶  shown in README
```

These are **examples of core + the first-party extensions**: `demos/init.lua` loads
ami core together with the extensions each demo needs. The GIFs are not of core
alone.

| Tape | Shows | Extension used |
| --- | --- | --- |
| `inline.tape` | comment-driven FIM completion | [`ami-inline.nvim`](https://github.com/moosch/ami-inline.nvim) |
| `chat.tape` | the chat advisor panel | [`ami-chat.nvim`](https://github.com/moosch/ami-chat.nvim) |
| `model.tape` | the model registry / `:AmiModel` | core, with `chat`/`fim` slots from the two above |
| `doc.tape` | `/doc` document generation into the repo | [`ami-doc.nvim`](https://github.com/moosch/ami-doc.nvim) |

## Prerequisites

- `vhs` (`brew install vhs` — pulls in `ttyd` and `ffmpeg`)
- `gifsicle` (optional, for smaller files: `brew install gifsicle`)
- A running **LM Studio** with a model loaded — the GIFs show real responses.
- The extension repos above **checked out next to this one** (siblings of the ami
  repo): `demos/init.lua` adds `../ami-chat.nvim` and `../ami-inline.nvim` to the
  runtimepath and loads whichever it finds.

## Render

From the repository root:

```sh
# localhost LM Studio
make demos

# or point at your server / pick models:
AMI_ENDPOINT=http://192.168.68.100:1234/v1 \
AMI_CHAT_MODEL=qwen3-coder \
AMI_FIM_MODEL=qwen3-coder \
make demos
```

`make demos` renders every tape, then (if `gifsicle` is installed) optimizes the
GIFs in place. To render a single one: `vhs demos/inline.tape`.

`doc.tape` needs `ami-doc.nvim` checked out as a sibling and launches with
`AMI_DEMO_DOC=1` (so the `doc` extension loads only for this demo); render it with
`AMI_DEMO_DOC=1 vhs demos/doc.tape`. It writes `EXAMPLE.md` into a throwaway
`/tmp/ami_doc_demo` project, not this repo.

ami-doc doesn't stream into the chat, so the raw render has a static "writing…"
stretch while the model works. The committed `doc.gif` has that gap (and the long
static tail) trimmed out with `ffmpeg`'s `select` filter — keep the command + reveal,
drop the wait. Adjust the two time windows to match your render's timings:

```sh
ffmpeg -y -i demos/doc.gif -filter_complex \
  "[0:v]select='lt(t,14)+between(t,19.5,23.5)',setpts=N/FRAME_RATE/TB,fps=24,\
   split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer" \
  demos/doc.trimmed.gif && mv demos/doc.trimmed.gif demos/doc.gif
# lt(t,14): keep intro+command up to ~14s · between(…): keep the reveal window
```

`chat.tape` defaults its chat model to **`deepseek-coder`** (fast replies that
keep the GIF short); set `AMI_CHAT_MODEL` to override. It shows the advisor panel
in its default look — right-docked and semi-transparent, so the source file stays
visible behind it.

Then commit the output:

```sh
git add demos/*.gif && git commit -m "docs: update demo gifs"
```

> `tree.tape` and `tree-branch.tape` are kept here but are **not** part of
> `make demos` or the main README yet — they need more timing/navigation work.

## Tuning

These scripts are timing-based, so adjust them to your model's latency:

- The `Sleep` after a trigger/send must cover the time until the ghost text or
  streamed reply appears. The chat/tree tapes wait on real LLM responses — lengthen
  those `Sleep`s for slower models.
- `tree.tape` / `tree-branch.tape` navigate windows (`Ctrl+W l`) and nodes (`j`,
  `<CR>`/`s`); adjust if your layout differs.
- `model.tape` assumes the built-in `vim.ui.select` (numbered list). With
  telescope/fzf/snacks the keystrokes differ.
- Keep files GitHub-friendly (<~10 MB): the tapes set `Framerate 24`; drop
  `Width`/`Height` further or rely on the `gifsicle` pass if a GIF is still large.

`init.lua` is the minimal Neovim config the tapes launch (`nvim -u demos/init.lua`).
