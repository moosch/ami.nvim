.PHONY: build run test tidy clean demos

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
demos:
	vhs demos/inline.tape
	vhs demos/chat.tape
	vhs demos/tree.tape
	vhs demos/tree-branch.tape
	vhs demos/model.tape
