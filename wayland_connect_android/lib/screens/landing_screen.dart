import 'package:flutter/material.dart';
import 'settings_screen.dart';


class LandingScreen extends StatelessWidget {
  final String approvalStatus;
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onReset;

  const LandingScreen({
    super.key,
    required this.approvalStatus,
    required this.isConnected,
    required this.onConnect,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    String title = "DISCONNECTED";
    String subtitle = "Establish a link to your PC to start control";
    IconData icon = Icons.link_off_rounded;
    bool isAmber = false;
    bool isRed = false;
    bool showOkButton = false;

    if (approvalStatus == "Pending") {
      title = "WAITING FOR APPROVAL";
      subtitle = "Please approve this device on your PC Dashboard.";
      icon = Icons.security_rounded;
      isAmber = true;
    } else if (approvalStatus == "Declined" || approvalStatus == "Blocked") {
      title = approvalStatus == "Blocked" ? "ACCESS BLOCKED" : "ACCESS DECLINED";
      subtitle = approvalStatus == "Blocked" ? "This device has been permanently blocked." : "The connection request was declined.";
      icon = Icons.block;
      isRed = true;
      showOkButton = true;
    }

    Color accentColor = isAmber ? Colors.amberAccent : (isRed ? Colors.redAccent : Colors.white24);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const SettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A0A),
          image: DecorationImage(image: AssetImage('assets/images/background.png'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withOpacity(0.2)),
                ),
                child: Icon(icon, size: 64, color: accentColor.withOpacity(0.8)),
              ),
              const SizedBox(height: 48),
              Text(
                title, 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4)
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: Text(
                  subtitle, 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)
                ),
              ),
              const SizedBox(height: 60),
              if (showOkButton)
                _LandingButton(label: "O K", color: Colors.redAccent, onTap: onReset)
              else if (!isConnected)
                _LandingButton(label: "CONNECT NOW", color: Colors.white, onTap: onConnect)
              else
                 const CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _LandingButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color == Colors.white ? Colors.white : color.withOpacity(0.1),
        foregroundColor: color == Colors.white ? Colors.black : color,
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), 
          side: color == Colors.white ? BorderSide.none : BorderSide(color: color.withOpacity(0.3))
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }
}
