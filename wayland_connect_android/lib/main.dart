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
import 'utils/protocol.dart';
import 'l10n/app_localizations.dart';
import 'package:crypto/crypto.dart';


import 'screens/touchpad_screen.dart';
import 'screens/keyboard_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/media_screen.dart';
import 'screens/pointer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/disconnect_screen.dart';
import 'screens/device_scanner_dialog.dart';
import 'screens/screen_share_screen.dart';
// Removed unused AppLauncherScreen import
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
    importance: fln.Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
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
      isForegroundMode: false, 
      notificationChannelId: 'connection_status',
      initialNotificationTitle: '',
      initialNotificationContent: '',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}


@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    final fln.FlutterLocalNotificationsPlugin notifications = fln.FlutterLocalNotificationsPlugin();

    void updateNotification(String title) async {
      await notifications.show(
        id: 888,
        title: title, 
        body: null, // No body, just the "Connected to..." title as requested

        notificationDetails: const fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            'connection_status',
            'Connection Status',
            channelDescription: 'Shows connection state',
            importance: fln.Importance.low,
            priority: fln.Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: false,
            onlyAlertOnce: true,
            // subText: 'Wayland Connect', // Removed to keep it minimal
            color: Color(0xFF000000), 
            category: fln.AndroidNotificationCategory.service,
            visibility: fln.NotificationVisibility.public,
          ),
        ),
      );
    }

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });
    
    service.on('updateStatus').listen((event) async {
      String status = event?['content'] ?? "";
      if (status.toLowerCase().contains("connected to")) {
        // Ensure "Connected to [PC Name]"
        String title = status.replaceAll(RegExp(r'connected to', caseSensitive: false), 'Connected To');
        updateNotification(title);
      } else {
        // If not connected, remove notification by going to background
        service.setAsBackgroundService();
        await notifications.cancel(id: 888);
      }
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
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

class WaylandConnectApp extends StatefulWidget {
  const WaylandConnectApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _WaylandConnectAppState? state = context.findAncestorStateOfType<_WaylandConnectAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<WaylandConnectApp> createState() => _WaylandConnectAppState();
}

class _WaylandConnectAppState extends State<WaylandConnectApp> {
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
  Socket? _socket;
  bool _isConnected = false;
  bool _zoomEnabled = false;
  String _approvalStatus = "Unknown"; // Unknown, Pending, Trusted, Declined, Blocked
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.1");
  final TextEditingController _portController = TextEditingController(text: "12345");
  int _currentIndex = 0;
  final List<int> _navigationHistory = [0];
  Stream<Uint8List>? _socketStream;
  bool _isScrolled = false;
  OverlayEntry? _errorOverlay;
  String? _serverName;
  final ProtocolHandler _protocolHandler = ProtocolHandler();

  @override
  void initState() {
    super.initState();
    _loadSettingsAndConnect();
    _startAutoReconnectLoop();
    _setupVolumeChannel();
  }

  // CENTRALIZED VOLUME HANDLING
  final _volumeStreamController = StreamController<String>.broadcast();
  Stream<String> get _volumeEventStream => _volumeStreamController.stream;

  void _setupVolumeChannel() {
    const channel = MethodChannel('com.arthenyx.wayland_connect/volume');
    channel.setMethodCallHandler((call) async {
       if (call.method != null) {
         _volumeStreamController.add(call.method);
       }
    });
  }

  void _setInterceptVolume(bool enabled) {
    const channel = MethodChannel('com.arthenyx.wayland_connect/volume');
    channel.invokeMethod('setInterceptVolume', {'enabled': enabled});
  }

  @override 
  void dispose() { // Clean up
     _volumeStreamController.close();
     super.dispose();
  }

  void _startAutoReconnectLoop() {
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isConnected && _approvalStatus == "Trusted") {
        _checkAutoConnectAndConnect();
      }
    });
  }

  void _checkAutoConnectAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final bool autoConnect = prefs.getBool('auto_connect') ?? true;
    if (autoConnect) {
      _connect(silent: true);
    }
  }

  void _onTabChanged(int index) {
    if (_currentIndex == index) return;
    setState(() {
      if (_navigationHistory.length > 20) _navigationHistory.removeAt(0);
      _navigationHistory.add(index);
      _currentIndex = index;
      _isScrolled = false; // Reset scroll state (blur) immediately when changing tabs
      _setInterceptVolume([2, 3].contains(index));
      
      // ORIENTATION LOCKING: Only allow landscape in Screen Share (tab 4)
      if (index == 4) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
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
    
    final bool autoConnect = prefs.getBool('auto_connect') ?? true;
    if ((_approvalStatus == "Trusted" || _approvalStatus == "Pending") && autoConnect) {
      _connect(silent: true);
    }
    
    if (_approvalStatus == "Trusted") _updateServiceStatus("searching for pc...");
  }


  void _showConnectionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DeviceScannerDialog(),
    ).then((result) async {
      if (result != null) {
        if (result is String) {
           // Reload settings just saved by the dialog
           final prefs = await SharedPreferences.getInstance();
           setState(() {
             _ipController.text = prefs.getString('pc_ip') ?? result;
             _portController.text = prefs.getString('pc_port') ?? "12345";
           });
           
           // Connect with feedback (silent: false)
           _connect(silent: false);
        }
      }
    });
  }


  void _connect({bool silent = false}) async {
    _socket?.close();
    if (_isConnected) return;
    if (!silent) HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final expectedFingerprint = prefs.getString('server_fingerprint');

      int port = int.tryParse(_portController.text) ?? 12345;
      final s = await SecureSocket.connect(
        _ipController.text, 
        port, 
        timeout: const Duration(seconds: 3),
        onBadCertificate: (certificate) {
          // 1. Calculate SHA-256 fingerprint of the certificate
          final hash = sha256.convert(certificate.der).toString().toUpperCase();
          final formattedHash = hash.replaceAllMapped(RegExp(r".{2}"), (match) => "${match.group(0)}:").substring(0, hash.length + (hash.length / 2).floor() - 1);
          
          debugPrint("🛡️ Received Cert Fingerprint: $formattedHash");
          
          if (expectedFingerprint != null && expectedFingerprint.isNotEmpty) {
             if (expectedFingerprint == formattedHash) {
                debugPrint("✅ Fingerprint matches pinned certificate.");
                return true;
             } else {
                debugPrint("🚨 MITM ATTACK DETECTED? Fingerprint mismatch!");
                debugPrint("   Expected: $expectedFingerprint");
                debugPrint("   Got:      $formattedHash");
                _showError("Security Alert: Server identity changed!");
                return false;
             }
          }
          
          // First time connecting (TOFU) or not yet trusted
          debugPrint("⚖️ First time connection or untrusted. Allowing for handshake...");
          return true; 
        },
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
        (data) async {
           // Binary Protocol Handling
           try {
             final packets = _protocolHandler.process(data);
             for (final packet in packets) {
                // Check packet type. MsgPack decodes maps as Map<dynamic, dynamic> usually.
                // We cast to string keys if needed.
                
                // Expected format: {"type": "...", "data": ...}
                if (packet is Map) {
                   // Optimization: Skip binary/high-frequency packets (Spectrum/Frame)
                   // and let specific screens handle them if they are listening to the same stream.
                   if (packet.containsKey('t')) continue;

                   final type = packet['type'];
                   if (type == 'mirror_frame') continue; // Extra safety                   
                   final pData = packet['data'];
                   
                   if (type == 'status_response' && pData != null) {
                      final zoomEnabled = pData['zoom_enabled'] as bool?;
                      if (zoomEnabled != null) {
                        setState(() => _zoomEnabled = zoomEnabled);
                      }
                   }

                   if (type == 'mirror_request' && pData != null) {
                      _showMirrorRequestDialog(pData['device_name'] ?? "Linux PC", pData['device_id'] ?? "");
                   }

                   if (type == 'mirror_status' && pData != null) {
                      _showMirrorStatus(pData['allowed'] == true, pData['message'] ?? "");
                   }

                   if (type == 'pair_response') {
                      final status = pData['status'];
                      final sName = pData['server_name'];
                      
                      if (sName != null) {
                        setState(() => _serverName = sName);
                        final prefs = await SharedPreferences.getInstance();
                        prefs.setString('server_name', sName);
                      }
                      
                      _updateApprovalStatus(status, fingerprint: pData['fingerprint']);
                      if (status == "Trusted") {
                        HapticFeedback.heavyImpact();
                        _showConnectedNotification();
                        _updateServiceStatus("connected to ${_serverName ?? 'pc'}");
                        FlutterBackgroundService().invoke("setAsForeground");
                      }
                      if (status == "Blocked" || status == "Declined") {
                        HapticFeedback.vibrate();
                        _disconnect();
                      }
                      if (status == "VersionMismatch") {
                        _showVersionMismatchDialog(pData['message'] ?? "Update required.");
                        _disconnect(manual: true);
                      }
                   }

                   if (type == 'security_update' && pData != null) {
                      final status = pData['status'];
                      _updateApprovalStatus(status);
                      if (status == "Blocked" || status == "Declined") {
                         HapticFeedback.vibrate();
                         _disconnect();
                      } else if (status == "Trusted") {
                         HapticFeedback.mediumImpact();
                         // Auto-refresh or just wait for reconnect loop
                      }
                   }
                }
             }
           } catch (e) {
             debugPrint("Protocol error: $e");
           }
        },
        onDone: () => _onDisconnect(),
        onError: (e) => _onDisconnect(),
      );
    } catch (e) {
      if (!silent) _showError("Connection failed: $e");
    }
  }

  void _showVersionMismatchDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.update, color: Colors.orangeAccent),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context)!.updateRequired, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.deny.toUpperCase(), style: const TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () async {
              final url = Uri.parse("https://github.com/Aofsnorth/WaylandConnect/releases/latest");
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(AppLocalizations.of(context)!.updateRequired), // Using same for now as fallback
          ),
        ],
      ),
    );
  }

  Future<void> _updateApprovalStatus(String status, {String? fingerprint}) async {
    setState(() => _approvalStatus = status);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('approval_status', status);
    if (fingerprint != null) {
      await prefs.setString('server_fingerprint', fingerprint);
      debugPrint("📌 Pinned Server Fingerprint: $fingerprint");
    }
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
       final prefs = await SharedPreferences.getInstance();
       try {
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

       String version = "1.0.0"; // Fallback
       try {
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          version = packageInfo.version;
       } catch (_) {}

        final bool autoReconnect = prefs.getBool('auto_reconnect') ?? true;

        final event = {
          "type": "pair_request",
          "data": {
            "device_name": deviceName,
            "id": deviceId,
            "version": version,
            "auto_reconnect": autoReconnect,
          }
        };
       try { 
         _socket!.add(ProtocolHandler.encodePacket(event)); 
       } catch (_) {}
     }
   }

  void _disconnect({bool manual = false}) {
    _socket?.destroy();
    _onDisconnect(manual: manual);
  }

  void _onDisconnect({bool manual = false}) {
    if (mounted) {
      setState(() {
        _isConnected = false;
        _socket = null;
        _socketStream = null;
      });
       _hideNotification();
       FlutterBackgroundService().invoke("setAsBackground");
       _setInterceptVolume(false);
       if (_approvalStatus == "Trusted") {
         _updateServiceStatus("searching for pc...");
         setState(() => _serverName = null);
       }
     }
  }

  void _resetConnectionState({bool notifyServer = false}) async {
    if (notifyServer && _socket != null) {
      try {
        final event = {"type": "cancel_request"};
        _socket!.add(ProtocolHandler.encodePacket(event));
      } catch (_) {}
    }
    
    _approvalStatus = "Unknown";
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('approval_status');
    // Ensure we disconnect the socket if we are resetting state
    _socket?.destroy();
    
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
    FlutterBackgroundService().invoke("updateStatus", {"content": "Connected to ${_serverName ?? 'PC'}"});
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

  void _showMirrorRequestDialog(String deviceName, String deviceId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.monitor, color: Colors.blueAccent),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context)!.mirroringRequest, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text("'$deviceName' ${AppLocalizations.of(context)!.wantsToMirrorYourScreen}", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sendMirrorResponse(deviceId, false);
            },
            child: Text(AppLocalizations.of(context)!.deny, style: const TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(ctx);
              _sendMirrorResponse(deviceId, true);
            },
            child: Text(AppLocalizations.of(context)!.allow),
          ),
        ],
      ),
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
      try {
        _socket!.add(ProtocolHandler.encodePacket(event));
      } catch (_) {}
    }
  }

  void _showMirrorStatus(bool allowed, String message) {
     _showError(message);
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
          title: Text(AppLocalizations.of(context)!.exitApp, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(AppLocalizations.of(context)!.exitConfirmation, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.cancel, style: const TextStyle(color: Colors.white38))),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              style: TextButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1)),
              child: Text(AppLocalizations.of(context)!.exit, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
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
          onReset: () => _resetConnectionState(notifyServer: true),
          socket: _socket,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth > 800;
        
        // Navigation Mapping:
        // 0: Touchpad
        // 1: Keyboard
        // 2: Media
        // 3: Present
        // 4: Desktop (Screen Share)
        // 5: Settings
        final int safeIndex = (_currentIndex >= 0 && _currentIndex <= 5) ? _currentIndex : 0;

        Widget? bottomBar;
        if (!isDesktop && _currentIndex != 5) { // 5 is Settings
          bottomBar = Material(
            color: Colors.transparent,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: double.infinity, // Ensure full width in landscape
                  height: 90,
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                    ),
                  ),
                  child: Center( // Center content for better landscape look
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildNavButton(0, Icons.touch_app_outlined, Icons.touch_app, AppLocalizations.of(context)!.touchpad),
                          _buildNavButton(1, Icons.keyboard_outlined, Icons.keyboard, AppLocalizations.of(context)!.keyboard),
                          _buildNavButton(2, Icons.music_note_outlined, Icons.music_note, AppLocalizations.of(context)!.media),
                          _buildNavButton(3, Icons.stars_outlined, Icons.stars, AppLocalizations.of(context)!.present),
                          _buildNavButton(4, Icons.computer_rounded, Icons.computer, AppLocalizations.of(context)!.desktop),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // --- DISCONNECTION OVERLAY ---
        if (!_isConnected && _approvalStatus == "Trusted") {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              final shouldExit = await _showExitConfirmation();
              if (shouldExit) SystemNavigator.pop();
            },
            child: DisconnectedScreen(
              onReconnect: _connect,
              onReturnHome: () => _resetConnectionState(notifyServer: false),
              lastDeviceName: _serverName,
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (_navigationHistory.length > 1) {
              setState(() {
                _navigationHistory.removeLast();
                _currentIndex = _navigationHistory.last;
                _setInterceptVolume([2, 3].contains(_currentIndex));
              });
            } else if (_currentIndex != 0) {
              setState(() {
                _currentIndex = 0;
                _navigationHistory.clear();
                _navigationHistory.add(0);
                _setInterceptVolume(false);
              });
            } else {
              final shouldExit = await _showExitConfirmation();
              if (shouldExit) {
                SystemNavigator.pop();
              }
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            extendBodyBehindAppBar: true,
            appBar: (isDesktop || _currentIndex == 5) ? null : AppBar(
              key: ValueKey(_currentIndex), // FORCE REBUILD ON TAB CHANGE to clear stuck states
              // Strict logic: Media (2), and Desktop (4) allow transparent/blur.
              backgroundColor: ([2, 4].contains(_currentIndex) && _isScrolled) ? Colors.black.withOpacity(0.3) : Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0, // Prevent white tint on scroll
              surfaceTintColor: Colors.transparent, // Prevent white tint on scroll
              toolbarHeight: 80,
              flexibleSpace: ([2, 4].contains(_currentIndex) && _isScrolled)
                  ? ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(color: Colors.transparent),
                      ),
                    )
                  : null,
          leading: _currentIndex == 5 // Settings Screen
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () {
                    if (_navigationHistory.length > 1) {
                      setState(() {
                        _navigationHistory.removeLast();
                        _currentIndex = _navigationHistory.last;
                        _setInterceptVolume([2, 3].contains(_currentIndex));
                      });
                    } else {
                      setState(() {
                        _currentIndex = 0;
                        _setInterceptVolume(false);
                      });
                    }
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.link_off, color: Colors.white70),
                  onPressed: () { _disconnect(manual: true); _resetConnectionState(); },
                ),
          actions: [
            if (_currentIndex != 5)
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                onPressed: () => _onTabChanged(5),
              ),
            const SizedBox(width: 20),
          ],
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    // Force transparent on non-Media tabs to prevent stickiness
                    if (_currentIndex != 2) { // 2 = Media
                       if (_isScrolled) setState(() => _isScrolled = false);
                       return false;
                    }

                    if (notification is ScrollUpdateNotification) {
                      if (notification.metrics.axis == Axis.vertical) {
                        final scrolled = notification.metrics.pixels > 20;
                        if (_isScrolled != scrolled) {
                          setState(() => _isScrolled = scrolled);
                        }
                      }
                    }
                    return false;
                  },
                  child: Stack(
                  children: [
                    IndexedStack(
                      index: safeIndex,
                      children: [
                        TouchpadScreen(socket: _socket),
                        KeyboardScreen(socket: _socket),
                        MediaScreen(socket: _socket, socketStream: _socketStream, isActiveTab: _currentIndex == 2, volumeStream: _volumeEventStream),
                        PointerScreen(socket: _socket, isActiveTab: _currentIndex == 3, volumeStream: _volumeEventStream, zoomEnabled: _zoomEnabled),
                        ScreenShareScreen(socket: _socket, socketStream: _socketStream),
                        SettingsScreen(
                          socket: _socket,
                          onBack: () {
                          if (_navigationHistory.length > 1) {
                            setState(() {
                              _navigationHistory.removeLast();
                              _currentIndex = _navigationHistory.last;
                              _setInterceptVolume([2, 3].contains(_currentIndex));
                            });
                          } else {
                            setState(() {
                              _currentIndex = 0;
                              _setInterceptVolume(false);
                            });
                          }
                        }),
                      ],
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
                    Text(_isConnected ? AppLocalizations.of(context)!.connected : AppLocalizations.of(context)!.disconnected, style: TextStyle(fontSize: 10, color: _isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
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
                  _SidebarItem(icon: Icons.touch_app_outlined, label: AppLocalizations.of(context)!.touchpad, selected: _currentIndex == 0, onTap: () => _onTabChanged(0)),
                  _SidebarItem(icon: Icons.keyboard_outlined, label: AppLocalizations.of(context)!.keyboard, selected: _currentIndex == 1, onTap: () => _onTabChanged(1)),
                  _SidebarItem(icon: Icons.music_note_outlined, label: AppLocalizations.of(context)!.mediaControl, selected: _currentIndex == 2, onTap: () => _onTabChanged(2)),
                  _SidebarItem(icon: Icons.stars_outlined, label: AppLocalizations.of(context)!.presentation, selected: _currentIndex == 3, onTap: () => _onTabChanged(3)),
                  _SidebarItem(icon: Icons.screenshot_monitor_outlined, label: AppLocalizations.of(context)!.screenShare, selected: _currentIndex == 4, onTap: () => _onTabChanged(4)),
                  _SidebarItem(icon: Icons.settings_outlined, label: AppLocalizations.of(context)!.settings, selected: _currentIndex == 5, onTap: () => _onTabChanged(5)),
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
              label: Text(AppLocalizations.of(context)!.disconnect),
              onPressed: () { _disconnect(manual: true); _resetConnectionState(); },
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

  Widget _buildNavButton(int index, IconData icon, IconData selectedIcon, String label) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabChanged(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSelected ? selectedIcon : icon, color: isSelected ? Colors.white : Colors.white38, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white24, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
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
