.PHONY: check demos optimize-demos

# ami is now pure Lua — there is no build step. `check` verifies version
# consistency; `demos` renders the README GIFs.

check:
	scripts/check-version.sh

# Render the README demo GIFs. Requires `vhs` (https://github.com/charmbracelet/vhs)
# and a running LM Studio. Override the endpoint/models via env, e.g.:
#   AMI_ENDPOINT=http://192.168.68.100:1234/v1 make demos
demos:
	vhs demos/inline.tape
	vhs demos/chat.tape
	vhs demos/model.tape
	@$(MAKE) optimize-demos

# Shrink the rendered GIFs for GitHub (best-effort; no-op without gifsicle).
optimize-demos:
	@if command -v gifsicle >/dev/null; then \
		for f in demos/*.gif; do gifsicle -O3 --lossy=80 -b "$$f" && echo "optimized $$f"; done; \
	else \
		echo "gifsicle not installed — skipping GIF optimization (brew install gifsicle)"; \
	fi
