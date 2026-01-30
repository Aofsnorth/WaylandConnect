import 'package:flutter/material.dart';

class DisconnectedScreen extends StatelessWidget {
  final VoidCallback onReconnect;
  final VoidCallback? onReturnHome;
  final String? lastDeviceName;

  const DisconnectedScreen({
    super.key,
    required this.onReconnect,
    this.onReturnHome,
    this.lastDeviceName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red.shade900.withOpacity(0.4), Colors.black],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.signal_wifi_off, size: 80, color: Colors.white38),
            const SizedBox(height: 32),
            const Text(
              "Connection Lost",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "The connection to your PC was interrupted.\nThis could happen if the PC was turned off\nor properly disconnected.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () {
                onReconnect();
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text("Reconnect Now", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                if (onReturnHome != null) {
                  onReturnHome!();
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text("Return to Home", style: TextStyle(color: Colors.white54)),
            )
          ],
        ),
      ),
    );
  }
}
