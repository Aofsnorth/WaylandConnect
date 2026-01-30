import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import '../utils/protocol.dart';
import 'package:wayland_connect_android/l10n/app_localizations.dart';

class TouchpadScreen extends StatefulWidget {
  final Socket? socket;
  const TouchpadScreen({super.key, required this.socket});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> with TickerProviderStateMixin {
  // Trackpad States
  double _touchpadScale = 1.0;
  double _scrollAccumulator = 0.0;
  Offset _touchPosition = Offset.zero;
  bool _isTouching = false;
  bool _isScrolling = false;

  // Ripple Effect
  final List<_RippleEffect> _ripples = [];

  @override
  void initState() {
    super.initState();
    // Entry animations disabled as per user request
  }

  @override
  void dispose() {
    for (var ripple in _ripples) {
      ripple.controller.dispose();
    }
    super.dispose();
  }

  void _addRipple(Offset position) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final ripple = _RippleEffect(position, controller);
    setState(() => _ripples.add(ripple));
    controller.forward().then((_) {
      setState(() => _ripples.remove(ripple));
      controller.dispose();
    });
  }

  void _sendMove(double dx, double dy) {
    if (widget.socket != null) {
      final event = {
        "type": "move",
        "data": {"dx": dx, "dy": dy}
      };
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
    }
  }

  void _sendClick(String button) {
    HapticFeedback.mediumImpact();
    if (widget.socket != null) {
      final event = {
        "type": "click",
        "data": {"button": button}
      };
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
    }
  }

  void _sendScroll(double dy) {
    if (widget.socket != null) {
      _scrollAccumulator += (dy * 0.15);
      int toSend = _scrollAccumulator.toInt();
      if (toSend != 0) {
        _scrollAccumulator -= toSend.toDouble();
        final event = {
          "type": "scroll",
          "data": {"dy": toSend.toDouble()}
        };
        try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Colors.white;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
          opacity: 0.15,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // --- HEADER ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.of(context)!.virtual, style: TextStyle(color: accentColor.withOpacity(0.5), fontWeight: FontWeight.bold, letterSpacing: 4, fontSize: 8)),
                          Text(AppLocalizations.of(context)!.trackpad, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -1)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
  
                // --- MAIN INTERACTION AREA ---
                Expanded(
                  flex: 10,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Row(
                      children: [
                        // --- TRACKPAD AREA ---
                        Expanded(
                          flex: 6,
                          child: Listener(
                            onPointerDown: (details) => setState(() { _isTouching = true; _touchPosition = details.localPosition; }),
                            onPointerMove: (details) => setState(() => _touchPosition = details.localPosition),
                            onPointerUp: (details) => setState(() => _isTouching = false),
                            child: Transform.scale(
                              scale: _touchpadScale,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (details) => _sendMove(details.delta.dx, details.delta.dy),
                                onTapDown: (details) {
                                  setState(() => _touchpadScale = 0.98);
                                  _addRipple(details.localPosition);
                                },
                                onTapUp: (_) {
                                  setState(() => _touchpadScale = 1.0);
                                  _sendClick("left");
                                },
                                onTapCancel: () => setState(() => _touchpadScale = 1.0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutExpo,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(_isTouching ? 0.08 : 0.03),
                                    borderRadius: BorderRadius.circular(35),
                                    border: Border.all(
                                      color: _isTouching ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.08), 
                                      width: _isTouching ? 2.0 : 1.5
                                    ),
                                    boxShadow: _isTouching ? [
                                      BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 30, spreadRadius: 0)
                                    ] : [],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(35),
                                    child: Stack(
                                      children: [
                                        // --- DYNAMIC GRID BACKGROUND ---
                                        RepaintBoundary(
                                          child: Opacity(
                                            opacity: 0.05,
                                            child: CustomPaint(
                                              painter: _TrackpadGridPainter(),
                                              size: Size.infinite,
                                            ),
                                          ),
                                        ),
                                        
                                        // Interactive Touch Aura
                                        if (_isTouching)
                                          TweenAnimationBuilder<double>(
                                            tween: Tween(begin: 0.0, end: 1.0),
                                            duration: const Duration(milliseconds: 200),
                                            builder: (context, value, child) {
                                              return Positioned(
                                                left: _touchPosition.dx - (60 * value),
                                                top: _touchPosition.dy - (60 * value),
                                                child: Container(
                                                  width: 120 * value, height: 120 * value,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: RadialGradient(
                                                      colors: [
                                                        Colors.white.withOpacity(0.25 * value),
                                                        Colors.white.withOpacity(0.05 * value),
                                                        Colors.transparent
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          ),
                                        
                                        // Click Ripples
                                        ..._ripples.map((ripple) => AnimatedBuilder(
                                          animation: ripple.controller,
                                          builder: (context, child) {
                                            final value = ripple.controller.value;
                                            final opacity = (1.0 - value).clamp(0.0, 1.0);
                                            final scale = 0.2 + (value * 1.8);
                                            return Positioned(
                                              left: ripple.position.dx - 50,
                                              top: ripple.position.dy - 50,
                                              child: Opacity(
                                                opacity: opacity,
                                                child: Transform.scale(
                                                  scale: scale,
                                                  child: Container(
                                                    width: 100,
                                                    height: 100,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                                                      gradient: RadialGradient(
                                                        colors: [
                                                          Colors.white.withOpacity(0.2),
                                                          Colors.transparent
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        )),
                                        const Center(
                                          child: Opacity(
                                            opacity: 0.03,
                                            child: Icon(Icons.gesture_rounded, size: 80, color: Colors.white),
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
                        const SizedBox(width: 15),
                        // --- SCROLL BAR ---
                        _buildScrollStrip(accentColor),
                      ],
                    ),
                  ),
                ),
  
                const SizedBox(height: 10),
                // --- MOUSE BUTTONS ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 0, 25, 100),
                  child: SizedBox(
                    height: 45,
                    child: Row(
                      children: [
                        _MouseButton(label: AppLocalizations.of(context)!.left, onTap: () => _sendClick("left"), flex: 3, accent: accentColor),
                        const SizedBox(width: 15),
                        _MouseButton(label: AppLocalizations.of(context)!.middle, onTap: () => _sendClick("middle"), flex: 1, accent: accentColor, isMiddle: true),
                        const SizedBox(width: 15),
                        _MouseButton(label: AppLocalizations.of(context)!.right, onTap: () => _sendClick("right"), flex: 3, accent: accentColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollStrip(Color accent) {
    return Expanded(
      flex: 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _isScrolling = true),
        onVerticalDragUpdate: (details) => _sendScroll(details.delta.dy),
        onVerticalDragEnd: (_) => setState(() => _isScrolling = false),
        onVerticalDragCancel: () => setState(() => _isScrolling = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _isScrolling ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(35),
            border: Border.all(
              color: _isScrolling ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.08),
              width: _isScrolling ? 1.5 : 1.0,
            ),
            boxShadow: _isScrolling ? [
              BoxShadow(color: Colors.white.withOpacity(0.05), blurRadius: 15, spreadRadius: 0)
            ] : [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(8, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _isScrolling ? 6 : 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: _isScrolling ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
              ),
              Positioned(
                bottom: 20,
                child: Opacity(
                  opacity: _isScrolling ? 0.8 : 0.2,
                  child: const Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MouseButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final int flex;
  final Color accent;
  final bool isMiddle;

  const _MouseButton({required this.label, required this.onTap, required this.flex, required this.accent, this.isMiddle = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isMiddle ? 0.05 : 0.08),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Center(
              child: isMiddle 
                ? Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.white.withOpacity(0.4), blurRadius: 8, spreadRadius: 1),
                      ],
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RippleEffect {
  final Offset position;
  final AnimationController controller;
  _RippleEffect(this.position, this.controller);
}

class _TrackpadGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 0.5;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
