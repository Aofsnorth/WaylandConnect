import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:ui';

import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _startOnBoot = true;
  bool _notificationGranted = false;
  bool _batteryOptimized = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _startOnBoot = prefs.getBool('start_on_boot') ?? true;
    });
  }

  Future<void> _checkPermissions() async {
    final nStatus = await Permission.notification.status;
    final bStatus = await Permission.ignoreBatteryOptimizations.status;
    
    if (!mounted) return;
    setState(() {
      _notificationGranted = nStatus.isGranted;
      _batteryOptimized = bStatus.isGranted;
    });
  }

  Future<void> _toggleStartOnBoot(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('start_on_boot', value);
    setState(() => _startOnBoot = value);
    
    // Linux Autostart Logic
    if (Platform.isLinux) {
      try {
        final String home = Platform.environment['HOME'] ?? '/';
        final String autostartDir = '$home/.config/autostart';
        final File desktopFile = File('$autostartDir/wayland_connect.desktop');

        if (value) {
          final Directory dir = Directory(autostartDir);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }

          final String execPath = Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;
          
          final String content = '''[Desktop Entry]
Type=Application
Name=Wayland Connect
Comment=Remote control receiver
Exec=$execPath
Icon=wayland_connect
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
''';
          await desktopFile.writeAsString(content);
        } else {
          if (await desktopFile.exists()) {
            await desktopFile.delete();
          }
        }
      } catch (e) {
        debugPrint("Error toggling autostart: $e");
      }
      return; 
    }

    // Update service configuration (Mobile)
    if (value) {
      FlutterBackgroundService().invoke("setAsBackground");
    } else {
      FlutterBackgroundService().invoke("setAsForeground");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionHeader("Boot & Background"),
          _buildSettingCard(
            icon: Icons.power_settings_new_rounded,
            title: "Start on Boot",
            subtitle: "Automatically start service when phone turns on",
            trailing: Switch(
              value: _startOnBoot,
              onChanged: _toggleStartOnBoot,
              activeColor: Colors.white,
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader("Permissions"),
          _buildPermissionCard(
            icon: Icons.notifications_active_rounded,
            title: "Notifications",
            subtitle: "Required to keep connection alive in background",
            isGranted: _notificationGranted,
            onTap: () async {
              await Permission.notification.request();
              _checkPermissions();
            },
          ),
          _buildPermissionCard(
            icon: Icons.battery_saver_rounded,
            title: "Ignore Battery Optimization",
            subtitle: "Prevent Android from killing the app in standby",
            isGranted: _batteryOptimized,
            onTap: () async {
              await Permission.ignoreBatteryOptimizations.request();
              _checkPermissions();
            },
          ),
          const SizedBox(height: 48),
          const Center(
            child: Text(
              "Wayland Connect v1.0.4",
              style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2),
      ),
    );
  }

  Widget _buildSettingCard({required IconData icon, required String title, required String subtitle, required Widget trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildPermissionCard({required IconData icon, required String title, required String subtitle, required bool isGranted, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: isGranted ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isGranted ? Colors.green.withOpacity(0.05) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isGranted ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isGranted ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: Icon(icon, color: isGranted ? Colors.greenAccent : Colors.white70, size: 20),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isGranted ? Colors.white : Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            if (isGranted)
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24)
            else
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}
