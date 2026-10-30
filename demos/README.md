# Demo recordings

The `*.tape` files here are [VHS](https://github.com/charmbracelet/vhs) scripts —
the **source** for the GIFs shown in the main README. GitHub does not render a
`.tape`; you render it to a `.gif` and commit the `.gif`.

```
.tape  ──vhs──▶  .gif  ──git add / commit──▶  shown in README
```

## Prerequisites

- `vhs` (`brew install vhs` — pulls in `ttyd` and `ffmpeg`)
- `gifsicle` (optional, for smaller files: `brew install gifsicle`)
- A running **LM Studio** with a model loaded — the GIFs show real responses.

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
