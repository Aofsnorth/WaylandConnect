#!/bin/bash
# WaylandConnect Auto-Installer
# One-command installation script for Linux

set -e

INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="waylandconnect"
CONFIG_DIR="$HOME/.config/waylandconnect"
UDEV_RULES="/etc/udev/rules.d/99-waylandconnect-uinput.rules"
SYSTEMD_SERVICE="/etc/systemd/user/${SERVICE_NAME}.service"

echo "╔════════════════════════════════════════╗"
echo "║   WaylandConnect Installer v0.1.0      ║"
echo "║   Remote Control for Linux Wayland     ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo "⚠️  Please do NOT run as root. The script will request sudo when needed."
   exit 1
fi

# Step 1: Build everything
echo "📦 Building project components..."

echo "🦀 Building Rust backend..."
cd rust_backend && cargo build --release && cd ..

echo "🎨 Building Wayland Overlay..."
cd wayland_pointer_overlay && cargo build --release && cd ..

echo "💙 Building Flutter Desktop App..."
cd wayland_connect_desktop && flutter build linux --release && cd ..

# Step 2: Install into /opt
echo "📋 Installing to /opt/wayland-connect (requires sudo)..."
OPT_DIR="/opt/wayland-connect"
sudo mkdir -p "$OPT_DIR/bin"
sudo cp rust_backend/target/release/wayland_connect_backend "$OPT_DIR/bin/"
sudo cp wayland_pointer_overlay/target/release/wayland_pointer_overlay "$OPT_DIR/bin/"

# Copy Flutter Bundle
FLUTTER_BUNDLE="wayland_connect_desktop/build/linux/x64/release/bundle"
sudo cp "$FLUTTER_BUNDLE/wayland_connect_desktop" "$OPT_DIR/bin/"
sudo cp -r "$FLUTTER_BUNDLE/lib" "$OPT_DIR/bin/"
sudo cp -r "$FLUTTER_BUNDLE/data" "$OPT_DIR/bin/"

# Symlink
sudo ln -sf "$OPT_DIR/bin/wayland_connect_desktop" "$INSTALL_DIR/wayland-connect"

# Step 3: Create config directory
echo "📁 Creating config directory..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/trusted_devices"

# Step 4: Install udev rules
echo "⚙️  Installing udev rules (requires sudo)..."
sudo tee "$UDEV_RULES" > /dev/null << 'EOF'
KERNEL=="uinput", MODE="0666", GROUP="input", OPTIONS+="static_node=uinput"
SUBSYSTEM=="input", ATTRS{name}=="WaylandConnect Virtual Mouse", ENV{ID_INPUT}="1", ENV{ID_INPUT_MOUSE}="1", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

# Step 5: Install Desktop Entry
echo "🖥️  Creating desktop shortcut..."
sudo tee /usr/share/applications/wayland-connect.desktop > /dev/null << EOF
[Desktop Entry]
Name=Wayland Connect
Comment=Control Wayland from your Android device
Exec=$OPT_DIR/bin/wayland_connect_desktop
Icon=$OPT_DIR/bin/data/flutter_assets/assets/images/app_icon.png
Terminal=false
Type=Application
Categories=Utility;RemoteAccess;
EOF

# Step 6: Load uinput module
echo "🔌 Loading uinput kernel module..."
sudo modprobe uinput
echo "uinput" | sudo tee -a /etc/modules-load.d/uinput.conf > /dev/null

echo ""
echo "✅ Installation complete!"
echo "🎉 You can now launch 'Wayland Connect' from your app menu or terminal."
echo ""
