.PHONY: all build build-backend build-overlay build-desktop build-android test clean help appimage
.DEFAULT_GOAL := help

appimage: ## Build the AppImage for Linux
	@echo "📦 Building AppImage..."
	@chmod +x build_appimage.sh
	./build_appimage.sh


# Variables
CARGO := cargo
FLUTTER := flutter

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: build ## Build all components (Desktop)

build: build-backend build-overlay build-desktop ## Build all desktop components

build-backend: ## Build the Rust backend
	@echo "🦀 Building Rust Backend..."
	cd rust_backend && $(CARGO) build --release

build-overlay: ## Build the Wayland Overlay
	@echo "🎨 Building Wayland Overlay..."
	cd wayland_pointer_overlay && $(CARGO) build --release

build-desktop: ## Build the Flutter Linux App
	@echo "💙 Building Flutter Desktop..."
	cd wayland_connect_desktop && $(FLUTTER) build linux --release
	@echo "🗜️ Stripping Desktop binary..."
	@strip wayland_connect_desktop/build/linux/x64/release/bundle/wayland_connect_desktop || true

build-android: ## Build the Flutter Android App
	@echo "🤖 Building Flutter Android (Split by ABI for smaller size)..."
	cd wayland_connect_android && $(FLUTTER) build apk --release --split-per-abi

test: ## Run tests for all components
	@echo "🧪 Running Tests..."
	cd rust_backend && $(CARGO) test
	cd wayland_connect_desktop && $(FLUTTER) test

clean: ## Clean build artifacts
	@echo "🧹 Cleaning..."
	cd rust_backend && $(CARGO) clean
	cd wayland_pointer_overlay && $(CARGO) clean
	cd wayland_connect_desktop && $(FLUTTER) clean
	cd wayland_connect_android && $(FLUTTER) clean

format: ## Format code
	@echo "✨ Formatting code..."
	cd rust_backend && $(CARGO) fmt
	cd wayland_pointer_overlay && $(CARGO) fmt
	cd wayland_connect_desktop && $(FLUTTER) format .
	cd wayland_connect_android && $(FLUTTER) format .
