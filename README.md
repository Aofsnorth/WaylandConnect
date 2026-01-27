# 🚀 Wayland Connect

Wayland Connect adalah aplikasi *remote control* dan alat presentasi modern yang dirancang khusus untuk ekosistem Linux (Wayland). Kendalikan PC Linux Anda langsung dari perangkat Android dengan latensi rendah dan antarmuka yang elegan.

![License](https://img.shields.io/github/license/Aofsnorth/WaylandConnect)
![Release](https://img.shields.io/github/v/release/Aofsnorth/WaylandConnect)

## ✨ Fitur Utama

-   **Dashboard Terintegrasi**: Pantau status koneksi, IP Server, dan perangkat yang terhubung dalam satu tampilan premium.
-   **Presentation Pointer (Air Mouse)**: Gunakan giroskop HP Anda sebagai *laser pointer* di layar PC. Dilengkapi dengan berbagai mode (Laser Dot, Ring, Hollow Frame, dll).
-   **Mouse & Gesture Control**: Navigasi kursor, klik (termasuk tombol volume & power sebagai shortcut), dan scroll dengan mulus.
-   **Media Controller**: Kendalikan pemutar musik/video (MPV, Spotify, Browser, dll) langsung dari genggaman.
-   **Security First**: Sistem *Trusted Devices* memastikan hanya perangkat yang Anda izinkan yang bisa mengendalikan PC.
-   **Minimalist Overlay**: Kursor khusus yang cantik dan animatif di sisi Linux untuk presentasi yang memukau.

## 🛠️ Persyaratan Sistem

-   **PC**: Linux dengan Wayland (Hyprland, Sway, GNOME Wayland, dll).
-   **Android**: Versi 8.0 (Oreo) atau lebih tinggi.
-   **Jaringan**: PC dan Android harus berada di jaringan Wi-Fi/LAN yang sama.

## 📥 Instalasi (Linux)

Cukup jalankan script installer otomatis untuk membangun (build) dan menginstal semua komponen:

```bash
git clone https://github.com/Aofsnorth/WaylandConnect.git
cd WaylandConnect
chmod +x install.sh
./install.sh
```

Script ini akan menginstal aplikasi ke `/opt/wayland-connect`, mengatur *udev rules* untuk input, dan membuat shortcut di menu aplikasi Anda.

## 📱 Instalasi (Android)

Unduh APK terbaru dari halaman [Releases](https://github.com/Aofsnorth/WaylandConnect/releases) dan instal di smartphone Anda.

## 🚀 Cara Penggunaan

1.  Buka aplikasi **Wayland Connect** di Linux.
2.  Aktifkan **Service Active** di Dashboard.
3.  Buka aplikasi di Android, masukkan IP yang tertera di Dashboard PC.
4.  Klik **Connect**.
5.  Terima permintaan koneksi di PC (akan muncul notifikasi).

## 🔧 Pengembangan (Development)

Jika Anda ingin berkontribusi:

-   **Backend**: Ditulis menggunakan Rust (`rust_backend`).
-   **Overlay**: Ditulis menggunakan Rust + Crate `wayland-client` (`wayland_pointer_overlay`).
-   **Desktop App**: Dibangun dengan Flutter (`wayland_connect_desktop`).
-   **Android App**: Dibangun dengan Flutter (`wayland_connect_android`).

## 📜 Lisensi

Project ini dilisensikan di bawah [MIT License](LICENSE).

---
Made with ❤️ by [Aofsnorth](https://github.com/Aofsnorth)
