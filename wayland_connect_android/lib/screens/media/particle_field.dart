import 'dart:math' as math;
import 'package:flutter/material.dart';

class MusicParticleField extends StatefulWidget {
  final bool isPlaying;
  final Color accent;
  final Map<String, double>? spectrum;
  final List<Color>? paletteColors;
  final int frameShape;
  final double speedMultiplier;
  final double densityMultiplier;
  final double sizeMultiplier;
  final int particleShape;
  final List<Offset>? customShapePath;

  const MusicParticleField({
    super.key,
    required this.isPlaying,
    required this.accent,
    this.spectrum,
    this.paletteColors,
    this.frameShape = 0,
    this.speedMultiplier = 1.0,
    this.densityMultiplier = 1.0,
    this.sizeMultiplier = 1.0,
    this.particleShape = 0,
    this.customShapePath,
  });

  @override
  State<MusicParticleField> createState() => _MusicParticleFieldState();
}

class _MusicParticleFieldState extends State<MusicParticleField> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_BgParticle> _particles = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _ctrl.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_particles.isEmpty) {
      for (int i = 0; i < 50; i++) {
        _spawnParticle(force: true);
        _particles.last.life = _rng.nextDouble();
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    int maxParticles = (80 * widget.densityMultiplier).toInt();
    if (_particles.length < maxParticles) {
      if (_rng.nextDouble() > 0.8) _spawnParticle();
    }

    final double bass = widget.spectrum?['low'] ?? 0.0;

    for (var p in _particles) {
      if (p.state == 0) {
        p.opacity += 0.02;
        if (p.opacity >= 1.0) {
          p.opacity = 1.0;
          p.state = 1;
        }
      } else if (p.state == 1) {
        p.life -= p.decay;
        if (p.life <= 0) p.state = 2;
      } else {
        p.opacity -= 0.02;
      }

      // Optimize trail: Efficiently update trail offsets
      if (p.trail.length >= 10) {
        for (int i = p.trail.length - 1; i > 0; i--) {
          p.trail[i] = p.trail[i - 1];
        }
        p.trail[0] = Offset(p.x, p.y);
      } else {
        p.trail.insert(0, Offset(p.x, p.y));
      }

      double bassFactor = math.pow(bass, 1.2).toDouble(); // Reduced power for more sensitivity
      
      // Smooth transition between playing/paused speeds to reduce lag
      double targetSpeedMultiplier = widget.isPlaying ? (1.0 + bassFactor * 12.0) : 0.2; // Increased multiplier from 5.0 to 12.0
      p.actualSpeedMultiplier = p.actualSpeedMultiplier + (targetSpeedMultiplier - p.actualSpeedMultiplier) * 0.15;
      
      double speed = p.speed * widget.speedMultiplier * p.actualSpeedMultiplier;
      p.y -= speed;
      p.x += math.sin(p.y * 0.01 + p.offset) * 0.2;

      p.rotation += p.rSpeed * (widget.isPlaying ? 2 : 0.5);

      if (p.y < -50 || (p.opacity <= 0 && p.state == 2)) {
        _resetParticle(p);
      }
    }
  }

  void _spawnParticle({bool force = false}) {
    _particles.add(_createParticle());
  }

  _BgParticle _createParticle() {
    double w = MediaQuery.of(context).size.width;
    double h = MediaQuery.of(context).size.height;
    final p = _BgParticle(
      x: _rng.nextDouble() * w,
      y: h + _rng.nextDouble() * 100,
      size: (2.0 + _rng.nextDouble() * 3.0) * widget.sizeMultiplier,
      speed: 0.5 + _rng.nextDouble() * 1.5,
      life: 0.5 + _rng.nextDouble() * 0.5,
      decay: 0.002 + _rng.nextDouble() * 0.003,
      shape: _rng.nextInt(7), // Increased range for more shapes
      rotation: _rng.nextDouble() * math.pi * 2,
      rSpeed: (_rng.nextDouble() - 0.5) * 0.1,
      offset: _rng.nextDouble() * 100,
      hueShift: (_rng.nextDouble() - 0.5) * 60.0,
    );

    _assignParticleColor(p);
    return p;
  }

  void _assignParticleColor(_BgParticle p) {
    if (widget.paletteColors != null && widget.paletteColors!.isNotEmpty) {
      p.color = widget.paletteColors![_rng.nextInt(widget.paletteColors!.length)];
    } else {
      p.color = widget.accent;
    }
  }

  void _resetParticle(_BgParticle p) {
    double w = MediaQuery.of(context).size.width;
    double h = MediaQuery.of(context).size.height;
    p.x = _rng.nextDouble() * w;
    p.y = h + 10;
    p.life = 0.5 + _rng.nextDouble() * 0.5;
    p.state = 0;
    p.opacity = 0;

    _assignParticleColor(p);

    p.size = (2.0 + _rng.nextDouble() * 3.0) * widget.sizeMultiplier;
    p.trail.clear();
    p.hueShift = (_rng.nextDouble() - 0.5) * 60.0;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _MusicParticlePainter(
              particles: _particles,
              accent: widget.accent,
              isPlaying: widget.isPlaying,
              spectrum: widget.spectrum,
              frameShape: widget.frameShape,
              particleShape: widget.particleShape,
              customShapePath: widget.customShapePath,
            ),
          );
        },
      ),
    );
  }
}

class _BgParticle {
  double x, y, size, speed, life, decay, rotation, rSpeed, offset, hueShift;
  double opacity = 0;
  double actualSpeedMultiplier = 1.0;
  int state = 0;
  int shape;

  _BgParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.life,
    required this.decay,
    required this.shape,
    required this.rotation,
    required this.rSpeed,
    required this.offset,
    required this.hueShift,
  });

  List<Offset> trail = [];
  Color color = Colors.white;
}

class _MusicParticlePainter extends CustomPainter {
  final List<_BgParticle> particles;
  final Color accent;
  final bool isPlaying;
  final Map<String, double>? spectrum;
  final int frameShape;
  final int particleShape;
  final List<Offset>? customShapePath;

  _MusicParticlePainter({
    required this.particles,
    required this.accent,
    required this.isPlaying,
    this.spectrum,
    required this.frameShape,
    required this.particleShape,
    this.customShapePath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final double bass = spectrum?['low'] ?? 0.0;

    for (var p in particles) {
      final Color pColor = p.color;

      if (p.trail.isNotEmpty) {
        paint.style = PaintingStyle.stroke;
        paint.strokeCap = StrokeCap.round;
        final trailPath = Path();
        trailPath.moveTo(p.x, p.y);
        for (int i = 0; i < p.trail.length; i++) {
          trailPath.lineTo(p.trail[i].dx, p.trail[i].dy);
        }
        paint.color = pColor.withOpacity(p.opacity * 0.3);
        paint.strokeWidth = p.size * 0.8;
        canvas.drawPath(trailPath, paint);
        paint.style = PaintingStyle.fill;
      }

      paint.color = pColor.withOpacity(p.opacity * (0.7 + bass * 0.3));
      if (!isPlaying) paint.color = Colors.white.withOpacity(p.opacity * 0.1);

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);

      int activeShape = particleShape == 0 ? p.shape : particleShape - 1;

      _drawShape(canvas, activeShape, p.size, paint);
      
      canvas.restore();
    }
  }

  void _drawShape(Canvas canvas, int shape, double size, Paint paint) {
    double s = size;
    switch (shape) {
      case 0: // Circle
        canvas.drawCircle(Offset.zero, s / 2, paint);
        break;
      case 1: // Square
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s, height: s), paint);
        break;
      case 2: // Triangle
        final path = Path();
        path.moveTo(0, -s / 2);
        path.lineTo(s / 2, s / 2);
        path.lineTo(-s / 2, s / 2);
        path.close();
        canvas.drawPath(path, paint);
        break;
      case 3: // Star
        final path = Path();
        int points = 5;
        double outerRadius = s / 2;
        double innerRadius = s / 4;
        for (int i = 0; i < points * 2; i++) {
          double radius = i % 2 == 0 ? outerRadius : innerRadius;
          double angle = i * math.pi / points;
          double x = radius * math.sin(angle);
          double y = -radius * math.cos(angle);
          if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
        }
        path.close();
        canvas.drawPath(path, paint);
        break;
      case 4: // Heart
        final path = Path();
        double w = s;
        double h = s;
        path.moveTo(0, h * 0.35);
        path.cubicTo(w * 0.2, h * 0.1, w * 0.5, h * 0.2, 0, h * 0.8);
        path.cubicTo(-w * 0.5, h * 0.2, -w * 0.2, h * 0.1, 0, h * 0.35);
        canvas.drawPath(path, paint);
        break;
      case 5: // Hexagon
        final path = Path();
        for (int i = 0; i < 6; i++) {
          double angle = i * math.pi / 3;
          double x = (s / 2) * math.cos(angle);
          double y = (s / 2) * math.sin(angle);
          if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
        }
        path.close();
        canvas.drawPath(path, paint);
        break;
      case 6: // Custom Path
        if (customShapePath != null && customShapePath!.isNotEmpty) {
          final path = Path();
          // Translate path to center
          path.moveTo((customShapePath![0].dx - 0.5) * s, (customShapePath![0].dy - 0.5) * s);
          for (int i = 1; i < customShapePath!.length; i++) {
            path.lineTo((customShapePath![i].dx - 0.5) * s, (customShapePath![i].dy - 0.5) * s);
          }
          path.close();
          canvas.drawPath(path, paint);
        } else {
          canvas.drawCircle(Offset.zero, s / 2, paint);
        }
        break;
      default:
        canvas.drawCircle(Offset.zero, s / 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MusicParticlePainter old) {
    return true; 
  }
}
