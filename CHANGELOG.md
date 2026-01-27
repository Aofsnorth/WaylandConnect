# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-01-28

### ⚡ Optimized
- **Build Size**: 
  - Android APK size reduced by ~60% using ABI splitting, Proguard, and resource shrinking.
  - Desktop binary size reduced significantly using aggressive Rust release optimizations and binary stripping.
  - Compressed all app icons and assets (Reduced icon sizes from ~500KB to ~50KB).
- **GitHub Release**: Optimized release workflow to include split APKs.

## [1.0.0] - 2026-01-28

### 🚀 Added
- **Wayland Connect Desktop**:
  - Integrated Dashboard for monitoring connection status and server info.
  - "Trusted Devices" management system.
  - System Tray support with minimize/restore functionality.
- **Android Client**:
  - Air Mouse (Gyroscope-based) control.
  - Media Controller for MPRIS players (Spotify, MPV, etc).
  - Multi-touch gestures (scrolling, clicking).
- **Core**:
  - `rust_backend`: High-performance TCP/UDP server with `uinput` simulation.
  - `wayland_pointer_overlay`: Smooth, hardware-accelerated custom cursor using `gtk4-layer-shell`.
- **CI/CD**:
  - Automated GitHub Actions for building Android APK and Linux AppImage/Tarball.
  - Auto-release generation on tag creation.

### 🐛 Fixed
- Fixed layout issues on Android devices with notches.
- Resolved pointer jitter by implementing smooth damping in the overlay.
- Fixed `uinput` permission issues with new `install.sh` script.
- Resolved build failures on Linux CI by adding necessary system dependencies (`libgtk4-layer-shell`, `libayatana-appindicator`).

### 🔧 Changed
- Upgraded project to Professional Monorepo structure.
- Introduced `Makefile` for unified build commands.
- Added `CONTRIBUTING.md` for developer guidelines.
