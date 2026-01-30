#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/opt/wayland-connect"
BIN_DIR="$INSTALL_DIR/bin"
ASSETS_DIR="$INSTALL_DIR/assets"

echo -e "${GREEN}🔧 Installing Wayland Connect...${NC}"

# 1. Check dependencies
echo "📦 Checking dependencies..."
DEPS=("cargo" "flutter" "make")
for dep in "${DEPS[@]}"; do
    if ! command -v $dep &> /dev/null; then
        echo -e "${RED}❌ $dep not found.${NC} Please install it first."
        exit 1
    fi
done

# 2. Setup Udev Rule for UInput
echo "🛡️ Setting up uinput permissions..."
echo 'KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/99-wayland-connect-uinput.rules > /dev/null
sudo usermod -aG input $USER
sudo udevadm control --reload-rules
sudo udevadm trigger

# 3. Build Components
echo -e "${BLUE}🏗️ Building Rust Backend...${NC}"
cd rust_backend && cargo build --release && cd ..

echo -e "${BLUE}🎨 Building Wayland Overlay...${NC}"
cd wayland_pointer_overlay && cargo build --release && cd ..

echo -e "${BLUE}💙 Building Flutter Desktop App...${NC}"
cd wayland_connect_desktop && flutter build linux --release && cd ..

# 4. Install Binaries and Assets
echo "🚀 Installing to $INSTALL_DIR..."
sudo mkdir -p "$BIN_DIR"
sudo mkdir -p "$ASSETS_DIR"

sudo cp rust_backend/target/release/wayland_connect_backend "$BIN_DIR/"
sudo cp wayland_pointer_overlay/target/release/wayland_pointer_overlay "$BIN_DIR/"
sudo cp -r wayland_connect_desktop/build/linux/x64/release/bundle/* "$INSTALL_DIR/"

# Create symlink for easier access
sudo ln -sf "$INSTALL_DIR/wayland_connect_desktop" "/usr/local/bin/wayland-connect"

# 5. Create Desktop Entry
echo "🖥️ Creating Desktop Entry..."
# Install icon to system icons directory
sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
sudo cp wayland_connect_desktop/assets/images/app_icon.png /usr/share/icons/hicolor/512x512/apps/wayland-connect.png
sudo gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

cat <<EOF | sudo tee /usr/share/applications/wayland-connect.desktop > /dev/null
[Desktop Entry]
Name=Wayland Connect
Comment=Remote control and presentation tool for Wayland
Exec=/usr/local/bin/wayland-connect
Icon=wayland-connect
Terminal=false
Type=Application
Categories=Utility;RemoteControl;
EOF

# 6. Create Systemd User Service (Backend)
echo "⚙️ Creating Systemd User Service..."
mkdir -p ~/.config/systemd/user/
cat <<EOF > ~/.config/systemd/user/wayland-connect.service
[Unit]
Description=Wayland Connect Backend Service
After=network.target

[Service]
ExecStart=$BIN_DIR/wayland_connect_backend
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable wayland-connect.service

echo -e "${GREEN}✅ Installation Complete!${NC}"
echo "You can now launch Wayland Connect from your application menu."
echo -e "${GREEN}Note: You may need to logout and login again for group permissions to apply.${NC}"
