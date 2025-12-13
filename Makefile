.PHONY: all build build-linux build-darwin build-windows clean install deps

# Binary name
BINARY_NAME=pc-management-exporter

# Build directory
BUILD_DIR=build

all: deps build

# Install dependencies
deps:
	go mod tidy
	go mod download

# Build for current platform
build: deps
	go build -o $(BUILD_DIR)/$(BINARY_NAME) .

# Build for Linux
build-linux: deps
	GOOS=linux GOARCH=amd64 go build -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 .

# Build for macOS
build-darwin: deps
	GOOS=darwin GOARCH=amd64 go build -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 .
	GOOS=darwin GOARCH=arm64 go build -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 .

# Build for Windows
build-windows: deps
	GOOS=windows GOARCH=amd64 go build -o $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe .
	GOOS=windows GOARCH=arm64 go build -o $(BUILD_DIR)/$(BINARY_NAME)-windows-arm64.exe .

# Build for all platforms
build-all: build-linux build-darwin build-windows

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	go clean

# Install to system (requires root on Linux/macOS)
install: build
	install -m 755 $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/

# Run the exporter (requires HOOK_URL)
run: build
	@if [ -z "$(HOOK_URL)" ]; then \
		echo "Error: HOOK_URL is required. Usage: make run HOOK_URL=http://your-endpoint"; \
		exit 1; \
	fi
	$(BUILD_DIR)/$(BINARY_NAME) --hook-url $(HOOK_URL)
