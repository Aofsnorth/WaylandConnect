import 'dart:math' as math;
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';

class PointerVisualState {
    final double width;
    final double height;
    final double radius;
    final double strokeWidth;
    final Color color;
    final double fillAlpha;

    PointerVisualState({
       required this.width, required this.height, required this.radius, 
       required this.strokeWidth, required this.color, required this.fillAlpha
    });
}

class PointerVisualStateTween extends Tween<PointerVisualState> {
  PointerVisualStateTween({PointerVisualState? begin, PointerVisualState? end}) : super(begin: begin, end: end);

  @override
  PointerVisualState lerp(double t) {
    if (begin == null || end == null) return begin ?? end!;
    return PointerVisualState(
       width: lerpDouble(begin!.width, end!.width, t)!,
       height: lerpDouble(begin!.height, end!.height, t)!,
       radius: lerpDouble(begin!.radius, end!.radius, t)!,
       strokeWidth: lerpDouble(begin!.strokeWidth, end!.strokeWidth, t)!,
       color: Color.lerp(begin!.color, end!.color, t)!,
       fillAlpha: lerpDouble(begin!.fillAlpha, end!.fillAlpha, t)!
    );
  }
}

class PointerShapePainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double fillAlpha;
  final int mode;
  final int particleType;
  final double zoomScale;
  final String? customImagePath;

  PointerShapePainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.fillAlpha,
    required this.mode,
    required this.particleType,
    required this.zoomScale,
    this.customImagePath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Draw background dot if custom image is present (Mode 6)
    if (mode == 6 && customImagePath != null) {
       // Just draw a basic shape as background for image
       final p = Paint()..color = Colors.black;
       canvas.drawRRect(rrect, p);
       return; 
    }

    // Surgical Masking for Hollow Modes
    if (fillAlpha < 0.5) {
      canvas.saveLayer(rect.inflate(100), Paint());
    }

    // 1. VOLUMETRIC MONOCHROME GLOW (Hitam Putih Default -> Colored for Laser)
    final glowPaint = Paint()
      ..style = fillAlpha < 0.5 ? PaintingStyle.stroke : PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    
    // Layer 1: Soft Colored Glow (Was White)
    // "Semua laser di android memiliki glow" - using color
    glowPaint.color = color.withOpacity(0.6);
    glowPaint.strokeWidth = strokeWidth + 12;
    _drawManifestation(canvas, rrect, glowPaint, mode, particleType);

    // Layer 2: Deep Black Shadow
    glowPaint.color = Colors.black.withOpacity(0.4);
    glowPaint.strokeWidth = strokeWidth + 25;
    glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 35);
    _drawManifestation(canvas, rrect, glowPaint, mode, particleType);

    // 2. HIGH CONTRAST BORDER
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = fillAlpha < 0.5 ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = strokeWidth + 4;
    _drawManifestation(canvas, rrect, borderPaint, mode, particleType);

    // 3. MAIN SHAPE
    final mainPaint = Paint()
      ..color = color
      ..style = fillAlpha < 0.5 ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = strokeWidth;
    _drawManifestation(canvas, rrect, mainPaint, mode, particleType);

    // 3.5 COMET TRAIL (Mode 6 Special) - Match Linux Design
    if (mode == 6) {
       // Draw a trail of circles/shapes behind the main one
       // "Visual hp matches Linux" -> Linux draws ~45 points trail.
       // We simulate a static curve trail for the preview
       final center = rect.center;
       for (int i = 1; i <= 6; i++) {
          double offset = i * 16.0 * zoomScale;
          double scale = 1.0 - (i * 0.14);
          if (scale <= 0) break;
          double opacity = (0.6 - (i * 0.1)).clamp(0.0, 1.0);
          
          final trailPaint = Paint()
            ..color = color.withOpacity(opacity)
            ..style = PaintingStyle.fill;
             
          // Trail points UPWARDS so the overall design "faces down"
          // Or if user means the tail points down, then Offset(0, offset)
          // "menghadap kebawah tailnya" usually means the tail is at the bottom.
          final pos = center + Offset(0, offset); 
          final size = rrect.width * scale * 0.9;
          
          if (particleType == 1) {
             _drawStar(canvas, pos, 5, size * 0.4, size / 2, trailPaint);
          } else if (particleType == 2) {
             _drawPolygon(canvas, pos, 3, size, trailPaint);
          } else if (particleType == 3) {
             _drawPolygon(canvas, pos, 4, size, trailPaint);
          } else {
             canvas.drawCircle(pos, size / 2, trailPaint);
             // Small dot in trail particles too for core look
             final dotP = Paint()..color = color.withOpacity(opacity)..style = PaintingStyle.fill;
             canvas.drawCircle(pos, size * 0.12, dotP);
          }
        }
    }

    // 4. THE PUNCH (Ensure Transparency)
    if (fillAlpha < 0.5) {
      final punchPaint = Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.fill;
      
      final punchRect = rect.deflate(strokeWidth / 2);
      final punchRRect = RRect.fromRectAndRadius(punchRect, Radius.circular(math.max(radius - strokeWidth/2, 0)));
      _drawManifestation(canvas, punchRRect, punchPaint, mode, particleType);
      
      canvas.restore();
    }
  }

  void _drawManifestation(Canvas canvas, RRect rrect, Paint paint, int mode, int particleType) {
    if (mode == 6) {
      final center = rrect.center;
      final size = rrect.width; // Assuming squareish
      switch (particleType) {
        case 1: // Star
          _drawStar(canvas, center, 5, size * 0.4, size * 1.0, paint);
          break;
        case 2: // Triangle
          _drawPolygon(canvas, center, 3, size * 1.0, paint);
          break;
        case 3: // Diamond
          _drawPolygon(canvas, center, 4, size * 1.0, paint);
          break;
        default:
          canvas.drawCircle(center, size / 2, paint);
          // High-contrast Core Dot
          final corePaint = Paint()
            ..color = paint.color
            ..style = PaintingStyle.fill;
          canvas.drawCircle(center, size * 0.18, corePaint);
      }
    } else {
      canvas.drawRRect(rrect, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, int points, double innerRadius, double outerRadius, Paint paint) {
    final path = Path();
    final angle = math.pi / points;
    for (int i = 0; i < 2 * points; i++) {
        final r = i % 2 == 0 ? outerRadius : innerRadius;
        final a = i * angle - math.pi / 2;
        final x = center.dx + math.cos(a) * r;
        final y = center.dy + math.sin(a) * r;
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPolygon(Canvas canvas, Offset center, int sides, double radius, Paint paint) {
    final path = Path();
    final angle = 2 * math.pi / sides;
    for (int i = 0; i < sides; i++) {
        final a = i * angle - math.pi / 2;
        final x = center.dx + math.cos(a) * radius;
        final y = center.dy + math.sin(a) * radius;
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PointerShapePainter oldDelegate) {
     return oldDelegate.color != color || oldDelegate.radius != radius || oldDelegate.mode != mode || oldDelegate.fillAlpha != fillAlpha;
  }
}
