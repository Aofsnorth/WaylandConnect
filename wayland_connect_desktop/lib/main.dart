import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'dart:async';
import './utils/protocol.dart';
import 'l10n/app_localizations.dart';
import 'package:crypto/crypto.dart';

// ignore: must_be_immutable
class _SidebarItem extends StatelessWidget {
  final bool isSmall;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.isSmall,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: isSmall ? 10 : 20),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected ? Border.all(color: Colors.white12) : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: isSmall ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.white38, size: 20),
              if (!isSmall) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label, 
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white38, 
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

Future<String> _getIconPath() async {
  try {
    const path = '/tmp/wayland_connect_icon_extracted.png';
    final file = File(path);
    if (await file.exists()) return path;
    final byteData = await rootBundle.load('assets/images/app_icon.png');
    final buffer = byteData.buffer;
    await file.writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return path;
  } catch (e) {
    debugPrint("Icon extraction error: $e");
    return "";
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  bool startHidden = args.contains('--hidden');

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    final iconPath = await _getIconPath();
    if (iconPath.isNotEmpty) await windowManager.setIcon(iconPath);
    if (!startHidden) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(const WaylandManagerApp());
}

class WaylandManagerApp extends StatefulWidget {
  const WaylandManagerApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _WaylandManagerAppState? state = context.findAncestorStateOfType<_WaylandManagerAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<WaylandManagerApp> createState() => _WaylandManagerAppState();
}

class _WaylandManagerAppState extends State<WaylandManagerApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final String? languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      setState(() {
        _locale = Locale(languageCode);
      });
    }
  }

  void setLocale(Locale newLocale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', newLocale.languageCode);
    setState(() {
      _locale = newLocale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WaylandConnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white54,
          surface: Color(0xFF121212),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TrayListener, WindowListener {
  int _selectedIndex = 0; // 0: Dashboard, 1: Devices, 2: Security, 3: Settings
  bool _serviceActive = true;
  Socket? _socket;
  Process? _backendProcess;
  Process? _overlayProcess;
  List<Map<String, dynamic>> _devices = [];
  bool _isConnected = false;
  bool _zoomEnabled = false;
  Timer? _pollTimer;
  final ProtocolHandler _protocolHandler = ProtocolHandler();

  String _ipAddress = "Loading..."; // Initial value, will be replaced by l10n in build if needed, but logic uses it for stats.

  // Mock Settings
  bool _startOnBoot = false;
  bool _minimizeToTray = true;
  bool _darkMode = true;
  bool _autoConnect = true;
  bool _requireApproval = true;
  bool _encryptionEnabled = true;
  int _selectedMonitor = 0;
  List<Display> _monitors = [];
  final TextEditingController _portController = TextEditingController(text: "12345");

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initSystemTray();
    _loadSettings().then((_) {
      _loadMonitors();
      _startBackendServer();
      _connectToBackend();
      _getIpAddress();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus());
    });
  }

  Future<void> _loadMonitors() async {
    try {
      List<Display> displays = await screenRetriever.getAllDisplays();
      if (mounted) {
        setState(() {
          _monitors = displays;
          // Ensure selected monitor index is valid
          if (_selectedMonitor >= _monitors.length) {
            _selectedMonitor = 0;
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load monitors: $e");
    }
  }

  Future<void> _getIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('docker') || interface.name.contains('br-')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => _ipAddress = addr.address);
            return;
          }
        }
      }
      if (mounted) setState(() => _ipAddress = "127.0.0.1");
    } catch (_) {
      if (mounted) setState(() => _ipAddress = "Unknown");
    }
  }

  Future<void> _setAutoStart(bool enable) async {
    setState(() => _startOnBoot = enable);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('start_on_boot', enable);

    if (Platform.isLinux) {
      try {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final autostartDir = Directory('$home/.config/autostart');
          if (!await autostartDir.exists()) {
             await autostartDir.create(recursive: true);
          }
          final file = File('$home/.config/autostart/com.arthenyx.wayland_connect.desktop');
          
          if (enable) {
             // Create .desktop file for autostart
             // Note: We point to the AppImage or binary if installed. 
             // Ideally this should point to the installed `wayland_connect_desktop` command.
             // For now we assume it's in PATH or installed via install.sh to /usr/bin or /opt
             const content = '''
[Desktop Entry]
Type=Application
Name=Wayland Connect
Exec=wayland-connect --hidden
Icon=com.arthenyx.wayland_connect
Comment=Start Wayland Connect Server
X-GNOME-Autostart-enabled=true
''';
             await file.writeAsString(content);
          } else {
             if (await file.exists()) {
               await file.delete();
             }
          }
        }
      } catch (e) {
        debugPrint("Failed to toggle autostart: $e");
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _portController.text = prefs.getString('service_port') ?? "12345";
        _selectedMonitor = prefs.getInt('selected_monitor') ?? 0;
        _startOnBoot = prefs.getBool('start_on_boot') ?? false;
        _minimizeToTray = prefs.getBool('minimize_to_tray') ?? true;
        _darkMode = prefs.getBool('dark_mode') ?? true;
        _autoConnect = prefs.getBool('auto_connect') ?? true;
      });
    }
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _backendProcess?.kill();
    _overlayProcess?.kill();
    _pollTimer?.cancel();
    _socket?.destroy();
    super.dispose();
  }
  
  // ... [Tray/Window/Backend/Connection Logic remains same, omitting to save tokens, assume it's there or user can see it's needed. Wait, I must provide full replacement content if I replace the whole class or block.]
  
  // I will assume I need to PROVIDE ALL logic again if I replace.
  // To save space/tokens, I will only replace the BUILD method and add variables/helper methods.
  // But since I need to change `_SidebarItem` callbacks, I need to change the Sidebar construction in `build`.
  
  // Let's implement the full build method replacement first with internal helper methods.
  
  // ... [Previous logic helpers: _initSystemTray, onTray..., _startBackendServer, _connectToBackend, _refreshStatus, _approveDevice, _rejectDevice]
  
  // Since I cannot use "..." in replacement, I will try to target ONLY the `build` method and `_SidebarItem` class. 
  // But I need `_selectedIndex` in state. 
  
  // Strategy:
  // 1. Add `int _selectedIndex = 0;` and settings vars to State.
  // 2. Replace `build` method to support switching views.
  
  // Wait, I can't easily injection variables into the class without replacing the class body start.
  // I'll do a focused replace on the class start to add variables.
  
  // SKIP to actual tool usage.
  
  // Step 1: Add variables.
  // Step 2: Replace build.
  
  // Actually, I can replace the whole file content efficiently if I just copy-paste the whole thing with changes. 
  // But that's 600 lines. 
  
  // Let's just modify the `_DashboardScreenState` class start and the `build` method.
  
  // I'll do this in one go? No.
  
  // I will replace `class _DashboardScreenState ... {` start to add variables.
  // Then replace `Widget build` to implement navigation.


  
  // Tray & Window Logic
  Future<void> _initSystemTray() async {
    String iconPath = await _getIconPath();
    debugPrint("TRAY_ICON_PATH: $iconPath");
    if (iconPath.isNotEmpty) {
       await trayManager.setIcon(iconPath);
       await windowManager.setIcon(iconPath); // Set taskbar icon
    }
    
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: AppLocalizations.of(context)!.restoreWindow,
        ),
        MenuItem(
          key: 'hide_window',
          label: AppLocalizations.of(context)!.minimizeWindow,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: AppLocalizations.of(context)!.exit,
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }
  
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
    } else if (menuItem.key == 'hide_window') {
      windowManager.hide();
    } else if (menuItem.key == 'exit_app') {
      _backendProcess?.kill();
      _overlayProcess?.kill();
      exit(0);
    }
  }

  @override
  void onWindowClose() async {
    // Minimize to tray instead of closing
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  @override
  void onWindowMinimize() {
     windowManager.hide();
  }

  void _startBackendServer() async {
     try {
       int port = int.tryParse(_portController.text) ?? 12345;
       
       // Try to connect FIRST before doing anything
       try {
         final testSocket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 500));
         testSocket.destroy();
         debugPrint("📡 Backend already running on port $port, skipping spawn.");
         _connectToBackend();
         return;
       } catch (_) {
         // Port is free or backend not responding, proceed with spawning
       }

       _backendProcess?.kill();
       await Future.delayed(const Duration(milliseconds: 200)); 
       
       final prefs = await SharedPreferences.getInstance();
       await prefs.setString('service_port', port.toString());
       
       // Detect Path
       String exeDir = File(Platform.resolvedExecutable).parent.path;
       String backendPath = '$exeDir/wayland_connect_backend';
       String overlayPath = '$exeDir/wayland_pointer_overlay';

       // Local Development Paths (Source Tree)
       if (!File(backendPath).existsSync()) {
          final possiblePaths = [
            'target/release/wayland_connect_backend',
            'target/debug/wayland_connect_backend',
            '../target/release/wayland_connect_backend',
            '../target/debug/wayland_connect_backend',
            'rust_backend/target/release/wayland_connect_backend',
            'rust_backend/target/debug/wayland_connect_backend',
            '../rust_backend/target/release/wayland_connect_backend',
            '../rust_backend/target/debug/wayland_connect_backend',
            'build/linux/x64/debug/bundle/wayland_connect_backend',
            'build/linux/x64/release/bundle/wayland_connect_backend',
            '/opt/wayland-connect/bin/wayland_connect_backend',
          ];
          for (final p in possiblePaths) {
            if (File(p).existsSync()) {
              backendPath = p;
              overlayPath = p.replaceAll('wayland_connect_backend', 'wayland_pointer_overlay');
              break;
            }
          }
       }

       debugPrint("🚀 Attempting to launch Backend from: $backendPath");
       
       if (File(backendPath).existsSync()) {
          _backendProcess = await Process.start(backendPath, [port.toString()]);
          _backendProcess?.stdout.transform(utf8.decoder).listen((data) => debugPrint("[BACKEND]: $data"));
          _backendProcess?.stderr.transform(utf8.decoder).listen((data) => debugPrint("[BACKEND ERROR]: $data"));
          
          // Optimized: Poll for connection instead of hard sleep
          int attempts = 0;
          while (attempts < 15) { // Try for 3 seconds (15 * 200ms)
            await Future.delayed(const Duration(milliseconds: 200));
            try {
              final test = await SecureSocket.connect(
                '127.0.0.1', 
                port, 
                timeout: const Duration(milliseconds: 200),
                onBadCertificate: (_) => true,
              );
              test.destroy();
              _connectToBackend(); // Success!
              break;
            } catch (_) {
              attempts++;
            }
          }
       } else {
      debugPrint("❌ CRITICAL: Backend binary NOT FOUND.");
          // Attempt connection anyway in case it was started externally just now
          _connectToBackend();
       }

       if (File(overlayPath).existsSync()) {
          _overlayProcess = await Process.start(overlayPath, []);
          _overlayProcess?.stdout.transform(utf8.decoder).listen((data) => debugPrint("[OVERLAY]: $data"));
          _overlayProcess?.stderr.transform(utf8.decoder).listen((data) => debugPrint("[OVERLAY ERROR]: $data"));
       }

     } catch (e) {
       debugPrint("Failed to start backend: $e");
     }
  }

  void _connectToBackend() async {
    _socket?.close();
    
    int port = int.tryParse(_portController.text) ?? 12345;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final expectedFingerprint = prefs.getString('backend_fingerprint');

      _socket = await SecureSocket.connect(
        '127.0.0.1', 
        port,
        onBadCertificate: (certificate) {
          final hash = sha256.convert(certificate.der).toString().toUpperCase();
          final formattedHash = hash.replaceAllMapped(RegExp(r".{2}"), (match) => "${match.group(0)}:").substring(0, hash.length + (hash.length / 2).floor() - 1);
          
          if (expectedFingerprint != null && expectedFingerprint.isNotEmpty) {
             if (expectedFingerprint == formattedHash) {
                return true;
             } else {
                debugPrint("🚨 BACKEND IDENTITY CHANGED! Expected: $expectedFingerprint, Got: $formattedHash");
                return false;
             }
          }
          // First time, pin it
          prefs.setString('backend_fingerprint', formattedHash);
          debugPrint("📌 Pinned Local Backend Fingerprint: $formattedHash");
          return true;
        },
      );
      if (mounted) setState(() => _isConnected = true);
      
      // Mark this connection as a dashboard so it receives broadcasts
      _socket!.add(ProtocolHandler.encodePacket({'type': 'register_dashboard'}));
      
      _socket!.listen(
        (data) {
          try {
            final packets = _protocolHandler.process(data);
            for (final packet in packets) {
              if (packet is! Map) continue;
              
              final type = packet['type']?.toString();
              final d = packet['data'];
              
              if (type == 'status_response') {
                final devices = d['devices'];
                final zoomEnabled = d['zoom_enabled'] as bool?;
                if (mounted) {
                  setState(() {
                    if (devices != null) {
                      _devices = List<Map<String, dynamic>>.from(
                        (devices as List).map((x) => Map<String, dynamic>.from(x as Map))
                      );
                    }
                    if (zoomEnabled != null) {
                      _zoomEnabled = zoomEnabled;
                    }
                  });
                }
              } else if (type == 'mirror_request') {
                final deviceId = d['device_id']?.toString();
                final deviceName = d['device_name']?.toString() ?? "Unknown Device";
                if (deviceId != null) {
                  windowManager.show();
                  windowManager.focus();
                  _showMirrorRequestDialog(deviceId, deviceName);
                }
              } else if (type == 'auto_reconnect_request') {
                final deviceId = d['device_id']?.toString();
                final deviceName = d['device_name']?.toString() ?? "Unknown Device";
                if (deviceId != null) {
                  windowManager.show();
                  windowManager.focus();
                  _showAutoReconnectRequestDialog(deviceId, deviceName);
                }
              }
            }
          } catch (e) {
            debugPrint("Protocol Decode Error in Desktop: $e");
          }
        },
        onDone: () { if (mounted) setState(() => _isConnected = false); },
        onError: (e) { if (mounted) setState(() => _isConnected = false); },
        cancelOnError: true,
      );

      _refreshStatus();
      _syncMonitor();
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _syncMonitor() {
    if (_socket != null) {
      final event = {
        "type": "set_pointer_monitor",
        "data": {"monitor": _selectedMonitor}
      };
      _socket!.add(ProtocolHandler.encodePacket(event));
    }
  }

  void _showMirrorRequestDialog(String deviceId, String deviceName) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Mirror Request",
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return DraggablePopup(
          title: AppLocalizations.of(context)!.mirroringRequest,
          content: "'$deviceName' ${AppLocalizations.of(context)!.wantsToShareScreen}",
          onAccept: () {
            Navigator.pop(context);
            _sendMirrorResponse(deviceId, true);
          },
          onReject: () {
            Navigator.pop(context);
            _sendMirrorResponse(deviceId, false);
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * anim1.value, sigmaY: 10 * anim1.value),
          child: ScaleTransition(
            scale: curve,
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          ),
        );
      },
    );
  }

  void _sendMirrorResponse(String deviceId, bool accepted) {
    if (_socket != null) {
      final event = {
        "type": "mirror_response",
        "data": {
          "device_id": deviceId,
          "accepted": accepted,
        }
      };
      _socket!.add(ProtocolHandler.encodePacket(event));
    }
  }

  void _showAutoReconnectRequestDialog(String deviceId, String deviceName) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Auto Reconnect Request",
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return DraggablePopup(
          title: "Auto-Reconnect", 
          content: "'$deviceName' wants to enable auto-reconnect for future sessions.",
          onAccept: () {
            Navigator.pop(context);
            _sendAutoReconnectResponse(deviceId, true);
          },
          onReject: () {
            Navigator.pop(context);
            _sendAutoReconnectResponse(deviceId, false);
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * anim1.value, sigmaY: 10 * anim1.value),
          child: ScaleTransition(
            scale: curve,
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          ),
        );
      },
    );
  }

  void _sendAutoReconnectResponse(String deviceId, bool accepted) {
    if (_socket != null) {
      _socket!.add(ProtocolHandler.encodePacket({
        'type': 'auto_reconnect_response',
        'data': {'id': deviceId, 'accepted': accepted}
      }));
      _refreshStatus();
    }
  }

  void _sendPCStopMirroring(String deviceId) {
    if (_socket != null) {
      _socket!.add(ProtocolHandler.encodePacket({
        'type': 'pc_stop_mirroring',
        'data': {'id': deviceId}
      }));
      _refreshStatus();
    }
  }

  void _refreshStatus() {
    if (_socket != null) {
      final event = {"type": "get_status"};
      try { _socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
    }
  }

  void _approveDevice(String id) {
    if (_socket != null) {
      final event = {
        "type": "approve_device",
        "data": {"id": id}
      };
      _socket!.add(ProtocolHandler.encodePacket(event));
      _refreshStatus();
    }
  }
  
  void _rejectDevice(String id) {
     if (_socket != null) {
      final event = {
        "type": "reject_device",
        "data": {"id": id}
      };
      _socket!.add(ProtocolHandler.encodePacket(event));
      _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSmallScreen = constraints.maxWidth < 900;
        final double sidebarWidth = isSmallScreen ? 72.0 : 280.0;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              image: DecorationImage(
                image: AssetImage('assets/images/background.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  _darkMode ? Colors.black.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.1), 
                  _darkMode ? BlendMode.darken : BlendMode.lighten
                ),
              ),
            ),
            child: Row(
              children: [
                // Sidebar
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: sidebarWidth,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        border: const Border(right: BorderSide(color: Colors.white10)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 60),
                          // Logo
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: isSmallScreen 
                             ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.asset('assets/images/app_icon.png', width: 40, height: 40),
                               )
                             : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                 ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.asset('assets/images/app_icon.png', width: 40, height: 40),
                                ),
                                const SizedBox(height: 12),
                                const SizedBox(height: 12),
                                const Text("WAYLAND", style: TextStyle(fontFamily: 'Roboto', fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 4, color: Colors.white70)),
                                const SizedBox(height: 2),
                                Container(width: 40, height: 2, color: Colors.white),
                                const SizedBox(height: 4),
                                const Text("CONNECT", style: TextStyle(fontFamily: 'Roboto', fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40), // Reduced spacing
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.dashboard_outlined, label: AppLocalizations.of(context)!.dashboard, selected: _selectedIndex == 0, onTap: () => setState(() => _selectedIndex = 0)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.devices_other_outlined, label: AppLocalizations.of(context)!.pairedDevices, selected: _selectedIndex == 1, onTap: () => setState(() => _selectedIndex = 1)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.block, label: AppLocalizations.of(context)!.blockedDevices, selected: _selectedIndex == 4, onTap: () => setState(() => _selectedIndex = 4)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.security_outlined, label: AppLocalizations.of(context)!.securityTrust, selected: _selectedIndex == 2, onTap: () => setState(() => _selectedIndex = 2)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.settings_outlined, label: AppLocalizations.of(context)!.settings, selected: _selectedIndex == 3, onTap: () => setState(() => _selectedIndex = 3)),
                                ],
                              ),
                            ),
                          ),
                          // Version
                          Padding(
                            padding: const EdgeInsets.all(24), // Reduced padding
                            child: isSmallScreen
                             ? const Icon(Icons.info_outline, size: 18, color: Colors.white38)
                             : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.info_outline, size: 10, color: Colors.white38),
                                    const SizedBox(width: 6),
                                    Text("v1.0.0", style: TextStyle(
                                      color: Colors.white70, 
                                      fontSize: 10,
                                      shadows: [
                                        Shadow(color: Colors.blueAccent.withValues(alpha: 0.8), blurRadius: 15),
                                        Shadow(color: Colors.purpleAccent.withValues(alpha: 0.5), blurRadius: 25),
                                      ]
                                    )),
                                  ],
                                ),
                             ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Main Content Area
                Expanded(
                   child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          alignment: Alignment.topLeft,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.02, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        key: ValueKey(_selectedIndex),
                        padding: const EdgeInsets.all(24),
                        child: _buildContent(), 
                      ),
                   ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  void _toggleService() {
    setState(() {
      _serviceActive = !_serviceActive;
    });
    if (_serviceActive) {
      _initSystemTray(); // Ensure tray is fresh
      _startBackendServer();
      _connectToBackend();
    } else {
      _backendProcess?.kill();
      _socket?.close();
      _socket = null;
      setState(() => _isConnected = false);
    }
  }

  void _toggleAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_connect', value);
    setState(() => _autoConnect = value);
    
    if (_socket != null) {
      _socket!.add(ProtocolHandler.encodePacket({
        "type": "set_auto_connect",
        "data": {"enabled": value}
      }));
    }
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0: return _buildDashboard();
      case 1: return _buildDevices();
      case 2: return _buildSecurity();
      case 3: return _buildSettings();
      case 4: return _buildBlockedDevices();
      default: return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isVeryNarrow = constraints.maxWidth < 700;
            final double horizontalPadding = isVeryNarrow ? 12 : 24;
            final double topPadding = isVeryNarrow ? 12 : 24;

            return Padding(
              padding: EdgeInsets.only(left: horizontalPadding, right: horizontalPadding, top: topPadding, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                                child: Text(
                                AppLocalizations.of(context)!.dashboard, 
                                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(context)!.systemControlCenter,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(flex: 0, child: Row(
                        children: [
                          _StatusBadge(active: _serviceActive, isConnected: _isConnected),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Stats Section
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      // Calculate width based on constraints
                      // If very narrow: 1 column. If medium: 2 columns. If wide: 4 columns.
                      ...[
                        _StatCard(title: AppLocalizations.of(context)!.serverIp, value: _ipAddress == "Loading..." ? AppLocalizations.of(context)!.loading : _ipAddress, icon: Icons.wifi_tethering, highlight: true),
                        _StatCard(title: AppLocalizations.of(context)!.port, value: _portController.text, icon: Icons.lan),
                        _StatCard(title: AppLocalizations.of(context)!.paired, value: "${_devices.where((d) => d['status'] == 'Trusted').length}", icon: Icons.devices),
                        _StatCard(title: AppLocalizations.of(context)!.request, value: "${_devices.where((d) => d['status'] == 'Pending').length}", icon: Icons.verified_user_outlined),
                      ].map((card) {
                        double itemWidth;
                        double availableWidth = constraints.maxWidth - (horizontalPadding * 2);
                        if (availableWidth < 500) {
                          itemWidth = availableWidth; // 1 column
                        } else if (availableWidth < 950) {
                          itemWidth = (availableWidth - 16) / 2; // 2 columns
                        } else {
                          // Subtract a small epsilon to avoid subpixel wrapping issues
                          itemWidth = (availableWidth - (16 * 3)) / 4 - 0.1; // 4 columns
                        }
                        return SizedBox(
                          width: itemWidth.clamp(140.0, double.infinity), 
                          child: card
                        );
                      }).toList(),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Recent Activity Section
                  Text(AppLocalizations.of(context)!.recentActivity, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 12),
                  
                  _devices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.03),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.history, size: 48, color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              const SizedBox(height: 20),
                              Text(AppLocalizations.of(context)!.noRecentConnections, style: const TextStyle(color: Colors.white24, fontSize: 15, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 8),
                              Text(AppLocalizations.of(context)!.connectAndroidToGetStarted, style: const TextStyle(color: Colors.white10, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            return _DeviceRow(
                              id: device['id'],
                              name: device['name'] ?? "Unknown Device",
                              details: "${device['ip']} • ${device['id']}",
                              status: device['status'],
                              isMirroring: device['is_mirroring'] ?? false,
                              actions: [
                                if (device['is_mirroring'] == true) ...[
                                  TextButton(
                                    onPressed: () => _sendPCStopMirroring(device['id']),
                                    child: const Text("STOP", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                if (device['status'] == 'Pending') ...[
                                  TextButton(
                                    onPressed: () => _approveDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.approve, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  TextButton(
                                    onPressed: () => _rejectDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.reject, style: const TextStyle(color: Colors.white38)),
                                  ),
                                ] else if (device['status'] == 'Trusted') ...[
                                  TextButton(
                                    onPressed: () => _rejectDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.remove, style: const TextStyle(color: Colors.white60)),
                                  ),
                                  TextButton(
                                    onPressed: () => _blockDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.block, style: const TextStyle(color: Colors.redAccent)),
                                  ),
                                ] else if (device['status'] == 'Declined') ...[
                                  TextButton(
                                    onPressed: () => _approveDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.rePair, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                  ),
                                  TextButton(
                                    onPressed: () => _unblockDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.delete, style: const TextStyle(color: Colors.white38)),
                                  ),
                                ] else if (device['status'] == 'Blocked') ...[
                                  TextButton(
                                    onPressed: () => _unblockDevice(device['id']),
                                    child: Text(AppLocalizations.of(context)!.unblock, style: const TextStyle(color: Colors.amberAccent)),
                                  ),
                                ]
                              ],
                            );
                          },
                        ),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }


  Widget _buildDevices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.pairedDevices, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.manageDevicesAccess, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 40),
        Expanded(
          child: _devices.where((d) => d['status'] == 'Trusted').isEmpty 
          ? Center(child: Text(AppLocalizations.of(context)!.noPairedDevices, style: const TextStyle(color: Colors.white38)))
          : ListView.builder(
            itemCount: _devices.where((d) => d['status'] == 'Trusted').length,
            itemBuilder: (context, index) {
              final device = _devices.where((d) => d['status'] == 'Trusted').toList()[index];
              return _DeviceRow(
                id: device['id'],
                name: device['name'] ?? "Unknown",
                details: "ID: ${device['id']}\nIP: ${device['ip']}",
                status: device['status'] ?? "Unknown",
                isMirroring: device['is_mirroring'] ?? false,
                actions: [
                   if (device['is_mirroring'] == true) ...[
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                        child: const Text("STOP MIRRORING"),
                        onPressed: () => _sendPCStopMirroring(device['id']),
                      ),
                      const SizedBox(width: 8),
                   ],
                   OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white10)),
                      child: Text(AppLocalizations.of(context)!.remove),
                      onPressed: () => _rejectDevice(device['id']),
                   ),
                   const SizedBox(width: 8),
                   OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      child: Text(AppLocalizations.of(context)!.block),
                      onPressed: () => _blockDevice(device['id']),
                   )
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBlockedDevices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.blockedDevices, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.permanentlyBlocked, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 40),
        Expanded(
          child: _devices.where((d) => d['status'] == 'Blocked').isEmpty 
          ? Center(child: Text(AppLocalizations.of(context)!.noBlockedDevices, style: const TextStyle(color: Colors.white38)))
          : ListView.builder(
            itemCount: _devices.where((d) => d['status'] == 'Blocked').length,
            itemBuilder: (context, index) {
              final device = _devices.where((d) => d['status'] == 'Blocked').toList()[index];
              return _DeviceRow(
                id: device['id'] ?? "",
                name: device['name'] ?? "Unknown",
                details: "ID: ${device['id']}\nIP: ${device['ip']}",
                status: device['status'] ?? "Unknown",
                actions: [
                   FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      icon: const Icon(Icons.lock_open, size: 16),
                      label: Text(AppLocalizations.of(context)!.unblock),
                      onPressed: () => _unblockDevice(device['id']),
                   )
                ],
              );
            },
          ),
        ),
      ],
    );
  }
  
  void _blockDevice(String id) {
    if (_socket != null) {
      final event = {
        "type": "block_device",
        "data": {"id": id}
      };
      _socket!.add(ProtocolHandler.encodePacket(event));
      _refreshStatus();
    }
  }

  void _unblockDevice(String id) {
     if (_socket != null) {
      final event = {
        "type": "unblock_device",
        "data": {"id": id}
      };
      _socket!.add(ProtocolHandler.encodePacket(event));
      _refreshStatus();
    }
  }

  void _revokeAllAccess() {
    final trustedDevices = _devices.where((d) => d['status'] == 'Trusted').toList();
    for (var device in trustedDevices) {
      _rejectDevice(device['id']);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${AppLocalizations.of(context)!.revokedAccessFor} ${trustedDevices.length} ${AppLocalizations.of(context)!.devices}"))
    );
  }

  Widget _buildSecurity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.securityTrust, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _buildSwitch(AppLocalizations.of(context)!.requireApprovalNew, AppLocalizations.of(context)!.alwaysAskPairing, _requireApproval, (v) => setState(() => _requireApproval = v)),
        // Encryption is mandatory and enabled by default in backend v1.0.3+
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context)!.accessControl, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 16),
              Expanded(child: Text("${AppLocalizations.of(context)!.revokeAllAccess}\n${AppLocalizations.of(context)!.revokeAllDetails}", style: const TextStyle(color: Colors.red))),
              const SizedBox(width: 8),
              Flexible(
                flex: 0,
                child: OutlinedButton(
                  onPressed: _revokeAllAccess,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  child: Text(AppLocalizations.of(context)!.revokeAllBtn),
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      children: [
        Text(AppLocalizations.of(context)!.settings, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _buildSwitch(AppLocalizations.of(context)!.startOnBoot, AppLocalizations.of(context)!.startOnBootDetails, _startOnBoot, _setAutoStart),
        _buildSwitch(AppLocalizations.of(context)!.minimizeToTray, AppLocalizations.of(context)!.minimizeToTrayDetails, _minimizeToTray, (v) => setState(() => _minimizeToTray = v)),
        _buildSwitch(AppLocalizations.of(context)!.darkMode, AppLocalizations.of(context)!.darkModeDetails, _darkMode, (v) => setState(() => _darkMode = v)),
        _buildSwitch(AppLocalizations.of(context)!.autoConnect, AppLocalizations.of(context)!.autoConnectDetails, _autoConnect, _toggleAutoConnect),
        _buildSwitch(AppLocalizations.of(context)!.enableZoom, AppLocalizations.of(context)!.enableZoomDetails, _zoomEnabled, (v) {
          setState(() => _zoomEnabled = v);
          if (_socket != null) {
            _socket!.add(ProtocolHandler.encodePacket({
              "type": "set_zoom_enabled",
              "data": {"enabled": v}
            }));
          }
        }),
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context)!.language, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: Localizations.localeOf(context).languageCode,
              dropdownColor: const Color(0xFF1E1E1E),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: [
                DropdownMenuItem(value: 'en', child: Text(AppLocalizations.of(context)!.english)),
                DropdownMenuItem(value: 'id', child: Text(AppLocalizations.of(context)!.indonesian)),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  WaylandManagerApp.setLocale(context, Locale(newValue));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context)!.pointerOverlay, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(AppLocalizations.of(context)!.selectMonitorDetails, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedMonitor,
              dropdownColor: const Color(0xFF1E1E1E),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: _monitors.isEmpty 
              ? [DropdownMenuItem(value: 0, child: Text(AppLocalizations.of(context)!.detectingMonitors))]
              : _monitors.asMap().entries.map((entry) {
                  int idx = entry.key;
                  Display d = entry.value;
                  return DropdownMenuItem(
                    value: idx,
                    child: Text("${AppLocalizations.of(context)!.monitor} $idx: ${d.name} (${d.size.width.toInt()}x${d.size.height.toInt()})"),
                  );
                }).toList(),
              onChanged: (val) async {
                if (val != null) {
                  setState(() => _selectedMonitor = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('selected_monitor', val);
                  _syncMonitor();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(AppLocalizations.of(context)!.serverConfiguration, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.servicePort,
            labelStyle: const TextStyle(color: Colors.white54),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
            errorText: _portController.text.isEmpty ? AppLocalizations.of(context)!.portEmptyError : null,
          ),
          onChanged: (v) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _portController.text.isEmpty ? null : () => _startBackendServer(),
          icon: const Icon(Icons.restart_alt),
          label: Text(AppLocalizations.of(context)!.restartServiceApply),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
        ),
        const SizedBox(height: 48),
        Text(AppLocalizations.of(context)!.systemUpdate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.updateDetails, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse("https://github.com/Aofsnorth/WaylandConnect/releases/latest");
                        await Process.run('xdg-open', [url.toString()]);
                      },
                      icon: const Icon(Icons.system_update_alt),
                      label: Text(AppLocalizations.of(context)!.checkForUpdates),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        // For direct update, we could try running git pull and install.sh
                        // but opening the repo is safer for now as we don't know where it's cloned.
                        final url = Uri.parse("https://github.com/Aofsnorth/WaylandConnect");
                        await Process.run('xdg-open', [url.toString()]);
                      },
                      icon: const Icon(Icons.code),
                      label: Text(AppLocalizations.of(context)!.githubRepo),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: Colors.white, foregroundColor: Colors.black),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
  
  Widget _buildSwitch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: Colors.white)
        ],
      ),
    );
  }
}



class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool highlight;

  const _StatCard({required this.title, required this.value, required this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 180;
        final double cardPadding = isCompact ? 16 : 24;

        return Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: highlight 
                ? [Colors.blueAccent.withValues(alpha: 0.12), Colors.blueAccent.withValues(alpha: 0.04)]
                : [const Color(0xFF101010), const Color(0xFF080808)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlight ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: highlight ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: highlight ? Colors.blueAccent : Colors.white54, size: 32),
              ),
              SizedBox(height: isCompact ? 14 : 24),
              Text(title, 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, 
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 36, 
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                  )
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final String id;
  final String name;
  final String details;
  final String status;
  final List<Widget> actions;
  final bool isMirroring;

  const _DeviceRow({
    required this.id,
    required this.name,
    required this.details,
    required this.status,
    required this.actions,
    this.isMirroring = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTrusted = status == 'Trusted';
    final bool isPending = status == 'Pending';
    final bool isBlocked = status == 'Blocked';
    final bool isDeclined = status == 'Declined';

    return LayoutBuilder(
      builder: (context, constraints) {
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF080808).withValues(alpha: isDeclined ? 0.5 : 1.0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPending ? Colors.amber.withValues(alpha: 0.2) 
                   : (isBlocked ? Colors.red.withValues(alpha: 0.2) 
                   : (isDeclined ? Colors.white10 : Colors.white.withValues(alpha: 0.05)))
            ),
          ),
          child: Row(
            children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.amber.withValues(alpha: 0.1) 
                         : (isBlocked ? Colors.red.withValues(alpha: 0.1) 
                         : (isDeclined ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.03))),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPending ? Icons.warning_amber_rounded 
                    : (isBlocked ? Icons.block 
                    : (isDeclined ? Icons.cancel : Icons.smartphone)), 
                    color: isPending ? Colors.amber 
                         : (isBlocked ? Colors.red 
                         : (isDeclined ? Colors.red : Colors.white)), 
                    size: 20
                  ),
                ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name, 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              color: isDeclined ? Colors.white38 : Colors.white,
                            )
                          ),
                        ),
                        if (isPending) 
                          Flexible(
                            flex: 0,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: _StatusChip(label: "REQUEST", color: Colors.amber),
                            ),
                          ),
                        if (isBlocked) 
                          Flexible(
                            flex: 0,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: _StatusChip(label: "BLOCKED", color: Colors.red),
                            ),
                          ),
                        if (isDeclined)
                          Flexible(
                            flex: 0,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: _StatusChip(label: "REMOVED", color: Colors.white10, textColor: Colors.white38),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(details, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 0.5)
                    ),
                    if (isMirroring) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cast_connected, color: Colors.greenAccent, size: 12),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "SCREEN MIRRORING ACTIVE",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.greenAccent.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: actions.map((action) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: action,
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  final bool isConnected;
  const _StatusBadge({required this.active, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    Color mainColor = Colors.red;
    String text = "SERVICE STOPPED";
    bool showGlow = active;

    if (active) {
      if (isConnected) {
        mainColor = Colors.white;
        text = "SERVICE ACTIVE";
      } else {
        mainColor = Colors.amberAccent;
        text = "SEARCHING BACKEND...";
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // For very small widths, show only the dot indicator
        final bool isTiny = constraints.maxWidth < 80;
        
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isTiny ? 8 : 16, 
            vertical: isTiny ? 6 : 8
          ),
          decoration: BoxDecoration(
            color: mainColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: mainColor.withValues(alpha: 0.3)),
            boxShadow: showGlow ? [
               BoxShadow(color: mainColor.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 1),
               if (isConnected) BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5),
            ] : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: mainColor,
                  shape: BoxShape.circle,
                  boxShadow: showGlow ? [
                     BoxShadow(color: mainColor.withValues(alpha: 0.8), blurRadius: 8, spreadRadius: 2),
                  ] : [],
                ),
              ),
              if (!isTiny) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mainColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      shadows: (active && isConnected) ? [
                         Shadow(color: Colors.blueAccent, blurRadius: 10),
                      ] : [],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;

  const _StatusChip({required this.label, required this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class DraggablePopup extends StatefulWidget {
  final String title;
  final String content;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const DraggablePopup({
    super.key,
    required this.title,
    required this.content,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<DraggablePopup> createState() => _DraggablePopupState();
}

class _DraggablePopupState extends State<DraggablePopup> {
  Offset? _position; 
  final double _width = 380;
  final double _estimatedHeight = 240; 
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_position == null) {
      final size = MediaQuery.of(context).size;
      _position = Offset((size.width - _width) / 2, (size.height - _estimatedHeight) / 2);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_position == null) return const SizedBox.shrink();
    
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: _position!.dx,
            top: _position!.dy,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                setState(() {
                  final screenSize = MediaQuery.of(context).size;
                  
                  double newX = _position!.dx + details.delta.dx;
                  double newY = _position!.dy + details.delta.dy;
        
                  const double bottomBarHeight = 100.0;
                  final double horizontalLimit = (screenSize.width - _width).clamp(0.0, double.infinity);
                  final double verticalLimit = (screenSize.height - _estimatedHeight - bottomBarHeight).clamp(0.0, double.infinity);
        
                  _position = Offset(
                    newX.clamp(0.0, horizontalLimit),
                    newY.clamp(0.0, verticalLimit),
                  );
                });
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _width,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.cast_connected_rounded, color: Colors.blueAccent, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "SCREEN SHARE REQUEST",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      "SECURE LINK PENDING",
                                      style: TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.content,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: widget.onReject,
                              icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                              label: const Text("DECLINE", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, letterSpacing: 1)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: widget.onAccept,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text("APPROVE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: Colors.blueAccent.withValues(alpha: 0.4),
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
