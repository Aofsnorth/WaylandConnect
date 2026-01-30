import 'dart:math' as math;
import 'package:flutter/material.dart';

class QuantumProgressBar extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Color color;
  final Map<String, double>? spectrum;
  final bool isVertical;

  const QuantumProgressBar({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.color,
    this.spectrum,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: isVertical ? null : (d) {
        final box = context.findRenderObject() as RenderBox;
        onChanged((d.localPosition.dx / box.size.width).clamp(0.0, 1.0));
      },
      onVerticalDragUpdate: !isVertical ? null : (d) {
        final box = context.findRenderObject() as RenderBox;
        onChanged(1.0 - (d.localPosition.dy / box.size.height).clamp(0.0, 1.0));
      },
      onHorizontalDragEnd: isVertical ? null : (d) => onChangeEnd(value),
      onVerticalDragEnd: !isVertical ? null : (d) => onChangeEnd(value),
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox;
        double v;
        if (isVertical) {
          v = 1.0 - (d.localPosition.dy / box.size.height).clamp(0.0, 1.0);
        } else {
          v = (d.localPosition.dx / box.size.width).clamp(0.0, 1.0);
        }
        onChangeEnd(v);
      },
      child: Container(
        height: isVertical ? double.infinity : 20,
        width: isVertical ? 20 : double.infinity,
        child: CustomPaint(
          painter: _QuantumPainter(value, color, spectrum, isVertical),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _QuantumPainter extends CustomPainter {
  final double value;
  final Color color;
  final Map<String, double>? spectrum;
  final bool isVertical;
  _QuantumPainter(this.value, this.color, this.spectrum, this.isVertical);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final w = size.width;
    final hTotal = size.height;
    int segments = isVertical ? 30 : 40;
    double gap = 2;
    double segLen = (isVertical ? (hTotal - (segments - 1) * gap) : (w - (segments - 1) * gap)) / segments;

    for (int i = 0; i < segments; i++) {
      double pos = i * (segLen + gap);
      bool active = isVertical ? ((segments - 1 - i) / segments) < value : (i / segments) < value;
      paint.color = active ? color.withOpacity(0.8) : Colors.white.withOpacity(0.05);
      double low = spectrum?['low'] ?? 0.0;
      double thickness = active ? 4 + (4 + low * 16) * math.sin(i * 0.5 + value * 10) : 3;
      Rect rect;
      if (isVertical) {
        double x = (w - thickness) / 2;
        rect = Rect.fromLTWH(x, pos, thickness, segLen);
      } else {
        double y = (hTotal - thickness) / 2;
        rect = Rect.fromLTWH(pos, y, segLen, thickness);
      }
      if (active) {
        final glowP = Paint()
          ..color = color.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)), glowP);
      }
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _QuantumPainter old) => true;
}

class ParticleVolumeBar extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Color color;
  final bool isVertical;

  const ParticleVolumeBar({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.color,
    this.isVertical = false,
  });

  @override
  State<ParticleVolumeBar> createState() => _ParticleVolumeBarState();
}

class _ParticleVolumeBarState extends State<ParticleVolumeBar> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_VolParticle> _particles = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 16))..repeat();
    _ctrl.addListener(_tick);
  }

  void _tick() {
    if (!mounted) return;
    if (_particles.isEmpty) return;
    setState(() {
      for (var p in _particles) {
        p.life -= 0.03;
        p.x += p.vx;
        p.y += p.vy;
      }
      _particles.removeWhere((p) => p.life <= 0);
    });
  }

  void _spawn(double x, double width) {
    if (_particles.length > 40) return;
    for (int i = 0; i < 3; i++) {
      _particles.add(_VolParticle(
        x: x,
        y: 0,
        vx: (_rng.nextDouble() - 0.5) * 2,
        vy: (_rng.nextDouble() - 0.5) * 2,
        life: 1.0 + _rng.nextDouble() * 0.5,
        color: widget.color.withOpacity(0.5 + _rng.nextDouble() * 0.5),
        size: 2 + _rng.nextDouble() * 3,
      ));
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        final size = box.size;
        double v;
        if (widget.isVertical) {
          v = 1.0 - (d.localPosition.dy / size.height).clamp(0.0, 1.0);
        } else {
          v = (d.localPosition.dx / size.width).clamp(0.0, 1.0);
        }
        widget.onChanged(v);
        if (widget.isVertical) _spawn(v * size.height, size.height);
        else _spawn(v * size.width, size.width);
      },
      onPanEnd: (d) => widget.onChangeEnd(widget.value),
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox;
        final size = box.size;
        double v;
        if (widget.isVertical) {
          v = 1.0 - (d.localPosition.dy / size.height).clamp(0.0, 1.0);
        } else {
          v = (d.localPosition.dx / size.width).clamp(0.0, 1.0);
        }
        widget.onChanged(v);
        if (widget.isVertical) _spawn(v * size.height, size.height);
        else _spawn(v * size.width, size.width);
        widget.onChangeEnd(v);
      },
      child: Container(
        height: widget.isVertical ? double.infinity : 30,
        width: widget.isVertical ? 30 : double.infinity,
        child: CustomPaint(
          painter: _VolPainter(widget.value, widget.color, _particles, widget.isVertical),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _VolParticle {
  double x, y, vx, vy, life, size;
  Color color;
  _VolParticle({required this.x, required this.y, required this.vx, required this.vy, required this.life, required this.color, required this.size});
}

class _VolPainter extends CustomPainter {
  final double value;
  final Color color;
  final List<_VolParticle> particles;
  final bool isVertical;

  _VolPainter(this.value, this.color, this.particles, [this.isVertical = false]);

  @override
  void paint(Canvas canvas, Size size) {
    if (isVertical) {
      final cx = size.width / 2;
      final trackRect = Rect.fromLTWH(cx - 1.5, 0, 3, size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(trackRect, const Radius.circular(1.5)), Paint()..color = Colors.white.withOpacity(0.1));
      final activeH = size.height * value;
      final activeRect = Rect.fromLTWH(cx - 1.5, size.height - activeH, 3, activeH);
      final activePaint = Paint()..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [color.withOpacity(0.3), color, Colors.white]).createShader(activeRect);
      canvas.drawRRect(RRect.fromRectAndRadius(activeRect, const Radius.circular(1.5)), activePaint);
      canvas.drawRRect(RRect.fromRectAndRadius(activeRect, const Radius.circular(1.5)), Paint()..color = color.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      for (var p in particles) {
        final pp = Paint()..color = p.color.withOpacity((p.life).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(cx + p.y, size.height - p.x), p.size * p.life, pp);
      }
      canvas.drawCircle(Offset(cx, size.height - activeH), 4, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(cx, size.height - activeH), 8, Paint()..color = color.withOpacity(0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    } else {
      final cy = size.height / 2;
      final trackRect = Rect.fromLTWH(0, cy - 1.5, size.width, 3);
      canvas.drawRRect(RRect.fromRectAndRadius(trackRect, const Radius.circular(1.5)), Paint()..color = Colors.white.withOpacity(0.1));
      final activeW = size.width * value;
      final activeRect = Rect.fromLTWH(0, cy - 1.5, activeW, 3);
      final activePaint = Paint()..shader = LinearGradient(colors: [color.withOpacity(0.3), color, Colors.white]).createShader(activeRect);
      canvas.drawRRect(RRect.fromRectAndRadius(activeRect, const Radius.circular(1.5)), activePaint);
      canvas.drawRRect(RRect.fromRectAndRadius(activeRect, const Radius.circular(1.5)), Paint()..color = color.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      for (var p in particles) {
        final pp = Paint()..color = p.color.withOpacity((p.life).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(p.x, cy + p.y), p.size * p.life, pp);
      }
      canvas.drawCircle(Offset(activeW, cy), 5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(activeW, cy), 10, Paint()..color = color.withOpacity(0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
  }

  @override
  bool shouldRepaint(covariant _VolPainter old) => true;
}

class ScrollableText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final EdgeInsetsGeometry padding;

  const ScrollableText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.padding = const EdgeInsets.symmetric(horizontal: 0),
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.15, 0.85, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: padding,
        child: Text(
          text,
          textAlign: textAlign,
          style: style,
          maxLines: 1,
        ),
      ),
    );
  }
}
