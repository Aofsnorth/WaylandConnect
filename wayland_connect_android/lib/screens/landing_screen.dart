import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:io';
import 'settings_screen.dart';
import 'package:wayland_connect_android/l10n/app_localizations.dart';

class LandingScreen extends StatefulWidget {
  final String approvalStatus;
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onReset;
  final Socket? socket;

  const LandingScreen({
    super.key,
    required this.approvalStatus,
    required this.isConnected,
    required this.onConnect,
    required this.onReset,
    this.socket,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String title = AppLocalizations.of(context)!.disconnected;
    String subtitle = AppLocalizations.of(context)!.establishConnection;
    IconData icon = Icons.offline_bolt_rounded;
    Color statusColor = Colors.white24;
    bool showOkButton = false;

    if (widget.approvalStatus == "Pending") {
      title = AppLocalizations.of(context)!.waitingForApproval;
      subtitle = AppLocalizations.of(context)!.checkPcNotifications;
      icon = Icons.security_rounded;
      statusColor = Colors.amberAccent;
    } else if (widget.approvalStatus == "Declined" || widget.approvalStatus == "Blocked") {
      title = widget.approvalStatus == "Blocked" ? AppLocalizations.of(context)!.accessBlocked : AppLocalizations.of(context)!.accessDeclined;
      subtitle = AppLocalizations.of(context)!.permissionsRevoked;
      icon = Icons.gpp_bad_rounded;
      statusColor = Colors.redAccent;
      showOkButton = true;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF020202),
      body: Stack(
        children: [
          // 1. CYBER GRID BACKGROUND
          Positioned.fill(
            child: CustomPaint(
              painter: LandingGridPainter(
                color: statusColor.withOpacity(0.05),
                scanProgress: _scanController.value,
              ),
            ),
          ),

          // 2. AMBIENT GLOW
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [statusColor.withOpacity(0.08), Colors.transparent],
                ),
              ),
            ),
          ),

          // 3. MAIN CONTENT
          SafeArea(
            child: Column(
              children: [
                 _buildTopBar(context),
                 const Spacer(),
                 _buildStatusIcon(icon, statusColor),
                 const SizedBox(height: 40),
                 _buildTextSection(title, subtitle, statusColor),
                 const SizedBox(height: 60),
                 if (showOkButton)
                   _LandingButton(label: AppLocalizations.of(context)!.resetConnection, color: Colors.redAccent, onTap: widget.onReset)
                 else if (!widget.isConnected)
                   _LandingButton(label: AppLocalizations.of(context)!.connect, color: Colors.white, onTap: widget.onConnect)
                  else if (widget.approvalStatus == "Pending")
                    Column(
                      children: [
                        const CircularProgressIndicator(color: Colors.amberAccent, strokeWidth: 2),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context)!.waitingForApproval, style: const TextStyle(color: Colors.amberAccent, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 30),
                        _LandingButton(label: AppLocalizations.of(context)!.cancel, color: Colors.white24, onTap: widget.onReset),
                      ],
                    )
                  else
                    Column(
                      children: [
                        const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context)!.syncing, style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 4, fontWeight: FontWeight.bold)),
                      ],
                    ),
                 const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white24),
            onPressed: () {
               Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(
                 onBack: () => Navigator.pop(context),
                 socket: widget.socket,
               )));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Icon(icon, size: 80, color: color.withOpacity(0.8)),
    );
  }

  Widget _buildTextSection(String title, String subtitle, Color color) {
    return Column(
      children: [
        Text(
          title, 
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 6)
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: Text(
            subtitle, 
            textAlign: TextAlign.center, 
            style: TextStyle(color: color.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
        ),
      ],
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 22),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, spreadRadius: -5)
              ]
            ),
            child: Text(
              label, 
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 4)
            ),
          ),
        ),
      ),
    );
  }
}

class LandingGridPainter extends CustomPainter {
  final Color color;
  final double scanProgress;
  LandingGridPainter({required this.color, required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    
    // Draw Grid
    for (double i = 0; i <= size.width; i += 45) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i <= size.height; i += 45) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    // Draw Top Glowing Line (Fixed at top as requested)
    final scanPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.5), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 150));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 150), scanPaint);
    
    // Draw thin solid line at the very top for definition
    final topLinePaint = Paint()..color = color.withOpacity(0.8)..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), topLinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

