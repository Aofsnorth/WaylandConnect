import 'dart:math' as math;
import 'package:flutter/material.dart';

class RotatingOrbitalGlow extends StatefulWidget {
  final Color accent;
  final bool isPlaying;
  final double size;
  final double orbitRadius;
  const RotatingOrbitalGlow({
    super.key,
    required this.accent,
    required this.isPlaying,
    this.size = 180,
    this.orbitRadius = 60,
  });

  @override
  State<RotatingOrbitalGlow> createState() => _RotatingOrbitalGlowState();
}

class _RotatingOrbitalGlowState extends State<RotatingOrbitalGlow> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(RotatingOrbitalGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _ctrl.repeat();
      } else {
        _ctrl.animateTo(0.0, duration: const Duration(milliseconds: 1200), curve: Curves.easeOutBack);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _OrbitalGlowPainter(widget.accent, _ctrl.value, widget.orbitRadius),
        size: Size(widget.size, widget.size),
      ),
    );
  }
}

class _OrbitalGlowPainter extends CustomPainter {
  final Color color;
  final double angle;
  final double orbitRadius;
  _OrbitalGlowPainter(this.color, this.angle, this.orbitRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final a1 = -angle * 2 * math.pi;
    final orbSize = orbitRadius / 2.8;

    canvas.drawCircle(
      center + Offset(math.cos(a1) * orbitRadius, math.sin(a1) * orbitRadius),
      orbSize / 2,
      Paint()..color = color.withOpacity(0.8)..style = PaintingStyle.fill,
    );

    for (int i = 0; i < 3; i++) {
      double r = orbitRadius * (0.6 + i * 0.3);
      // Integer multipliers ensure perfect looping at angle 0.0 and 1.0
      double speed = (i % 2 == 0 ? 1 : -1) * (1.0 + i); 
      double a = angle * 2 * math.pi * speed + (i * 2.1);
      double s = orbSize * (0.3 + i * 0.2);
      canvas.drawCircle(
        center + Offset(math.cos(a) * r, math.sin(a) * r),
        s / 2,
        Paint()..color = color.withOpacity(0.4 - (i * 0.1))..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalGlowPainter old) {
    return old.color != color || old.angle != angle || old.orbitRadius != orbitRadius;
  }
}

class CyberPainter extends CustomPainter {
  final Color c1, c2;
  final double v;
  final bool active;
  CyberPainter(this.c1, this.c2, this.v, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    final gridPaint = Paint()
      ..color = c1.withOpacity(0.04)
      ..strokeWidth = 0.5;

    double gridSpacing = 40;
    double pan = v * 20;
    for (double i = -gridSpacing; i < w + gridSpacing; i += gridSpacing) {
      canvas.drawLine(Offset(i + pan % gridSpacing, 0), Offset(i + pan % gridSpacing, h), gridPaint);
    }
    for (double i = -gridSpacing; i < h + gridSpacing; i += gridSpacing) {
      canvas.drawLine(Offset(0, i + pan % gridSpacing), Offset(w, i + pan % gridSpacing), gridPaint);
    }

    final streamPaint = Paint()..strokeWidth = 1.0;
    for (int i = 0; i < 15; i++) {
      double x = (i * w / 15) + (math.sin(v * 2 * math.pi + i) * 10);
      double y = (v * h * (1 + i % 3) / 2) % h;
      streamPaint.color = c1.withOpacity(0.03);
      canvas.drawLine(Offset(x, y), Offset(x, y + 40), streamPaint);
      if (i % 4 == 0) {
        canvas.drawCircle(Offset(x, y), 1.0, streamPaint..color = c1.withOpacity(0.1));
      }
    }

    final scanPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, c1.withOpacity(0.08), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, (v * h) % h, w, 60));
    canvas.drawRect(Rect.fromLTWH(0, (v * h) % h, w, 60), scanPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < 4; i++) {
      double r = 160.0 + i * 50;
      double startAngle = (v * (i + 1) * math.pi);
      ringPaint.color = c1.withOpacity(0.06 / (i + 1));
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), startAngle, 1.2, false, ringPaint);
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), -startAngle, 0.7, false, ringPaint);
    }

    final cornerPaint = Paint()..color = c1.withOpacity(0.3)..strokeWidth = 2.0;
    double cS = 25;
    canvas.drawLine(const Offset(15, 60), Offset(15 + cS, 60), cornerPaint);
    canvas.drawLine(const Offset(15, 60), Offset(15, 60 + cS), cornerPaint);
    canvas.drawLine(Offset(w - 15, h - 15), Offset(w - 15 - cS, h - 15), cornerPaint);
    canvas.drawLine(Offset(w - 15, h - 15), Offset(w - 15, h - 15 - cS), cornerPaint);
    canvas.drawCircle(Offset(15 + cS + 5, 60), 1.5, cornerPaint);
    canvas.drawCircle(Offset(w - 15 - cS - 5, h - 15), 1.5, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CyberPainter old) {
    return old.c1 != c1 || old.c2 != c2 || old.v != v || old.active != active;
  }
}

class OrbitalStatus extends StatelessWidget {
  final Color accent;
  final String label, value;
  const OrbitalStatus({super.key, required this.accent, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: accent.withOpacity(0.4), fontSize: 5, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(3)),
          child: Text(value, style: TextStyle(color: accent, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        ),
      ],
    );
  }
}

class OrbitalRingPainter extends CustomPainter {
  final Color color;
  OrbitalRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    double s = 12;
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 3.14, 1.57, false, paint);
    canvas.drawArc(Rect.fromLTWH(size.width - s, 0, s, s), 4.71, 1.57, false, paint);
    canvas.drawArc(Rect.fromLTWH(0, size.height - s, s, s), 1.57, 1.57, false, paint);
    canvas.drawArc(Rect.fromLTWH(size.width - s, size.height - s, s, s), 0, 1.57, false, paint);
  }

  @override
  bool shouldRepaint(covariant OrbitalRingPainter old) => false;
}

class AbstractSideCard extends StatelessWidget {
  final Color accent;
  const AbstractSideCard({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 100,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.1)),
      ),
      child: Stack(
        children: [
          Positioned(top: 10, left: 18, child: Container(width: 2, height: 80, color: accent.withOpacity(0.2))),
          Positioned(top: 20, left: 8, right: 8, child: Container(height: 1, color: accent.withOpacity(0.3))),
          Positioned(bottom: 20, left: 8, right: 8, child: Container(height: 1, color: accent.withOpacity(0.3))),
          Positioned(top: 40, left: 0, right: 0, child: Icon(Icons.blur_on, color: accent.withOpacity(0.5), size: 16)),
        ],
      ),
    );
  }
}
