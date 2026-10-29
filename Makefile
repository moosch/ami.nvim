.PHONY: build run test tidy clean

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
