import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'package:permission_handler/permission_handler.dart';


import 'screens/touchpad_screen.dart';
import 'screens/keyboard_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/media_screen.dart';
import 'screens/pointer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/disconnect_screen.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';


final fln.FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = fln.FlutterLocalNotificationsPlugin();

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const fln.AndroidNotificationChannel channel = fln.AndroidNotificationChannel(
    'connection_status', 
    'Connection Status',
    description: 'Shows if PC is connected',
    importance: fln.Importance.max,
    playSound: false,
    enableVibration: false,
    showBadge: true,
  );

  const fln.AndroidInitializationSettings initializationSettingsAndroid = fln.AndroidInitializationSettings('@mipmap/ic_launcher');
  const fln.InitializationSettings initializationSettings = fln.InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (details) {
      if (details.actionId == 'stop_service') {
        service.invoke("stopService");
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  final fln.AndroidFlutterLocalNotificationsPlugin? androidImplementation = 
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
  
  await androidImplementation?.createNotificationChannel(channel);
  
  // Request permission explicitly for Android 13+
  if (Platform.isAndroid) {
     await androidImplementation?.requestNotificationsPermission();
  }

  final prefs = await SharedPreferences.getInstance();
  final bool autoStart = prefs.getBool('start_on_boot') ?? true;

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: autoStart,
      isForegroundMode: true,
      notificationChannelId: 'connection_status',
      initialNotificationTitle: 'searching for pc...',
      initialNotificationContent: 'preparing connection...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}


@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    
    final fln.FlutterLocalNotificationsPlugin notifications = fln.FlutterLocalNotificationsPlugin();

    void updateNotification(String content) async {
      await notifications.show(
        id: 888,
        title: content, // Just show the status (e.g., 'connected to desktop') in the title
        body: null,    // Hide body for a cleaner single-line look
        notificationDetails: const fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            'connection_status',
            'Connection Status',
            channelDescription: 'Shows connection state',
            importance: fln.Importance.max,
            priority: fln.Priority.high,
            ongoing: true,
            showWhen: false,
            onlyAlertOnce: true,
            color: Color(0xFF000000), 
            category: fln.AndroidNotificationCategory.service,
            visibility: fln.NotificationVisibility.public,
            actions: <fln.AndroidNotificationAction>[
              fln.AndroidNotificationAction(
                'stop_service',
                'DISCONNECT',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
      );
    }

    // Immediate notification
    updateNotification("service active...");

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('updateStatus').listen((event) {
      String status = event?['content'] ?? "service running";
      updateNotification(status.toLowerCase());
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1000, 700),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: "WaylandConnect Remote",
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent, 
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // Force edge-to-edge
  
  // Don't request here, do it in the UI or after frame
  initializeService();

  runApp(const WaylandConnectApp());
}

@pragma('vm:entry-point')
void notificationTapBackground(fln.NotificationResponse notificationResponse) {
  if (notificationResponse.actionId == 'stop_service') {
    FlutterBackgroundService().invoke("stopService");
  }
}

class WaylandConnectApp extends StatelessWidget {
  const WaylandConnectApp({super.key});

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
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  SecureSocket? _socket;
  bool _isConnected = false;
  String _approvalStatus = "Unknown"; // Unknown, Pending, Trusted, Declined, Blocked
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.1");
  final TextEditingController _portController = TextEditingController(text: "12345");
  int _currentIndex = 0;
  Stream<Uint8List>? _socketStream;
  bool _isScrolled = false;
  OverlayEntry? _errorOverlay;
  String? _serverName;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndConnect();
    _startAutoReconnectLoop();
  }

  void _startAutoReconnectLoop() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isConnected && _approvalStatus == "Trusted") {
        _connect(silent: true);
      }
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isScrolled = false; // Reset scroll state saat ganti tab
    });
  }

  Future<void> _loadSettingsAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('pc_ip') ?? "192.168.1.1";
      _portController.text = prefs.getString('pc_port') ?? "12345";
      _approvalStatus = prefs.getString('approval_status') ?? "Unknown";
      _serverName = prefs.getString('server_name');
    });
    
    _connect(silent: true);
    if (_approvalStatus == "Trusted") _updateServiceStatus("searching for pc...");
  }

  void _showConnectionDialog() {
    bool isChecking = false;

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text("Connect to PC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Ensure Wayland Connect is running on your PC.", style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 24),
                TextField(
                  controller: _ipController,
                  enabled: !isChecking,
                  cursorColor: Colors.white,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "PC IP Address",
                    labelStyle: const TextStyle(color: Colors.white38),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white),
                    ),
                    prefixIcon: const Icon(Icons.computer, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  enabled: !isChecking,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  cursorColor: Colors.white,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Port",
                    labelStyle: const TextStyle(color: Colors.white38),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white),
                    ),
                    prefixIcon: const Icon(Icons.hub_outlined, color: Colors.white54),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
                onPressed: isChecking ? null : () => Navigator.pop(ctx),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(100, 45),
                ),
                onPressed: isChecking ? null : () async {
                  final ip = _ipController.text.trim();
                  final portStr = _portController.text.trim();
                  
                  // 1. Validate Formats
                  final ipRegex = RegExp(r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$');
                  if (!ipRegex.hasMatch(ip) && ip != 'localhost') {
                    _showError("Invalid IP Address format.");
                    return;
                  }
                  
                  final port = int.tryParse(portStr);
                  if (port == null || port < 1024 || port > 65535) {
                    _showError("Invalid Port (1024-65535).");
                    return;
                  }

                  // 2. Validate Service existence (The Check)
                  setDialogState(() => isChecking = true);
                  try {
                    final testSocket = await SecureSocket.connect(
                      ip, 
                      port, 
                      timeout: const Duration(seconds: 3),
                      onBadCertificate: (cert) => true, // Self-signed support
                    );
                    testSocket.destroy(); // Success, close temp socket
                    
                    // 3. Save and Proceed
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('pc_ip', ip);
                    await prefs.setString('pc_port', portStr);
                    
                    if (context.mounted) Navigator.pop(ctx);
                    _connect();
                  } catch (e) {
                    setDialogState(() => isChecking = false);
                    _showError("PC not found or Wayland Connect is OFF.");
                  }
                },
                child: isChecking 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text("Connect"),
              )
            ],
          );
        }
      )
    );
  }

  void _connect({bool silent = false}) async {
    _socket?.close();
    if (_isConnected) return;
    if (!silent) HapticFeedback.mediumImpact();
    try {
      int port = int.tryParse(_portController.text) ?? 12345;
      final s = await SecureSocket.connect(
        _ipController.text, 
        port, 
        timeout: const Duration(seconds: 4),
        onBadCertificate: (cert) => true,
      );
      setState(() {
        _socket = s;
        _isConnected = true;
        _socketStream = s.asBroadcastStream();
      });
      if (_approvalStatus == "Trusted") {
         _showConnectedNotification();
         _updateServiceStatus("Connected to PC");
         FlutterBackgroundService().invoke("setAsForeground");
      }
      _startPolling(); 
      _socketStream!.listen(
        (data) {
          try {
            final str = String.fromCharCodes(data).trim();
            final lines = str.split('\n');
            for (var line in lines) {
              if (line.isEmpty) continue;
              try {
                final json = jsonDecode(line);
                 if (json['type'] == 'pair_response') {
                    final status = json['data']['status'];
                    final sName = json['data']['server_name'];
                    if (sName != null) setState(() => _serverName = sName);
                    
                    _updateApprovalStatus(status);
                    if (status == "Trusted") {
                       HapticFeedback.heavyImpact();
                       _showConnectedNotification();
                       _updateServiceStatus("connected to ${_serverName ?? 'pc'}");
                       FlutterBackgroundService().invoke("setAsForeground");
                    }
                   if (status == "Blocked") {
                      HapticFeedback.vibrate();
                      _disconnect();
                   }
                   if (status == "VersionMismatch") {
                      _showVersionMismatchDialog(json['data']['message'] ?? "Update required.");
                      _disconnect();
                   }
                }
              } catch (_) {}
            }
          } catch (e) {}
        },
        onDone: () => _onDisconnect(),
        onError: (e) => _onDisconnect(),
      );
    } catch (e) {
      if (!silent) _showError("Connectivity Error: Host unreachable.");
    }
  }

  void _showVersionMismatchDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.update, color: Colors.orangeAccent),
            SizedBox(width: 12),
            Text("Update Required", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Dimiss", style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () async {
              final url = Uri.parse("https://github.com/arthenyx/WaylandConnect/releases/latest");
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateApprovalStatus(String status) async {
    setState(() => _approvalStatus = status);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('approval_status', status);
    if (_serverName != null) {
      await prefs.setString('server_name', _serverName!);
    } else {
      await prefs.remove('server_name');
    }
  }

  void _startPolling() {
     // Always send initial handshake to update IP on Server
     _sendPairRequest();

     Future.doWhile(() async {
       if (!mounted || !_isConnected) return false;
       // We only need to keep polling (requesting) if we aren't Trusted yet
       if (_approvalStatus == 'Trusted' || _approvalStatus == 'Blocked') return false; 
       
       await Future.delayed(const Duration(seconds: 3)); 
       if (!mounted || !_isConnected) return false;
       
       _sendPairRequest();
       return true;
     });
   }

   void _sendPairRequest() async {
     if (_socket != null) {
       String deviceName = "Unknown Device";
       String deviceId = "unknown_id";
       try {
         final prefs = await SharedPreferences.getInstance();
         deviceId = prefs.getString('unique_device_id') ?? const Uuid().v4();
         if (!prefs.containsKey('unique_device_id')) await prefs.setString('unique_device_id', deviceId);
         
         if (Platform.isAndroid) {
            DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
            AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
            deviceName = "${androidInfo.manufacturer} ${androidInfo.model}";
         } else if (Platform.isLinux) {
            deviceName = "Linux Controller";
         } else {
            deviceName = "Desktop Controller";
         }
       } catch (e) {}

       String version = "1.0.4"; // Fallback
       try {
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          version = packageInfo.version;
       } catch (_) {}

       final event = {
         "type": "pair_request", 
         "data": {
           "device_name": deviceName, 
           "id": deviceId,
           "version": version
         }
       };
       try { _socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
     }
   }

  void _disconnect() {
    _socket?.destroy();
    _onDisconnect();
  }

  void _onDisconnect() {
    if (mounted) {
      if (_isConnected) {
        // Only show screen if we were previously connected (not manual disconnect)
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => DisconnectedScreen(
              onReconnect: () => _connect(),
            ),
          ),
        );
      }
      
      setState(() {
        _isConnected = false;
        _socket = null;
        _socketStream = null;
      });
       _hideNotification();
       FlutterBackgroundService().invoke("setAsBackground");
       if (_approvalStatus == "Trusted") {
         _updateServiceStatus("searching for pc...");
         setState(() => _serverName = null);
       }
     }
  }

  void _resetConnectionState() async {
    _approvalStatus = "Unknown";
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('approval_status');
    setState(() {
      _isConnected = false;
      _socket = null;
      _socketStream = null;
    });
  }

  void _updateServiceStatus(String content) {
    FlutterBackgroundService().invoke("updateStatus", {"content": content});
  }

  Future<void> _showConnectedNotification() async {
    // We use the background service to manage the persistent notification
    // as it is more reliable for 'ongoing' services on Android.
    FlutterBackgroundService().invoke("updateStatus", {"content": "Connected to PC"});
  }

  Future<void> _hideNotification() async {
    FlutterBackgroundService().invoke("updateStatus", {"content": "Searching for PC..."});
  }

  void _showError(String msg) {
    _errorOverlay?.remove();
    _errorOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: -5)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      child: const Icon(Icons.error_outline, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.2)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_errorOverlay!);
    Future.delayed(const Duration(seconds: 3), () {
      if (_errorOverlay != null) {
        _errorOverlay?.remove();
        _errorOverlay = null;
      }
    });
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
          title: const Text("Exit App", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text("Are you sure you want to close Wayland Connect?", style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL", style: TextStyle(color: Colors.white38))),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              style: TextButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1)),
              child: const Text("EXIT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_approvalStatus != "Trusted") {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldExit = await _showExitConfirmation();
          if (shouldExit) {
            SystemNavigator.pop();
          }
        },
        child: LandingScreen(
          approvalStatus: _approvalStatus,
          isConnected: _isConnected,
          onConnect: _showConnectionDialog,
          onReset: _resetConnectionState,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth > 800;
        
        // Use a local variable to ensure consistency during rebuilds
        final int safeIndex = (_currentIndex >= 0 && _currentIndex < 4) ? _currentIndex : (_currentIndex == 4 ? 0 : 0);

        Widget? bottomBar;
        if (!isDesktop && _currentIndex != 4) {
          bottomBar = Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme: NavigationBarThemeData(
                  indicatorColor: Colors.white,
                  labelTextStyle: WidgetStateProperty.all(const TextStyle(color: Colors.white70, fontSize: 11)),
                  iconTheme: WidgetStateProperty.all(const IconThemeData(color: Colors.white54)),
                ),
              ),
              child: NavigationBar(
                height: 70,
                backgroundColor: Colors.transparent,
                indicatorColor: Colors.white,
                elevation: 0,
                selectedIndex: safeIndex,
                onDestinationSelected: (index) {
                  if (index >= 0 && index < 4) {
                    HapticFeedback.selectionClick();
                    _onTabChanged(index);
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.touch_app_outlined),
                    selectedIcon: Icon(Icons.touch_app, color: Colors.black),
                    label: 'Touchpad',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.keyboard_outlined),
                    selectedIcon: Icon(Icons.keyboard, color: Colors.black),
                    label: 'Keyboard',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.music_note_outlined),
                    selectedIcon: Icon(Icons.music_note, color: Colors.black),
                    label: 'Media',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.stars_outlined),
                    selectedIcon: Icon(Icons.stars, color: Colors.black),
                    label: 'Present',
                  ),
                ],
              ),
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (_currentIndex != 0) {
              setState(() => _currentIndex = 0);
            } else {
              final shouldExit = await _showExitConfirmation();
              if (shouldExit) {
                SystemNavigator.pop();
              }
            }
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: isDesktop ? null : AppBar(
              backgroundColor: _isScrolled ? Colors.black.withOpacity(0.3) : Colors.transparent,
              elevation: 0,
              toolbarHeight: 80,
              flexibleSpace: _isScrolled
                  ? ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(color: Colors.transparent),
                      ),
                    )
                  : null,
              leading: _currentIndex == 4
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      onPressed: () => setState(() => _currentIndex = 0),
                    )
                  : IconButton(
                      icon: const Icon(Icons.link_off, color: Colors.white70),
                      onPressed: () { _disconnect(); _resetConnectionState(); },
                    ),
              actions: [
                if (_currentIndex != 4)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                    onPressed: () => setState(() => _currentIndex = 4),
                  ),
                const SizedBox(width: 12),
              ],
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/images/app_logo.png', width: 40, height: 40, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusDot(),
                ],
              ),
            ),
          body: Row(
            children: [
              if (isDesktop) 
                _buildSidebar(),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      final scrolled = notification.metrics.pixels > 20;
                      if (_isScrolled != scrolled) {
                        setState(() => _isScrolled = scrolled);
                      }
                    }
                    return false;
                  },
                  child: Stack(
                  children: [
                    IndexedStack(
                      index: _currentIndex,
                      children: [
                        TouchpadScreen(socket: _socket),
                        KeyboardScreen(socket: _socket),
                        MediaScreen(socket: _socket, socketStream: _socketStream),
                        PointerScreen(socket: _socket),
                        const SettingsScreen(),
                      ],
                    ),
                    if (!_isConnected && _approvalStatus == "Trusted")
                       Positioned(
                         bottom: isDesktop ? 40 : 120, left: 20, right: 20,
                         child: Container(
                           padding: const EdgeInsets.all(12),
                           decoration: BoxDecoration(
                             color: Colors.redAccent.withOpacity(0.9), 
                             borderRadius: BorderRadius.circular(16),
                             boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]
                           ),
                           child: Row(
                             children: [
                               const Icon(Icons.link_off, color: Colors.white),
                               const SizedBox(width: 12),
                               const Expanded(child: Text("PC DISCONNECTED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                               TextButton(
                                 onPressed: _connect, 
                                 style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withOpacity(0.2)),
                                 child: const Text("RECONNECT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11))
                               ),
                             ],
                           ),
                         ),
                       ),
                   ],
                  ),
                ),
              ),
            ],
          ),
            bottomNavigationBar: bottomBar,
          extendBody: true, // Key property to extend content behind NavBar
        ));
      }
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        border: const Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/images/app_logo.png', width: 48, height: 48),
                ),
                const SizedBox(height: 16),
                const Text("WAYLAND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 4, color: Colors.white70)),
                const Text("CONNECT", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatusDot(),
                    const SizedBox(width: 8),
                    Text(_isConnected ? "CONNECTED" : "DISCONNECTED", style: TextStyle(fontSize: 10, color: _isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SidebarItem(icon: Icons.touch_app_outlined, label: "Touchpad", selected: _currentIndex == 0, onTap: () => _onTabChanged(0)),
                  _SidebarItem(icon: Icons.keyboard_outlined, label: "Keyboard", selected: _currentIndex == 1, onTap: () => _onTabChanged(1)),
                  _SidebarItem(icon: Icons.music_note_outlined, label: "Media Control", selected: _currentIndex == 2, onTap: () => _onTabChanged(2)),
                  _SidebarItem(icon: Icons.stars_outlined, label: "Presentation", selected: _currentIndex == 3, onTap: () => _onTabChanged(3)),
                  _SidebarItem(icon: Icons.settings_outlined, label: "Settings", selected: _currentIndex == 4, onTap: () => _onTabChanged(4)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70, 
                side: const BorderSide(color: Colors.white10),
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 48),
              ),
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text("Disconnect"),
              onPressed: () { _disconnect(); _resetConnectionState(); },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot() {
    Color dotColor = _isConnected ? Colors.green : Colors.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: dotColor.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.white38, size: 20),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white38,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
