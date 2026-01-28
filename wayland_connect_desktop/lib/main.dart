import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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

class WaylandManagerApp extends StatelessWidget {
  const WaylandManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wayland Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white54,
          surface: Color(0xFF121212),
        ),
        fontFamily: 'Roboto',
      ),
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
  SecureSocket? _socket;
  Process? _backendProcess;
  Process? _overlayProcess;
  List<Map<String, dynamic>> _devices = [];
  bool _isConnected = false;
  Timer? _pollTimer;

  String _ipAddress = "Loading...";

  // Mock Settings
  bool _startOnBoot = false;
  bool _minimizeToTray = true;
  bool _darkMode = true;
  bool _requireApproval = true;
  bool _encryptionEnabled = true;
  int _selectedMonitor = 0;
  final TextEditingController _portController = TextEditingController(text: "12345");

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initSystemTray();
    _loadSettings().then((_) {
      _startBackendServer();
      _connectToBackend();
      _getIpAddress();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus());
    });
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _portController.text = prefs.getString('service_port') ?? "12345";
        _selectedMonitor = prefs.getInt('selected_monitor') ?? 0;
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
          label: 'Restore Window',
        ),
        MenuItem(
          key: 'hide_window',
          label: 'Minimize Window',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Exit',
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
       // Force kill any existing backend instances (zombies)
       await Process.run('fuser', ['-k', '12345/tcp']);
       await Process.run('pkill', ['-f', 'wayland_connect_backend']);
       await Process.run('pkill', ['-f', 'wayland_pointer_overlay']); 
       _backendProcess?.kill();
       await Future.delayed(const Duration(milliseconds: 500)); 
       
       int port = int.tryParse(_portController.text) ?? 12345;
       final prefs = await SharedPreferences.getInstance();
       await prefs.setString('service_port', port.toString());
       
       // Detect Path
       // 1. Check relative to executable (AppImage / Portable uses this)
       String exeDir = File(Platform.resolvedExecutable).parent.path;
       String backendPath = '$exeDir/wayland_connect_backend';
       String overlayPath = '$exeDir/wayland_pointer_overlay';

       if (!File(backendPath).existsSync()) {
          // 2. Check /opt (Legacy/Global Install)
          String optBackend = '/opt/wayland-connect/bin/wayland_connect_backend';
          if (File(optBackend).existsSync()) {
              backendPath = optBackend;
              overlayPath = '/opt/wayland-connect/bin/wayland_pointer_overlay';
          }
       }

       if (!File(backendPath).existsSync()) {
          // 3. Fallbacks for local dev (Source Tree)
          backendPath = '../rust_backend/target/release/wayland_connect_backend';
          overlayPath = '../wayland_pointer_overlay/target/release/wayland_pointer_overlay';
          
          if (!File(backendPath).existsSync()) {
             backendPath = '../rust_backend/target/debug/wayland_connect_backend';
             overlayPath = '../wayland_pointer_overlay/target/debug/wayland_pointer_overlay';
          }

          if (!File(backendPath).existsSync()) {
             // For running via 'flutter run' where CWD is project root
             backendPath = 'rust_backend/target/release/wayland_connect_backend';
             overlayPath = 'wayland_pointer_overlay/target/release/wayland_pointer_overlay';
             
             if (!File(backendPath).existsSync()) {
                backendPath = 'rust_backend/target/debug/wayland_connect_backend';
                overlayPath = 'wayland_pointer_overlay/target/debug/wayland_pointer_overlay'; 
             }
          }
       }

       debugPrint("🚀 Attempting to launch Backend from: $backendPath");
       
       // Start Backend
       if (File(backendPath).existsSync()) {
          _backendProcess = await Process.start(backendPath, [port.toString()]);
          debugPrint("✅ Backend process started (PID: ${_backendProcess?.pid})");
          
          _backendProcess?.stdout.transform(utf8.decoder).listen((data) => debugPrint("[BACKEND]: $data"));
          _backendProcess?.stderr.transform(utf8.decoder).listen((data) => debugPrint("[BACKEND ERROR]: $data"));
          
          Future.delayed(const Duration(milliseconds: 800), _connectToBackend);
       } else {
          debugPrint("❌ CRITICAL: Backend binary NOT FOUND at $backendPath");
       }

       // Start Overlay
       if (File(overlayPath).existsSync()) {
          Process.start(overlayPath, []).then((p) {
             _overlayProcess = p;
             debugPrint("✅ Overlay process started (PID: ${p.pid})");
          });
       } else {
          debugPrint("⚠️ Overlay binary NOT FOUND at $overlayPath");
       }

     } catch (e) {
       debugPrint("Failed to start backend: $e");
     }
  }

  void _connectToBackend() async {
    _socket?.close();
    
    int port = int.tryParse(_portController.text) ?? 12345;
    
    try {
      _socket = await SecureSocket.connect(
        '127.0.0.1', 
        port,
        onBadCertificate: (cert) => true, // Self-signed support
      );
      if (mounted) setState(() => _isConnected = true);
      
      utf8.decoder.bind(_socket!).transform(const LineSplitter()).listen(
        (line) {
          if (line.isEmpty) return;
          try {
            final json = jsonDecode(line);
            if (json['devices'] != null) {
               if (mounted) {
                 setState(() {
                   _devices = List<Map<String, dynamic>>.from(json['devices']);
                 });
               }
            }
          } catch (e) {
            debugPrint("JSON Decode Error in Desktop: $e | Line: $line");
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
      _socket!.write('{"type":"set_pointer_monitor", "data": {"monitor": $_selectedMonitor}}\n');
    }
  }

  void _refreshStatus() {
    if (_socket != null) {
      try { _socket!.write('{"type":"get_status", "data": null}\n'); } catch (_) {}
    }
  }

  void _approveDevice(String id) {
    if (_socket != null) {
      _socket!.write('{"type":"approve_device", "data": {"id": "$id"}}\n');
      _refreshStatus();
    }
  }
  
  void _rejectDevice(String id) {
     if (_socket != null) {
      _socket!.write('{"type":"reject_device", "data": {"id": "$id"}}\n');
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
                  _darkMode ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.1), 
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
                        color: Colors.black.withOpacity(0.6),
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
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.dashboard_outlined, label: "Dashboard", selected: _selectedIndex == 0, onTap: () => setState(() => _selectedIndex = 0)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.devices_other_outlined, label: "Paired Devices", selected: _selectedIndex == 1, onTap: () => setState(() => _selectedIndex = 1)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.block, label: "Blocked Devices", selected: _selectedIndex == 4, onTap: () => setState(() => _selectedIndex = 4)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.security_outlined, label: "Security & Trust", selected: _selectedIndex == 2, onTap: () => setState(() => _selectedIndex = 2)),
                                  _SidebarItem(isSmall: isSmallScreen, icon: Icons.settings_outlined, label: "Settings", selected: _selectedIndex == 3, onTap: () => setState(() => _selectedIndex = 3)),
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
                                        Shadow(color: Colors.blueAccent.withOpacity(0.8), blurRadius: 15),
                                        Shadow(color: Colors.purpleAccent.withOpacity(0.5), blurRadius: 25),
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
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                                child: Text(
                                "Dashboard", 
                                style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)
                              ),
                            ),
                            Text(
                              "System Control Center",
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _StatusBadge(active: _serviceActive),
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
                        _StatCard(title: "Server IP", value: _ipAddress, icon: Icons.wifi_tethering, highlight: true),
                        _StatCard(title: "Port", value: _portController.text, icon: Icons.lan),
                        _StatCard(title: "Paired", value: "${_devices.where((d) => d['status'] == 'Trusted').length}", icon: Icons.devices),
                        _StatCard(title: "Request", value: "${_devices.where((d) => d['status'] == 'Pending').length}", icon: Icons.verified_user_outlined),
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
                  const Text("Recent Activity", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 12),
                  
                  _devices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.03),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.history, size: 48, color: Colors.white.withOpacity(0.1)),
                              ),
                              const SizedBox(height: 20),
                              const Text("No Recent Connections", style: TextStyle(color: Colors.white24, fontSize: 15, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 8),
                              const Text("Connect your Android device to get started", style: TextStyle(color: Colors.white10, fontSize: 13)),
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
                              name: device['name'] ?? "Unknown Device",
                              details: "${device['ip']} • ${device['id']}",
                              status: device['status'],
                              actions: [
                                if (device['status'] == 'Pending') ...[
                                  TextButton(
                                    onPressed: () => _approveDevice(device['id']),
                                    child: const Text("Approve", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  TextButton(
                                    onPressed: () => _rejectDevice(device['id']),
                                    child: const Text("Reject", style: TextStyle(color: Colors.white38)),
                                  ),
                                ] else if (device['status'] == 'Trusted') ...[
                                  TextButton(
                                    onPressed: () => _rejectDevice(device['id']),
                                    child: const Text("Remove", style: TextStyle(color: Colors.white60)),
                                  ),
                                  TextButton(
                                    onPressed: () => _blockDevice(device['id']),
                                    child: const Text("Block", style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ] else if (device['status'] == 'Declined') ...[
                                  TextButton(
                                    onPressed: () => _approveDevice(device['id']),
                                    child: const Text("Re-pair", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                  ),
                                  TextButton(
                                    onPressed: () => _unblockDevice(device['id']),
                                    child: const Text("Delete", style: TextStyle(color: Colors.white38)),
                                  ),
                                ] else if (device['status'] == 'Blocked') ...[
                                  TextButton(
                                    onPressed: () => _unblockDevice(device['id']),
                                    child: const Text("Unblock", style: TextStyle(color: Colors.amberAccent)),
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
        const Text("Paired Devices", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text("Manage all devices that have access to this PC.", style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 40),
        Expanded(
          child: _devices.where((d) => d['status'] == 'Trusted').isEmpty 
          ? const Center(child: Text("No paired devices", style: TextStyle(color: Colors.white38)))
          : ListView.builder(
            itemCount: _devices.where((d) => d['status'] == 'Trusted').length,
            itemBuilder: (context, index) {
              final device = _devices.where((d) => d['status'] == 'Trusted').toList()[index];
              return _DeviceRow(
                name: device['name'] ?? "Unknown",
                details: "ID: ${device['id']}\nIP: ${device['ip']}",
                status: device['status'] ?? "Unknown",
                actions: [
                   OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white10)),
                      child: const Text("Remove"),
                      onPressed: () => _rejectDevice(device['id']),
                   ),
                   const SizedBox(width: 8),
                   OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      child: const Text("Block"),
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
        const Text("Blocked Devices", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text("Devices that are permanently blocked from connecting.", style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 40),
        Expanded(
          child: _devices.where((d) => d['status'] == 'Blocked').isEmpty 
          ? const Center(child: Text("No blocked devices", style: TextStyle(color: Colors.white38)))
          : ListView.builder(
            itemCount: _devices.where((d) => d['status'] == 'Blocked').length,
            itemBuilder: (context, index) {
              final device = _devices.where((d) => d['status'] == 'Blocked').toList()[index];
              return _DeviceRow(
                name: device['name'] ?? "Unknown",
                details: "ID: ${device['id']}\nIP: ${device['ip']}",
                status: device['status'] ?? "Unknown",
                actions: [
                   FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      icon: const Icon(Icons.lock_open, size: 16),
                      label: const Text("Unblock"),
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
      _socket!.write('{"type":"block_device", "data": {"id": "$id"}}\n');
      _refreshStatus();
    }
  }

  void _unblockDevice(String id) {
     if (_socket != null) {
      _socket!.write('{"type":"unblock_device", "data": {"id": "$id"}}\n');
      _refreshStatus();
    }
  }

  void _revokeAllAccess() {
    final trustedDevices = _devices.where((d) => d['status'] == 'Trusted').toList();
    for (var device in trustedDevices) {
      _rejectDevice(device['id']);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Revoked access for ${trustedDevices.length} devices"))
    );
  }

  Widget _buildSecurity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Security & Trust", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _buildSwitch("Require Approval for New Devices", "Always ask before pairing a new device.", _requireApproval, (v) => setState(() => _requireApproval = v)),
        _buildSwitch("Enable Encryption (TLS)", "Encrypt all communication. (Requires certificates)", _encryptionEnabled, (v) => setState(() => _encryptionEnabled = v)),
        const SizedBox(height: 24),
        const Text("Access Control", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 16),
              const Expanded(child: Text("Revoke All Access\nDisconnect all devices and clear trust database.", style: TextStyle(color: Colors.red))),
              OutlinedButton(
                onPressed: _revokeAllAccess,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                child: const Text("REVOKE ALL"),
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
        const Text("Settings", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _buildSwitch("Start on Boot", "Automatically start server when you login.", _startOnBoot, (v) => setState(() => _startOnBoot = v)),
        _buildSwitch("Minimize to Tray", "Keep running in background when closed.", _minimizeToTray, (v) => setState(() => _minimizeToTray = v)),
        _buildSwitch("Dark Mode", "Use dark theme for dashboard.", _darkMode, (v) => setState(() => _darkMode = v)),
        const SizedBox(height: 24),
        const Text("Pointer Overlay", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text("Select which monitor the laser pointer should appear on.", style: TextStyle(color: Colors.white54, fontSize: 13)),
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
              items: const [
                DropdownMenuItem(value: 0, child: Text("Main Monitor (0)")),
                DropdownMenuItem(value: 1, child: Text("Second Monitor (1)")),
                DropdownMenuItem(value: 2, child: Text("Third Monitor (2)")),
              ],
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
        const Text("Server Configuration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            labelText: "Service Port",
            labelStyle: const TextStyle(color: Colors.white54),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white24)),
            errorText: _portController.text.isEmpty ? "Port cannot be empty" : null,
          ),
          onChanged: (v) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _portController.text.isEmpty ? null : () => _startBackendServer(),
          icon: const Icon(Icons.restart_alt),
          label: const Text("Restart Service & Apply Port"),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
        )
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

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isSmall;

  const _SidebarItem({required this.icon, required this.label, this.selected = false, required this.onTap, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 24, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? Colors.white : Colors.transparent, 
          boxShadow: selected ? [
             BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 15, spreadRadius: 1),
             BoxShadow(color: Colors.blueAccent.withOpacity(0.1), blurRadius: 25, spreadRadius: 2),
          ] : [],
        ),
        child: isSmall 
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
               height: 50,
               alignment: Alignment.center,
               child: Icon(
                icon, 
                color: selected ? Colors.black : Colors.white54,
                size: 22
               ),
            ),
          )
        : ClipRect(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         Icon(
                          icon, 
                          color: selected ? Colors.black : Colors.white54,
                          size: 20
                        ),
                        const SizedBox(width: 16),
                        Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white54,
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
                ? [Colors.blueAccent.withOpacity(0.12), Colors.blueAccent.withOpacity(0.04)]
                : [const Color(0xFF101010), const Color(0xFF080808)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlight ? Colors.blueAccent.withOpacity(0.4) : Colors.white.withOpacity(0.05),
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
                  color: highlight ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: highlight ? Colors.blueAccent : Colors.white54, size: 32),
              ),
              SizedBox(height: isCompact ? 14 : 24),
              Text(title, 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)
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
  final String name;
  final String details;
  final String status;
  final List<Widget> actions;

  const _DeviceRow({
    required this.name,
    required this.details,
    required this.status,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTrusted = status == 'Trusted';
    final bool isPending = status == 'Pending';
    final bool isBlocked = status == 'Blocked';
    final bool isDeclined = status == 'Declined';

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool showLabels = constraints.maxWidth > 600;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF080808).withOpacity(isDeclined ? 0.5 : 1.0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPending ? Colors.amber.withOpacity(0.2) 
                   : (isBlocked ? Colors.red.withOpacity(0.2) 
                   : (isDeclined ? Colors.white10 : Colors.white.withOpacity(0.05)))
            ),
          ),
          child: Row(
            children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.amber.withOpacity(0.1) 
                         : (isBlocked ? Colors.red.withOpacity(0.1) 
                         : (isDeclined ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.03))),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPending ? Icons.warning_amber_rounded 
                    : (isBlocked ? Icons.block 
                    : (isDeclined ? Icons.history : Icons.smartphone)), 
                    color: isPending ? Colors.amber 
                         : (isBlocked ? Colors.red 
                         : (isDeclined ? Colors.white24 : Colors.white)), 
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
                        Flexible(
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
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _StatusChip(label: "REQUEST", color: Colors.amber),
                          ),
                        if (isBlocked) 
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _StatusChip(label: "BLOCKED", color: Colors.red),
                          ),
                        if (isDeclined)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _StatusChip(label: "REMOVED", color: Colors.white10, textColor: Colors.white38),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(details, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 0.5)
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions.map((action) {
                  // If screen is narrow, we could try to reduce button padding or use icon buttons
                  // but for now Wrap is a good safety net.
                  return action;
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
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? Colors.white.withOpacity(0.05) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? Colors.white24 : Colors.red.withOpacity(0.3)),
        boxShadow: active ? [
           BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
           BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 20, spreadRadius: 5),
        ] : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.red,
              shape: BoxShape.circle,
              boxShadow: active ? [
                 BoxShadow(color: Colors.white.withOpacity(0.8), blurRadius: 8, spreadRadius: 2),
              ] : [],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            active ? "SERVICE ACTIVE" : "SERVICE STOPPED",
            style: TextStyle(
              color: active ? Colors.white : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              shadows: active ? [
                 Shadow(color: Colors.blueAccent, blurRadius: 10),
              ] : [],
            ),
          ),
        ],
      ),
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
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
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
