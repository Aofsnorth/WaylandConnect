#!/bin/bash
magick wayland_connect_android/assets/images/app_icon.png -resize 256x256 wayland_connect_android/assets/images/app_icon.png
magick wayland_connect_android/assets/images/app_logo.png -resize 256x256 wayland_connect_android/assets/images/app_logo.png
magick wayland_connect_desktop/tray_icon.png -resize 256x256 wayland_connect_desktop/tray_icon.png
magick wayland_connect_android/assets/images/background.png -resize 800x800 -quality 75 wayland_connect_android/assets/images/background.png
