# 🚀 Wayland Connect

[![Release](https://img.shields.io/github/v/release/Aofsnorth/WaylandConnect?style=for-the-badge&color=blue)](https://github.com/Aofsnorth/WaylandConnect/releases)
[![Build Status](https://img.shields.io/github/actions/workflow/status/Aofsnorth/WaylandConnect/release.yml?style=for-the-badge)](https://github.com/Aofsnorth/WaylandConnect/actions)
[![License](https://img.shields.io/github/license/Aofsnorth/WaylandConnect?style=for-the-badge&color=green)](LICENSE)
![Visitors](https://api.visitorbadge.io/api/visitors?path=Aofsnorth%2FWaylandConnect&label=PROJECT%20VIEWS&countColor=%23263238&style=for-the-badge)
![Downloads](https://img.shields.io/github/downloads/Aofsnorth/WaylandConnect/total?style=for-the-badge&color=orange)
![Made with Vibe Code](https://img.shields.io/badge/Made%20with-Vibe%20Code-purple?style=for-the-badge&logo=openai)

### 📊 Repository Activity
![Activity Graph](https://github-readme-activity-graph.vercel.app/graph?username=Aofsnorth&theme=react&bg_color=1f222e&color=697689&line=2196f3&point=f44336&area=true&hide_border=true)

[English](#-english) | [Bahasa Indonesia](#-bahasa-indonesia)

---

# 🇺🇸 English

> [!CAUTION]
> **Warning**: This application and its code were built with the assistance of **Artificial Intelligence (AI)**.

Wayland Connect is a professional remote control and presentation tool tailor-made for the Linux Wayland ecosystem. It allows you to transform your Android device into a powerful controller for your PC with low latency and a premium aesthetic.


## 💎 Key Features

- **Integrated Dashboard**: Monitor connection status, server IP, and connected devices in a sleek, modern interface.
- **UDP Discovery**: Fast and automatic device detection—no more manual IP entry required.
- **Multi-Pointer Support**: Multiple devices can now control independent pointers on the screen simultaneously.
- **Air Mouse (Presentation Pointer)**: Use your phone's gyroscope as a laser pointer on your PC screen. Features multiple modes: Laser Dot, Ring, Hollow Frame, and more.
- **Screen Mirroring**: Share your Android screen to your PC with low latency for presentations or monitoring.
- **Precision Control**: Seamless cursor navigation, click gestures (using volume/power buttons as shortcuts), and smooth scrolling.
- **Keyboard Control**: Type on your PC directly from your Android keyboard.
- **Media Controller**: Control music and video players (MPV, Spotify, Browsers, etc.) directly from your palm.
- **Security First**: TLS 1.3 encryption for all communications.
- **Trusted Devices**: Trust-On-First-Use (TOFU) certificate pinning prevents Man-in-the-Middle (MITM) attacks.
- **Minimalist Overlay**: Beautiful, animated custom cursors on the Linux side for high-impact presentations.

## ⚙️ System Requirements

- **PC**: Linux with Wayland (Hyprland, Sway, GNOME Wayland, etc.).
- **Android**: Version 8.0 (Oreo) or higher.
- **Network**: Both devices must be connected to the same Wi-Fi/LAN network.

## 📥 Installation

### Linux (Build from Source)
**Prerequisites:**
- [Rust](https://www.rust-lang.org/tools/install) installed.
- [Flutter](https://flutter.dev/docs/get-started/install/linux) installed.
- System dependencies: `libayatana-appindicator3-dev`, `libgtk-3-dev`, `libgtk-4-dev`, `libwayland-dev`, `libudev-dev`.

Run the automated installer script to build and install all components:

```bash
git clone https://github.com/Aofsnorth/WaylandConnect.git
cd WaylandConnect
chmod +x install.sh
./install.sh
```
*The script compiles the project and installs it to `/opt/wayland-connect`, configures udev rules, and creates a desktop shortcut.*


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
- **Screen Share**: **Rust** backend utilizing PipeWire and Portal (`wayland_share_screen`).
- **Desktop UI**: Developed using **Flutter** (`wayland_connect_desktop`).
- **Android App**: Developed using **Flutter** (`wayland_connect_android`).
- **Security**: **TLS 1.3** and **SHA-256** fingerprinting for robust device verification.

## 📜 License
This project is licensed under the [MIT License](LICENSE).

---

# 🇮🇩 Bahasa Indonesia

> [!CAUTION]
> **Peringatan**: Seluruh aplikasi dan kode program ini dibangun dengan bantuan **Kecerdasan Buatan (AI)**.

Wayland Connect adalah aplikasi *remote control* dan alat presentasi modern yang dirancang khusus untuk ekosistem Linux (Wayland). Kendalikan PC Linux Anda langsung dari perangkat Android dengan latensi rendah dan antarmuka yang elegan.


## ✨ Fitur Utama

- **Dashboard Terintegrasi**: Pantau status koneksi, IP Server, dan perangkat yang terhubung dalam satu tampilan premium.
- **UDP Discovery**: Deteksi perangkat secara otomatis dan cepat—tidak perlu lagi memasukkan IP secara manual.
- **Multi-Pointer Support**: Mendukung pengendalian kursor secara independen dari beberapa perangkat sekaligus.
- **Presentation Pointer (Air Mouse)**: Gunakan giroskop HP Anda sebagai *laser pointer* di layar PC. Dilengkapi dengan berbagai mode (Laser Dot, Ring, Hollow Frame, dll).
- **Screen Mirroring**: Bagikan layar Android ke PC dengan latensi rendah untuk presentasi atau monitoring.
- **Mouse & Gesture Control**: Navigasi kursor, klik (termasuk tombol volume & power sebagai shortcut), dan scroll dengan mulus.
- **Keyboard Control**: Mengetik di PC langsung dari keyboard Android Anda.
- **Media Controller**: Kendalikan pemutar musik/video (MPV, Spotify, Browser, dll) langsung dari genggaman.
- **Security First**: Enkripsi TLS 1.3 untuk seluruh komunikasi.
- **Trusted Devices**: Sistem *Trust-On-First-Use* (TOFU) untuk mencegah serangan Man-in-the-Middle (MITM).
- **Minimalist Overlay**: Kursor khusus yang cantik dan animatif di sisi Linux untuk presentasi yang memukau.

## 🛠️ Persyaratan Sistem

- **PC**: Linux dengan Wayland (Hyprland, Sway, GNOME Wayland, dll).
- **Android**: Versi 8.0 (Oreo) atau lebih tinggi.
- **Jaringan**: PC dan Android harus berada di jaringan Wi-Fi/LAN yang sama.

## 📥 Instalasi (Linux - Build from Source)

**Prasyarat:**
- [Rust](https://www.rust-lang.org/tools/install) telah terinstal.
- [Flutter](https://flutter.dev/docs/get-started/install/linux) telah terinstal.
- Dependensi sistem: `libayatana-appindicator3-dev`, `libgtk-3-dev`, `libgtk-4-dev`, `libwayland-dev`, `libudev-dev`.

Jalankan script installer otomatis untuk membangun (*build*) dan menginstal:

```bash
git clone https://github.com/Aofsnorth/WaylandConnect.git
cd WaylandConnect
chmod +x install.sh
./install.sh
```
*Script ini akan mengkompilasi aplikasi, menginstalnya ke `/opt/wayland-connect`, mengatur udev rules, dan membuat shortcut.*


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
- **Screen Share**: Backend **Rust** menggunakan PipeWire & Portal (`wayland_share_screen`).
- **Desktop App**: Dibangun dengan **Flutter** (`wayland_connect_desktop`).
- **Android App**: Dibangun dengan **Flutter** (`wayland_connect_android`).

## 📜 Lisensi

Project ini dilisensikan di bawah [MIT License](LICENSE).

---
Made with ❤️ by [Aofsnorth](https://github.com/Aofsnorth)
