import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

class TouchpadScreen extends StatefulWidget {
  final Socket? socket;
  const TouchpadScreen({super.key, required this.socket});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  double _touchpadScale = 1.0;
  Timer? _inertiaTimer;
  double _currentInertiaVelocity = 0;
  double _scrollAccumulator = 0.0;

  void _sendMove(double dx, double dy) {
    if (widget.socket != null) {
      final event = {"type": "move", "data": {"dx": dx, "dy": dy}};
      try { widget.socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
    }
  }

  void _sendClick(String button) {
    HapticFeedback.lightImpact();
    if (widget.socket != null) {
      final event = {"type": "click", "data": {"button": button}};
      try { widget.socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
    }
  }

  void _sendScroll(double dy) {
    if (widget.socket != null) {
      // Sensitivity reduced to 0.15 for better control
      _scrollAccumulator += (dy * 0.15);
      
      int toSend = _scrollAccumulator.toInt();
      if (toSend != 0) {
        _scrollAccumulator -= toSend.toDouble();
        final event = {"type": "scroll", "data": {"dy": toSend}};
        try { widget.socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
      }
    }
  }

  void _startInertia(double velocity) {
    // Disabled as requested: no gliding/inertia
  }

  void _stopInertia() {
    // Disabled
  }

  @override
  void dispose() {
    _inertiaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.black.withOpacity(0.9)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 120),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    // --- MOUSE TRACKPAD AREA ---
                    Expanded(
                      flex: 5,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) => _sendMove(details.delta.dx, details.delta.dy),
                        onTapDown: (_) {
                          _stopInertia();
                          setState(() => _touchpadScale = 0.98);
                        },
                        onTapUp: (_) {
                          setState(() => _touchpadScale = 1.0);
                          _sendClick("left");
                        },
                        onTapCancel: () => setState(() => _touchpadScale = 1.0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(_touchpadScale < 1.0 ? 0.08 : 0.03),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white.withOpacity(_touchpadScale < 1.0 ? 0.2 : 0.1)),
                          ),
                          child: Center(
                            child: Icon(Icons.touch_app_outlined, size: 48, color: Colors.white.withOpacity(0.05)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // --- SCROLL STRIP AREA ---
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) => _stopInertia(),
                        onVerticalDragUpdate: (details) {
                          _stopInertia();
                          _sendScroll(details.delta.dy);
                        },
                        onVerticalDragEnd: (details) {
                          _startInertia(details.primaryVelocity ?? 0);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Center(
                            child: Icon(Icons.unfold_more, color: Colors.white24, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 24, 40, 120),
              child: SizedBox(
                height: 80,
                child: Row(
                  children: [
                    _MouseButton(label: "LEFT", onTap: () => _sendClick("left"), flex: 3),
                    const SizedBox(width: 12),
                    _MouseButton(label: "•", onTap: () => _sendClick("middle"), flex: 1),
                    const SizedBox(width: 12),
                    _MouseButton(label: "RIGHT", onTap: () => _sendClick("right"), flex: 3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MouseButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final int flex;
  const _MouseButton({required this.label, required this.onTap, required this.flex});
  @override
  State<_MouseButton> createState() => _MouseButtonState();
}

class _MouseButtonState extends State<_MouseButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: widget.flex,
      child: GestureDetector(
        onTapDown: (_) { setState(() => _isPressed = true); HapticFeedback.mediumImpact(); },
        onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_isPressed ? 0.1 : 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(_isPressed ? 0.3 : 0.1)),
          ),
          child: Center(
            child: Text(
              widget.label, 
              style: TextStyle(
                color: Colors.white.withOpacity(_isPressed ? 0.8 : 0.4), 
                fontWeight: FontWeight.w900, 
                letterSpacing: 2, 
                fontSize: 12
              )
            )
          ),
        ),
      ),
    );
  }
}
