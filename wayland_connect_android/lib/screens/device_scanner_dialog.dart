import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/protocol.dart';

class DeviceScannerDialog extends StatefulWidget {
  @override
  State<DeviceScannerDialog> createState() => _DeviceScannerDialogState();
}

class DiscoveredDevice {
  final String ip;
  final String name;
  DiscoveredDevice(this.ip, this.name);

  @override
  bool operator ==(Object other) => other is DiscoveredDevice && other.ip == ip;
  @override
  int get hashCode => ip.hashCode;
}

class _DeviceScannerDialogState extends State<DeviceScannerDialog> {
  final List<DiscoveredDevice> _foundDevices = [];
  bool _isScanning = true;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: "12345");
  bool _isManualInput = false;

  @override
  void initState() {
    super.initState();
    _scanNetwork();
  }

  void _scanNetwork() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _foundDevices.clear();
    });

    try {
      final minTimeFuture = Future.delayed(const Duration(seconds: 2));
      int port = int.tryParse(_portController.text) ?? 12345;
      
      _udpDiscovery(port);
      
      List<String> subnets = [];
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback && !addr.address.startsWith("10.0.2")) { // skip emulator generic
             String subnet = addr.address.substring(0, addr.address.lastIndexOf('.'));
             if (!subnets.contains(subnet)) subnets.add(subnet);
          }
        }
      }

      if (subnets.isEmpty) {
        if (mounted) setState(() {
           _isScanning = false;
           _statusText = "No WiFi connection found";
        });
        return;
      }
      
      List<Future> allScans = [];
      int batchSize = 30; // slightly reduced for more reliable individual handshakes

      for (String subnet in subnets) {
          if (mounted) setState(() => _statusText = "Scanning ${subnet}.1-255 ...");
          
          for (int i = 1; i < 255; i+=batchSize) {
             List<Future> batch = [];
             for (int j = i; j < i + batchSize && j < 255; j++) {
                String ip = '$subnet.$j';
                
                batch.add(SecureSocket.connect(ip, port, timeout: const Duration(milliseconds: 600), onBadCertificate: (_) => true).then((socket) async {
                   final localProtocol = ProtocolHandler();
                   String pcName = ip;
                   try {
                     debugPrint('📡 Sending discovery to $ip...');
                     socket.add(ProtocolHandler.encodePacket({"type": "discovery", "data": {}}));
                     
                     // Listen for binary packets
                     await for (var data in socket.timeout(const Duration(milliseconds: 2000))) {
                        final packets = localProtocol.process(data);
                        bool found = false;
                        for (final packet in packets) {
                           debugPrint('📦 Received packet from $ip: $packet');
                           if (packet is Map && packet['type'].toString().toLowerCase() == 'discovery_response') {
                              pcName = packet['data']?['server_name'] ?? pcName;
                              debugPrint('🎯 SUCCESS: Found PC: $pcName at $ip');
                              found = true;
                              break;
                           }
                        }
                        if (found) break;
                     }
                   } catch (e) {
                     // debugPrint('Scan handshake failed for $ip: $e');
                   }

                   socket.destroy();
                   if (mounted) {
                     setState(() {
                        final dev = DiscoveredDevice(ip, pcName);
                        if (!_foundDevices.contains(dev)) {
                          _foundDevices.add(dev);
                        }
                     });
                   }
                }).catchError((e) {}));
             }
             await Future.wait(batch);
          }
      }
      
      await minTimeFuture;
    } catch (_) {}

    if (mounted) setState(() {
       _isScanning = false;
       _statusText = _foundDevices.isEmpty ? "Scan complete. No devices found." : "Scan complete.";
    });
  }

  void _udpDiscovery(int port) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      debugPrint('📡 Sending UDP Discovery broadcast...');
      final data = utf8.encode("discovery");
      socket.send(data, InternetAddress("255.255.255.255"), 12346);

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final ip = datagram.address.address;
            debugPrint('🎯 Received UDP response from $ip');

            // Process binary msgpack (skip 4 byte length header if present, though UDP usually doesn't need it if it's the whole packet)
            // But our backend sends it. Let's handle both.
            var payload = datagram.data;
            if (payload.length > 4) {
               final expectedLen = ByteData.sublistView(payload, 0, 4).getUint32(0, Endian.big);
               if (payload.length >= expectedLen + 4) {
                  payload = payload.sublist(4, 4 + expectedLen);
               }
            }
            
            final localProtocol = ProtocolHandler();
            final results = localProtocol.process(payload);
            for (final packet in results) {
               if (packet is Map && packet['type'].toString().toLowerCase() == 'discovery_response') {
                  final name = packet['data']?['server_name'] ?? ip;
                  if (mounted) {
                    setState(() {
                      final dev = DiscoveredDevice(ip, name);
                      if (!_foundDevices.contains(dev)) {
                        _foundDevices.add(dev);
                      }
                    });
                  }
               }
            }
          }
        }
      });

      // Close socket after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      socket.close();
    } catch (e) {
      debugPrint('❌ UDP Discovery error: $e');
    }
  }

  String _statusText = "Initializing...";

  void _onDeviceSelected(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pc_ip', ip);
    await prefs.setString('pc_port', _portController.text);
    if (mounted) Navigator.pop(context, ip);
  }

  @override
  Widget build(BuildContext context) {
    if (_isManualInput) {
       return AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Enter IP Manually", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ipController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "IP Address", labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Port", labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Back"),
            onPressed: () => setState(() => _isManualInput = false),
          ),
          FilledButton(
            child: const Text("Connect"),
            onPressed: () => _onDeviceSelected(_ipController.text),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Scanning for PC...", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          if (_isScanning)
             const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
          else 
             IconButton(
               icon: const Icon(Icons.refresh, color: Colors.white54),
               onPressed: _scanNetwork,
               tooltip: "Rescan",
             )
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ensure Wayland Connect is running on your PC.", style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
            if (_isScanning)
              Text(_statusText, style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
            const SizedBox(height: 16),
            if (_foundDevices.isEmpty && !_isScanning)
               Padding(
                 padding: const EdgeInsets.symmetric(vertical: 20),
                 child: Text(_statusText, style: const TextStyle(color: Colors.white24)),
               )
            else
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 250),
                 child: ListView.builder(
                   shrinkWrap: true,
                   itemCount: _foundDevices.length,
                   itemBuilder: (context, index) {
                     final dev = _foundDevices[index];
                     return ListTile(
                       leading: Container(
                         padding: const EdgeInsets.all(8),
                         decoration: BoxDecoration(
                           color: Colors.white.withOpacity(0.05),
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: const Icon(Icons.desktop_windows, color: Colors.white70, size: 20),
                       ),
                       title: Text(dev.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                       subtitle: Text(dev.ip, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                       trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                       onLongPress: () {
                          // Copy IP to clipboard
                          Clipboard.setData(ClipboardData(text: dev.ip));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("IP copied: ${dev.ip}"), duration: Duration(seconds: 1)));
                       },
                       onTap: () => _onDeviceSelected(dev.ip),
                     );
                   },
                 ),
               ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text("Manual Input", style: TextStyle(color: Colors.white38)),
          onPressed: () => setState(() {
             _isManualInput = true;
             _ipController.text = "192.168.1.";
          }),
        ),
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.pop(context),
        )
      ],
    );
  }
}

