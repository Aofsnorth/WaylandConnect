import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:ui';

import 'dart:io';
import 'package:wayland_connect_android/l10n/app_localizations.dart';
import '../main.dart';
import '../utils/protocol.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Socket? socket;
  const SettingsScreen({super.key, required this.onBack, this.socket});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _startOnBoot = true;
  bool _notificationGranted = false;
  bool _batteryOptimized = false;
  bool _autoConnect = true;
  bool _autoReconnect = true;

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
      _autoConnect = prefs.getBool('auto_connect') ?? true;
      _autoReconnect = prefs.getBool('auto_reconnect') ?? true;
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

  Future<void> _toggleAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_connect', value);
    setState(() => _autoConnect = value);
  }

  Future<void> _toggleAutoReconnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_reconnect', value);
    setState(() => _autoReconnect = value);

    if (widget.socket != null) {
      final deviceId = prefs.getString('unique_device_id') ?? "unknown";
      widget.socket!.add(ProtocolHandler.encodePacket({
        "type": "set_device_auto_reconnect",
        "data": {"id": deviceId, "enabled": value}
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Colors.white70;

    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              onPressed: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else {
                  Navigator.maybePop(context);
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.only(left: 40, bottom: 20),
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.configuration, style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, letterSpacing: 4, fontSize: 8)),
                  Text(AppLocalizations.of(context)!.settings, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -1)),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    _buildSectionHeader(AppLocalizations.of(context)!.systemBackground),
                    _buildSettingCard(
                         icon: Icons.language,
                         title: AppLocalizations.of(context)!.language,
                         subtitle: AppLocalizations.of(context)!.selectLanguage,
                         trailing: DropdownButton<String>(
                           value: Localizations.localeOf(context).languageCode,
                           dropdownColor: const Color(0xFF1E1E1E),
                           style: const TextStyle(color: Colors.white),
                           underline: const SizedBox(),
                           items: [
                             DropdownMenuItem(value: 'en', child: Text(AppLocalizations.of(context)!.english)),
                             DropdownMenuItem(value: 'id', child: Text(AppLocalizations.of(context)!.indonesian)),
                           ],
                           onChanged: (String? newValue) {
                             if (newValue != null) {
                               WaylandConnectApp.setLocale(context, Locale(newValue));
                             }
                           },
                         ),
                    ),
                    _buildSettingCard(
                      icon: Icons.power_settings_new_rounded,
                      title: AppLocalizations.of(context)!.startOnBoot,
                      subtitle: AppLocalizations.of(context)!.automateService,
                      trailing: Switch(
                        value: _startOnBoot,
                        onChanged: _toggleStartOnBoot,
                        activeColor: accentColor,
                        activeTrackColor: accentColor.withOpacity(0.2),
                      ),
                    ),
                    _buildSettingCard(
                      icon: Icons.sync_rounded,
                      title: AppLocalizations.of(context)!.autoConnect,
                      subtitle: AppLocalizations.of(context)!.autoConnectSubtitle,
                      trailing: Switch(
                        value: _autoConnect,
                        onChanged: _toggleAutoConnect,
                        activeColor: accentColor,
                        activeTrackColor: accentColor.withOpacity(0.2),
                      ),
                    ),
                    if (widget.socket != null)
                      _buildSettingCard(
                        icon: Icons.history_rounded,
                        title: AppLocalizations.of(context)!.autoReconnect,
                        subtitle: AppLocalizations.of(context)!.autoReconnectSubtitle,
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: OutlinedButton(
                            onPressed: () async {
                               final prefs = await SharedPreferences.getInstance();
                               final deviceId = prefs.getString('unique_device_id') ?? "android_test_id";
                               widget.socket!.add(ProtocolHandler.encodePacket({
                                 "type": "request_auto_reconnect",
                                 "data": {"id": deviceId}
                               }));
                               ScaffoldMessenger.of(context).showSnackBar(
                                 SnackBar(content: Text(AppLocalizations.of(context)!.approvalRequired))
                               );
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accentColor.withOpacity(0.3)),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.requestAutoReconnect,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    _buildSectionHeader(AppLocalizations.of(context)!.securityAccess),
                    _buildPermissionCard(
                      icon: Icons.notifications_active_rounded,
                      title: AppLocalizations.of(context)!.notifications,
                      subtitle: AppLocalizations.of(context)!.persistentLink,
                      isGranted: _notificationGranted,
                      accent: accentColor,
                      onTap: () async {
                        await Permission.notification.request();
                        _checkPermissions();
                      },
                    ),
                    _buildPermissionCard(
                      icon: Icons.battery_saver_rounded,
                      title: AppLocalizations.of(context)!.powerLogic,
                      subtitle: AppLocalizations.of(context)!.bypassBattery,
                      isGranted: _batteryOptimized,
                      accent: accentColor,
                      onTap: () async {
                        await Permission.ignoreBatteryOptimizations.request();
                        _checkPermissions();
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader(AppLocalizations.of(context)!.about),
                    _buildSettingCard(
                      icon: Icons.feedback_rounded,
                      title: AppLocalizations.of(context)!.sendFeedback,
                      subtitle: AppLocalizations.of(context)!.helpUsImprove,
                      trailing: const Icon(Icons.open_in_new_rounded, color: Colors.white24, size: 18),
                      onTap: () async {
                        final url = Uri.parse('https://aofsnorth.github.io/WaylandConnect/feedback/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const SizedBox(height: 60),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "WAYLAND CONNECT v1.0.1",
                              style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 3),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text("DEVELOPED BY ARTHENYX", style: TextStyle(color: Colors.white10, fontSize: 7, letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ]),
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

  Widget _buildSettingCard({required IconData icon, required String title, required String subtitle, required Widget trailing, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  Widget _buildPermissionCard({required IconData icon, required String title, required String subtitle, required bool isGranted, required VoidCallback onTap, required Color accent}) {
    return GestureDetector(
      onTap: isGranted ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isGranted ? accent.withOpacity(0.05) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isGranted ? accent.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isGranted ? accent.withOpacity(0.1) : Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: Icon(icon, color: isGranted ? accent : Colors.white70, size: 20),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            if (isGranted)
              Icon(Icons.check_circle_rounded, color: accent, size: 20)
            else
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}
