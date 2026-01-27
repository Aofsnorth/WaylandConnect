import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'screens/touchpad_screen.dart';
import 'screens/keyboard_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/media_screen.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF0A0A0A),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const WaylandConnectApp());
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
  Socket? _socket;
  bool _isConnected = false;
  String _approvalStatus = "Unknown"; // Unknown, Pending, Trusted, Declined, Blocked
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.1");
  final TextEditingController _portController = TextEditingController(text: "12345");
  int _currentIndex = 0;
  Stream<Uint8List>? _socketStream;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('pc_ip') ?? "192.168.1.1";
      _portController.text = prefs.getString('pc_port') ?? "12345";
    });
  }

  void _showConnectionDialog() {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Connection Rules", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your PC IP to link the devices.", style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
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
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Connect"),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pc_ip', _ipController.text);
              await prefs.setString('pc_port', _portController.text);
              Navigator.pop(ctx);
              _connect();
            },
          )
        ],
      )
    );
  }

  void _connect() async {
    _socket?.close();
    if (_isConnected) return;
    HapticFeedback.mediumImpact();
    try {
      int port = int.tryParse(_portController.text) ?? 12345;
      final s = await Socket.connect(_ipController.text, port, timeout: const Duration(seconds: 4));
      setState(() {
        _socket = s;
        _isConnected = true;
        _approvalStatus = "Unknown";
        _socketStream = s.asBroadcastStream();
      });
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
                   setState(() => _approvalStatus = status);
                   if (status == "Trusted") HapticFeedback.heavyImpact();
                   if (status == "Blocked" || status == "Declined") {
                      HapticFeedback.vibrate();
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
      _showError("Connectivity Error: Host unreachable.");
    }
  }

  void _startPolling() {
     Future.doWhile(() async {
       if (!mounted || !_isConnected) return false;
       if (_approvalStatus == 'Blocked' || _approvalStatus == 'Declined' || _approvalStatus == 'Trusted') return false; 
       _sendPairRequest();
       await Future.delayed(const Duration(seconds: 3)); 
       if (!mounted || !_isConnected) return false;
       if (_approvalStatus == 'Blocked' || _approvalStatus == 'Declined' || _approvalStatus == 'Trusted') return false;
       return true;
     });
   }

   void _sendPairRequest() async {
     if (_socket != null) {
       String deviceName = "Unknown Android";
       String deviceId = "unknown_id";
       try {
         final prefs = await SharedPreferences.getInstance();
         deviceId = prefs.getString('unique_device_id') ?? const Uuid().v4();
         if (!prefs.containsKey('unique_device_id')) {
            await prefs.setString('unique_device_id', deviceId);
         }
         DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
         AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
         deviceName = "${androidInfo.manufacturer} ${androidInfo.model}";
       } catch (e) {}
       final event = {"type": "pair_request", "data": {"device_name": deviceName, "id": deviceId}};
       try { _socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
     }
   }

  void _disconnect() {
    _socket?.destroy();
    _onDisconnect();
  }

  void _onDisconnect() {
    if (mounted) {
      setState(() {
        _isConnected = false;
        if (_approvalStatus != "Declined" && _approvalStatus != "Blocked") {
          _approvalStatus = "Unknown";
        }
        _socket = null;
        _socketStream = null;
      });
    }
  }

  void _resetConnectionState() {
    setState(() {
      _isConnected = false;
      _approvalStatus = "Unknown";
      _socket = null;
      _socketStream = null;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_approvalStatus != "Trusted") {
      return LandingScreen(
        approvalStatus: _approvalStatus,
        isConnected: _isConnected,
        onConnect: _showConnectionDialog,
        onReset: _resetConnectionState,
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        leading: IconButton(
          icon: const Icon(Icons.link_off, color: Colors.white70),
          onPressed: () { _disconnect(); _resetConnectionState(); },
        ),
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
      body: _currentIndex == 0 
          ? TouchpadScreen(socket: _socket)
          : _currentIndex == 1
              ? KeyboardScreen(socket: _socket)
              : MediaScreen(socket: _socket, socketStream: _socketStream),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A0A),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: NavigationBar(
          backgroundColor: const Color(0xFF050505),
          indicatorColor: Colors.white,
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            HapticFeedback.selectionClick();
            setState(() => _currentIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.touch_app_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.touch_app, color: Colors.black),
              label: 'Touchpad',
            ),
            NavigationDestination(
              icon: Icon(Icons.keyboard_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.keyboard, color: Colors.black),
              label: 'Keyboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.music_note_outlined, color: Colors.white54),
              selectedIcon: Icon(Icons.music_note, color: Colors.black),
              label: 'Media',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot() {
    Color dotColor = _approvalStatus == "Trusted" ? Colors.green : Colors.amber;
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
