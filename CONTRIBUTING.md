# Contributing to Wayland Connect

Thank you for your interest in contributing to Wayland Connect! We welcome contributions from the community to help make this project better.

## 🏗️ Project Structure

This is a **monorepo** containing multiple components:

- **rust_backend/**: The core logic server written in Rust. Handles input simulation (uinput), D-Bus communication, and device management.
- **wayland_pointer_overlay/**: A standalone Rust application that draws the custom cursor and visual effects on Wayland using `gtk4-layer-shell`.
- **wayland_connect_desktop/**: The desktop dashboard application built with Flutter (Linux).
- **wayland_connect_android/**: The mobile client application built with Flutter (Android).

## 🛠️ Development Setup

### Prerequisites

- **Rust**: Latest stable version (`rustup`).
- **Flutter**: Latest stable version (`flutter doctor`).
- **System Dependencies** (Debian/Ubuntu):
  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libgtk-4-dev liblzma-dev libstdc++-12-dev libwayland-dev libxkbcommon-dev libgtk4-layer-shell-dev
  ```

### Building

We use a `Makefile` to simplify common tasks.

```bash
# Build everything (Desktop)
make build

# Build specific components
make build-backend
make build-overlay
make build-desktop

# Run tests
make test
```

## 📝 Coding Standards

- **Rust**: Follow standard Rust idioms. Run `cargo fmt` and `cargo clippy` before committing.
- **Flutter**: Follow the Effective Dart style guide. Run `flutter format .` and `flutter analyze`.

## 🤝 Pull Request Process

1. Fork the repository.
2. Create a new branch (`git checkout -b feature/amazing-feature`).
3. Commit your changes (`git commit -m 'Add some amazing feature'`).
4. Push to the branch (`git push origin feature/amazing-feature`).
5. Open a Pull Request.

## ⚖️ License

By contributing, you agree that your contributions will be licensed under the MIT License defined in [LICENSE](LICENSE).
