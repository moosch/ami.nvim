.PHONY: build run test tidy clean demos optimize-demos

BIN := bin/amid

build:
	go build -o $(BIN) ./cmd/amid

run:
	go run ./cmd/amid

test:
	go test ./...

tidy:
	go mod tidy

clean:
	rm -rf bin

# Render the README demo GIFs. Requires `vhs` (https://github.com/charmbracelet/vhs)
# and a running LM Studio. Override the endpoint/models via env, e.g.:
#   AMI_ENDPOINT=http://192.168.68.100:1234/v1 make demos
# Build the daemon first so the chat/tree demos don't race a `go build` on launch.
demos: build
	vhs demos/inline.tape
	vhs demos/chat.tape
	vhs demos/tree.tape
	vhs demos/tree-branch.tape
	vhs demos/model.tape
	@$(MAKE) optimize-demos

# Shrink the rendered GIFs for GitHub (best-effort; no-op without gifsicle).
optimize-demos:
	@if command -v gifsicle >/dev/null; then \
		for f in demos/*.gif; do gifsicle -O3 --lossy=80 -b "$$f" && echo "optimized $$f"; done; \
	else \
		echo "gifsicle not installed — skipping GIF optimization (brew install gifsicle)"; \
	fi
