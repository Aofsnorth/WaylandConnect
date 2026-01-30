#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}🗑️ Uninstalling Wayland Connect...${NC}"

# 1. Stop and Disable Service
echo "🛑 Stopping service..."
systemctl --user stop wayland-connect.service 2>/dev/null || true
systemctl --user disable wayland-connect.service 2>/dev/null || true
rm -f ~/.config/systemd/user/wayland-connect.service
systemctl --user daemon-reload

# 2. Remove Binaries and Symlinks
echo "🗑️ Removing binaries and symlinks..."
sudo rm -f /usr/local/bin/wayland-connect
sudo rm -rf /opt/wayland-connect

# 3. Remove Desktop Entry
echo "🖥️ Removing desktop entry and icons..."
sudo rm -f /usr/share/applications/wayland-connect.desktop
sudo rm -f /usr/share/icons/hicolor/512x512/apps/wayland-connect.png
sudo gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

# 4. Remove Udev Rules
echo "🛡️ Removing udev rules..."
sudo rm -f /etc/udev/rules.d/99-wayland-connect-uinput.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# 5. Optional: Clean Config
read -p "Do you want to delete configuration files (~/.config/wayland-connect)? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf ~/.config/wayland-connect
    echo "🧹 Configuration deleted."
fi

echo -e "${GREEN}✅ Uninstalled successfully.${NC}"
