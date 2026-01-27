#!/bin/bash
# WaylandConnect Uninstaller

set -e

SERVICE_NAME="waylandconnect"
INSTALL_DIR="/usr/local/bin"
UDEV_RULES="/etc/udev/rules.d/99-waylandconnect-uinput.rules"
OPT_DIR="/opt/wayland-connect"

echo "🗑️  Starting WaylandConnect Uninstallation..."

# 1. Stop and disable systemd service
echo "🛑 Stopping systemd service..."
systemctl --user stop ${SERVICE_NAME}.service || true
systemctl --user disable ${SERVICE_NAME}.service || true
rm -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
systemctl --user daemon-reload

# 2. Remove binaries and symlinks
echo "📂 Removing binaries..."
sudo rm -f "$INSTALL_DIR/${SERVICE_NAME}-service"
sudo rm -f "$INSTALL_DIR/wayland-connect"
sudo rm -rf "$OPT_DIR"

# 3. Remove udev rules
echo "⚙️  Removing udev rules..."
sudo rm -f "$UDEV_RULES"
sudo udevadm control --reload-rules
sudo udevadm trigger

# 4. Remove desktop entry and icon
echo "🖥️  Removing desktop entry & icon..."
sudo rm -f /usr/share/applications/wayland-connect.desktop
sudo rm -f /usr/share/pixmaps/wayland-connect.png
sudo gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true

echo "✅ Uninstallation complete!"
