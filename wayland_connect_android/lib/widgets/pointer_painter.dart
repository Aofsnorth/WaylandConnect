import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class PointerParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double life;
  double hueShift; // Color variation
  
  PointerParticle({
    required this.x, required this.y, 
    required this.vx, required this.vy, 
    required this.size, required this.life,
    required this.hueShift
  });
}

class PointerPainter extends CustomPainter {
  final double animValue;
  final double morphValue;
  final double lifeValue;
  final bool isActive;
  final int mode;
  final double pointerScale;
  final Color color;
  final int particleType;
  final List<PointerParticle> particles;

  PointerPainter({
    required this.animValue,
    required this.morphValue,
    required this.lifeValue,
    required this.isActive,
    required this.mode,
    required this.pointerScale,
    required this.color,
    required this.particleType,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. STATEFUL PARTICLE SYSTEM (Idle + Active + Explode)
    final HSLColor baseHsl = HSLColor.fromColor(color);

    for (var p in particles) {
      double opacity = (math.sin(p.life * math.pi) * 0.8 + 0.2); // Twinkle
      if (isActive) opacity = 0.8 + 0.2 * math.sin(animValue * 10);
      
      final Color pColor = baseHsl.withHue((baseHsl.hue + p.hueShift) % 360).toColor();

      final Paint paint = Paint()
        ..color = pColor.withOpacity(opacity.clamp(0.0, 1.0))
        ..strokeCap = StrokeCap.round
        ..strokeWidth = p.size
        ..maskFilter = isActive ? const MaskFilter.blur(BlurStyle.normal, 3) : null;

      final Offset pos = Offset(p.x, p.y);
      
      if (isActive && (p.vx.abs() > 0.1 || p.vy.abs() > 0.1)) {
        final Offset tail = Offset(p.x - p.vx * 1.5, p.y - p.vy * 1.5);
        canvas.drawLine(pos, tail, paint);
      } else {
        if (particleType == 1) {
          _drawStar(canvas, pos, 5, p.size, p.size / 2, paint);
        } else {
          canvas.drawCircle(pos, p.size, paint);
        }
      }
    }

    // 2. MOLECULAR BEAM (Intro/Death)
    if (lifeValue > 0.001) {
      final center = Offset(size.width / 2, 0); 
      int layers = 20;
      for (int i = 0; i < layers; i++) {
        double progress = i / layers;
        double spread = 40.0 * progress * lifeValue; 
        double targetY = (size.height * 0.4) * progress * lifeValue; 
        double scale = (1.0 - progress) * lifeValue;
        if (scale <= 0) continue;

        int particlesPerRow = (spread / 5).ceil().clamp(1, 10);
        for (int j = 0; j <= particlesPerRow; j++) {
          double xOffset = (j / particlesPerRow - 0.5) * 2 * spread; 
          final pos = center + Offset(xOffset, targetY);
          double pSize = (3.0 + 2.0 * math.sin(animValue * 10 + i + j)) * scale;
          double pOpacity = (0.5 + 0.5 * math.cos(animValue * 5 + j)).clamp(0.0, 1.0) * scale;
          canvas.drawCircle(pos, pSize, Paint()..color = color.withOpacity(pOpacity)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        }
      }
      canvas.drawCircle(center, 15 * lifeValue, Paint()..color = Colors.white.withOpacity(0.9 * lifeValue)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15));
    }

    final rect = Offset.zero & size;
    // Note: The actual pointer shape is handled by the preview indicator in the app, 
    // while the real pointer is on the PC.
  }

  void _drawStar(Canvas canvas, Offset center, int points, double innerRadius, double outerRadius, Paint paint) {
    var angle = math.pi / points;
    var path = Path();
    for (var i = 0; i < 2 * points; i++) {
      var r = i % 2 == 0 ? outerRadius : innerRadius;
      var x = center.dx + math.cos(i * angle) * r;
      var y = center.dy + math.sin(i * angle) * r;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PointerPainter old) {
    return old.animValue != animValue ||
           old.morphValue != morphValue ||
           old.lifeValue != lifeValue ||
           old.isActive != isActive ||
           old.mode != mode ||
           old.pointerScale != pointerScale ||
           old.color != color ||
           old.particleType != particleType ||
           old.particles != particles;
  }
}
