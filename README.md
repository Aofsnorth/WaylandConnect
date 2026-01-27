# 🚀 Wayland Connect

[English](#-english) | [Bahasa Indonesia](#-bahasa-indonesia)

---

# 🇺🇸 English

Wayland Connect is a professional remote control and presentation tool tailor-made for the Linux Wayland ecosystem. It allows you to transform your Android device into a powerful controller for your PC with low latency and a premium aesthetic.

## 💎 Key Features

- **Integrated Dashboard**: Monitor connection status, server IP, and connected devices in a sleek, modern interface.
- **Air Mouse (Presentation Pointer)**: Use your phone's gyroscope as a laser pointer on your PC screen. Features multiple modes: Laser Dot, Ring, Hollow Frame, and more.
- **Precision Control**: Seamless cursor navigation, click gestures (using volume/power buttons as shortcuts), and smooth scrolling.
- **Media Controller**: Control music and video players (MPV, Spotify, Browsers, etc.) directly from your palm.
- **Security First**: A "Trusted Devices" system ensures only authorized devices can take control.
- **Minimalist Overlay**: Beautiful, animated custom cursors on the Linux side for high-impact presentations.

## ⚙️ System Requirements

- **PC**: Linux with Wayland (Hyprland, Sway, GNOME Wayland, etc.).
- **Android**: Version 8.0 (Oreo) or higher.
- **Network**: Both devices must be connected to the same Wi-Fi/LAN network.

## 📥 Installation

### Linux (Server)
Run the automated installer script to build and install all necessary components:

```bash
git clone https://github.com/Aofsnorth/WaylandConnect.git
cd WaylandConnect
chmod +x install.sh
./install.sh
```
*The script installs the app to `/opt/wayland-connect`, configures udev rules for input, and creates a desktop shortcut.*

### Android (Client)
Download the latest APK from the [Releases](https://github.com/Aofsnorth/WaylandConnect/releases) page.

## 🚀 Quick Start

1. Launch **Wayland Connect** on your Linux PC.
2. Toggle **Service Active** on the Dashboard.
3. Open the Android app and enter the IP address shown on your PC Dashboard.
4. Tap **Connect**.
5. Accept the connection request on your PC (a notification will appear).

## 🛠️ Technical Stack

- **Backend**: Built with **Rust** for performance and safety (`rust_backend`).
- **Overlay**: **Rust** utilizing `wayland-client` for low-level interaction (`wayland_pointer_overlay`).
- **Desktop UI**: Developed using **Flutter** (`wayland_connect_desktop`).
- **Android App**: Developed using **Flutter** (`wayland_connect_android`).

## 📜 License
This project is licensed under the [MIT License](LICENSE).

---

# 🇮🇩 Bahasa Indonesia

Wayland Connect adalah aplikasi *remote control* dan alat presentasi modern yang dirancang khusus untuk ekosistem Linux (Wayland). Kendalikan PC Linux Anda langsung dari perangkat Android dengan latensi rendah dan antarmuka yang elegan.

## ✨ Fitur Utama

- **Dashboard Terintegrasi**: Pantau status koneksi, IP Server, dan perangkat yang terhubung dalam satu tampilan premium.
- **Presentation Pointer (Air Mouse)**: Gunakan giroskop HP Anda sebagai *laser pointer* di layar PC. Dilengkapi dengan berbagai mode (Laser Dot, Ring, Hollow Frame, dll).
- **Mouse & Gesture Control**: Navigasi kursor, klik (termasuk tombol volume & power sebagai shortcut), dan scroll dengan mulus.
- **Media Controller**: Kendalikan pemutar musik/video (MPV, Spotify, Browser, dll) langsung dari genggaman.
- **Security First**: Sistem *Trusted Devices* memastikan hanya perangkat yang Anda izinkan yang bisa mengendalikan PC.
- **Minimalist Overlay**: Kursor khusus yang cantik dan animatif di sisi Linux untuk presentasi yang memukau.

## 🛠️ Persyaratan Sistem

- **PC**: Linux dengan Wayland (Hyprland, Sway, GNOME Wayland, dll).
- **Android**: Versi 8.0 (Oreo) atau lebih tinggi.
- **Jaringan**: PC dan Android harus berada di jaringan Wi-Fi/LAN yang sama.

## 📥 Instalasi (Linux)

Cukup jalankan script installer otomatis untuk membangun (*build*) dan menginstal semua komponen:

```bash
git clone https://github.com/Aofsnorth/WaylandConnect.git
cd WaylandConnect
chmod +x install.sh
./install.sh
```
*Script ini akan menginstal aplikasi ke `/opt/wayland-connect`, mengatur udev rules untuk input, dan membuat shortcut di menu aplikasi Anda.*

## 📱 Instalasi (Android)

Unduh APK terbaru dari halaman [Releases](https://github.com/Aofsnorth/WaylandConnect/releases) dan instal di smartphone Anda.

## 🚀 Cara Penggunaan

1. Buka aplikasi **Wayland Connect** di Linux.
2. Aktifkan **Service Active** di Dashboard.
3. Buka aplikasi di Android, masukkan IP yang tertera di Dashboard PC.
4. Klik **Connect**.
5. Terima permintaan koneksi di PC (akan muncul notifikasi).

## 🔧 Pengembangan (Development)

- **Backend**: Ditulis menggunakan **Rust** (`rust_backend`).
- **Overlay**: Ditulis menggunakan **Rust** + Crate `wayland-client` (`wayland_pointer_overlay`).
- **Desktop App**: Dibangun dengan **Flutter** (`wayland_connect_desktop`).
- **Android App**: Dibangun dengan **Flutter** (`wayland_connect_android`).

## 📜 Lisensi

Project ini dilisensikan di bawah [MIT License](LICENSE).

---
Made with ❤️ by [Aofsnorth](https://github.com/Aofsnorth)
