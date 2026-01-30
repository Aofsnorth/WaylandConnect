import 'dart:math' as math;
import 'package:flutter/material.dart';

class FrameEqualizerData {
  final Map<String, double> spectrum;
  final bool isPlaying;
  final double animationValue;

  FrameEqualizerData({
    required this.spectrum,
    required this.isPlaying,
    required this.animationValue,
  });
}

class FrameEqualizerOverlay extends StatefulWidget {
  final Color color;
  final int mode;
  final bool isRound;
  final ValueNotifier<Map<String, double>?> spectrumNotifier;
  final bool isPlaying;

  const FrameEqualizerOverlay({
    super.key,
    required this.color,
    this.mode = 0,
    required this.spectrumNotifier,
    this.isRound = false,
    this.isPlaying = true,
  });

  @override
  State<FrameEqualizerOverlay> createState() => _FrameEqualizerOverlayState();
}

class FrameEqualizerProvider extends ChangeNotifier {
  final List<double> currBands = List.generate(7, (_) => 0.0);
  final List<double> peaks = List.generate(64, (_) => 0.0);
  final List<double> peakDeath = List.generate(64, (_) => 0.0);
  
  void update(Map<String, double>? spec, bool isPlaying) {
    if (!isPlaying) {
      for (int i = 0; i < 7; i++) currBands[i] *= 0.8;
      for (int i = 0; i < 64; i++) peaks[i] *= 0.8;
    } else {
      for (int i = 0; i < 7; i++) {
          final target = spec?['band_$i'] ?? 0.0;
          // Faster smoothing for lower latency (0.6 instead of 0.75)
          currBands[i] = currBands[i] * 0.6 + target * 0.4;
      }

      for (int i = 0; i < 64; i++) {
          double currentVal = _getInterpolatedForIndex(i, 64);
          if (currentVal > peaks[i]) {
              peaks[i] = currentVal;
              peakDeath[i] = 1.0; 
          } else {
              peakDeath[i] -= 0.04; // Faster decay
              if (peakDeath[i] <= 0) {
                peaks[i] *= 0.90; 
              }
          }
      }
    }
    notifyListeners();
  }

  double _getInterpolatedForIndex(int index, int total) {
    double t = index / math.max(1, total - 1);
    double exactIdx = t * 6; 
    int i1 = exactIdx.floor();
    int i2 = (i1 + 1).clamp(0, 6);
    double f = exactIdx - i1;
    return currBands[i1] * (1.0 - f) + currBands[i2] * f;
  }
}

class _FrameEqualizerOverlayState extends State<FrameEqualizerOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final FrameEqualizerProvider _provider = FrameEqualizerProvider();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..addListener(_onTick)
      ..repeat();
    widget.spectrumNotifier.addListener(_onData);
  }

  void _onData() {
    _provider.update(widget.spectrumNotifier.value, widget.isPlaying);
  }

  void _onTick() {
    if (!mounted || !widget.isPlaying) return;
    // Tick at 60fps for smoothing even if no data comes in
    _provider.update(widget.spectrumNotifier.value, widget.isPlaying);
  }

  @override
  void didUpdateWidget(FrameEqualizerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spectrumNotifier != widget.spectrumNotifier) {
      oldWidget.spectrumNotifier.removeListener(_onData);
      widget.spectrumNotifier.addListener(_onData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ctrl, _provider]),
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _FramePainter(
            color: widget.color,
            bands: _provider.currBands,
            peaks: _provider.peaks,
            mode: widget.mode,
            isRound: widget.isRound,
            animationValue: _ctrl.value,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.spectrumNotifier.removeListener(_onData);
    _ctrl.dispose();
    _provider.dispose();
    super.dispose();
  }
}

class _FramePainter extends CustomPainter {
  final Color color;
  final List<double> bands;
  final List<double> peaks;
  final int mode;
  final bool isRound;
  final double animationValue;

  _FramePainter({
    required this.color,
    required this.bands,
    required this.peaks,
    required this.mode,
    required this.isRound,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 3;

    // Use specific bands for legacy low/mid/high if needed
    double low = bands[0];
    double mid = bands[3];
    double high = bands[6];

    switch (mode) {
      case 0:
        _drawWaveform(canvas, center, radius, low, mid, high, paint, isRound: isRound, size: size);
        break;
      case 1: // CYBER: Radial hexagonal grid or lines
        _drawCyberGrid(canvas, center, radius, bands);
        break;
      case 2: // PLANETARY: Orbiting rings
        _drawOrbitalParticles(canvas, center, radius, bands);
        break;
      case 3: // NORTHERN: Aurora waves
        _drawAurora(canvas, size, bands);
        break;
      case 4: // HIVE: Hexagonal pulsing
        _drawHive(canvas, center, radius, bands);
        break;
      case 5: // BLACK HOLE: Inward sucking particles
        _drawBlackHole(canvas, center, radius, bands);
        break;
      case 6: // NEBULA: Cloud-like pulsing
        _drawNebula(canvas, center, radius, bands);
        break;
      case 7: // HELIX: DNA double helix
        _drawHelix(canvas, size, bands);
        break;
      case 8: // WAVEFORM: Oscilloscope
        _drawOscilloscope(canvas, size, bands);
        break;
      case 9: // DIGITAL RAIN
        _drawDigitalRain(canvas, size, bands);
        break;
      case 10: // SUNBURST: Radial rays
        _drawSunburst(canvas, center, radius, bands);
        break;
      case 11: // SPARKLE: Bass-reactive floating particles
        _drawSparkle(canvas, center, radius, bands);
        break;
      case 12: // SHOCKWAVE: Concentric ripples
        _drawShockwave(canvas, center, radius, bands);
        break;
      case 13: // ZEN: Minimal breathing circle
        _drawZen(canvas, center, radius, bands);
        break;
      case 14: // OFF
        break;
      default:
        _drawGenericSpectrum(canvas, size, center, radius, bands, mode);
        break;
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.fill;
    double bass = bands[0];
    int count = 25;
    for (int i = 0; i < count; i++) {
      double angle = i * 137.5 * math.pi / 180 + animationValue * 2;
      double dist = radius * (1.1 + math.sin(animationValue * 3 + i) * 0.3) + bass * 40;
      Offset pos = center + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      p.color = color.withOpacity((0.2 + bass * 0.8).clamp(0, 1));
      canvas.drawCircle(pos, 1.5 + bass * 4, p);
    }
  }

  void _drawShockwave(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0;
    double bass = bands[0];
    for (int i = 0; i < 3; i++) {
        double t = (animationValue + i * 0.33) % 1.0;
        double r = radius + t * 100 * (1 + bass);
        p.color = color.withOpacity((1.0 - t) * (0.3 + bass * 0.7));
        canvas.drawCircle(center, r, p);
    }
  }

  void _drawZen(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
    double val = bands.reduce(math.max);
    double r = radius + val * 10 + math.sin(animationValue * math.pi * 2) * 5;
    p.color = color.withAlpha(100);
    canvas.drawCircle(center, r, p);
    canvas.drawCircle(center, r + 4, p..color = color.withAlpha(40));
  }

  void _drawCyberGrid(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    int rings = 5;
    for (int i = 0; i < rings; i++) {
      double r = radius * (1 + i * 0.2) + bands[i % 7] * 20;
      canvas.drawCircle(center, r, p);
    }
    int lines = 12;
    for (int i = 0; i < lines; i++) {
        double angle = (i / lines) * 2 * math.pi + animationValue * 0.2;
        double r1 = radius;
        double r2 = radius * 2 + bands[i % 7] * 40;
        canvas.drawLine(
          center + Offset(math.cos(angle) * r1, math.sin(angle) * r1),
          center + Offset(math.cos(angle) * r2, math.sin(angle) * r2),
          p..color = color.withOpacity(0.1 + bands[i % 7] * 0.5)
        );
    }
  }

  void _drawAurora(Canvas canvas, Size size, List<double> bands) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0;
    for (int i = 0; i < 3; i++) {
      double offset = i * 20.0;
      Path path = Path();
      p.color = color.withOpacity(0.1 + bands[i] * 0.4);
      for (double x = 0; x < size.width; x += 5) {
        double y = size.height * 0.5 + 
                   math.sin(x * 0.01 + animationValue * 5 + i) * (20 + bands[i] * 50) + 
                   math.cos(x * 0.02 - animationValue * 3) * 10;
        if (x == 0) path.moveTo(x, y + offset);
        else path.lineTo(x, y + offset);
      }
      canvas.drawPath(path, p);
    }
  }

  void _drawHive(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0;
    int sides = 6;
    for (int i = 0; i < 4; i++) {
      double r = radius * (0.8 + i * 0.3) + bands[i] * 30;
      p.color = color.withOpacity(0.2 + bands[i] * 0.6);
      Path path = Path();
      for (int s = 0; s <= sides; s++) {
        double angle = (s / sides) * 2 * math.pi;
        Offset pos = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (s == 0) path.moveTo(pos.dx, pos.dy);
        else path.lineTo(pos.dx, pos.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  void _drawBlackHole(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.fill;
    int count = 50;
    for (int i = 0; i < count; i++) {
      double t = (i / count + animationValue) % 1.0;
      double angle = i * 0.5 + animationValue * 2;
      double r = radius * 3 * (1.0 - t) + bands[i % 7] * 20;
      if (r < radius * 0.5) continue;
      p.color = color.withOpacity(t * 0.5);
      canvas.drawCircle(center + Offset(math.cos(angle) * r, math.sin(angle) * r), 1 + bands[i % 7] * 3, p);
    }
  }

  void _drawNebula(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.fill..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    for (int i = 0; i < 4; i++) {
      double val = bands[i * 2 % 7];
      p.color = color.withOpacity(0.1 + val * 0.2);
      canvas.drawCircle(center, radius * (1.2 + val), p);
    }
  }

  void _drawHelix(Canvas canvas, Size size, List<double> bands) {
     final p = Paint()..strokeWidth = 2.0;
     double spacing = 20.0;
     int count = (size.width / spacing).floor();
     for (int i = 0; i < count; i++) {
        double t = i / count;
        double bandVal = bands[(i % 7)];
        double angle = t * 4 * math.pi + animationValue * 4;
        double y1 = size.height * 0.5 + math.sin(angle) * (40 + bandVal * 40);
        double y2 = size.height * 0.5 - math.sin(angle) * (40 + bandVal * 40);
        p.color = color.withOpacity(0.3 + bandVal * 0.7);
        canvas.drawCircle(Offset(i * spacing, y1), 2 + bandVal * 3, p);
        canvas.drawCircle(Offset(i * spacing, y2), 2 + bandVal * 3, p);
        canvas.drawLine(Offset(i * spacing, y1), Offset(i * spacing, y2), p..color = color.withOpacity(0.1));
     }
  }

  void _drawOscilloscope(Canvas canvas, Size size, List<double> bands) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.0;
    Path path = Path();
    for (int i = 0; i < size.width; i += 2) {
      double t = i / size.width;
      double bIdx = t * 6;
      int i1 = bIdx.floor();
      int i2 = (i1 + 1).clamp(0, 6);
      double f = bIdx - i1;
      double val = bands[i1] * (1-f) + bands[i2] * f;
      double y = size.height * 0.5 + math.sin(i * 0.1 + animationValue * 20) * (val * size.height * 0.4);
      if (i == 0) path.moveTo(i.toDouble(), y);
      else path.lineTo(i.toDouble(), y);
    }
    canvas.drawPath(path, p);
  }

  void _drawDigitalRain(Canvas canvas, Size size, List<double> bands) {
    final p = Paint()..style = PaintingStyle.fill;
    int cols = 15;
    double colW = size.width / cols;
    for (int i = 0; i < cols; i++) {
      double val = bands[i % 7];
      double speed = 0.5 + val;
      double y = (animationValue * size.height * speed + i * 30) % size.height;
      p.color = color.withOpacity(0.3 + val * 0.7);
      canvas.drawRect(Rect.fromLTWH(i * colW + colW * 0.2, y, colW * 0.6, 10 + val * 30), p);
    }
  }

  void _drawSunburst(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    int rays = 32;
    for (int i = 0; i < rays; i++) {
      double angle = (i / rays) * 2 * math.pi;
      double val = bands[i % 7];
      double len = 20 + val * 80;
      p.color = color.withOpacity(0.2 + val * 0.8);
      canvas.drawLine(
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        center + Offset(math.cos(angle) * (radius + len), math.sin(angle) * (radius + len)),
        p
      );
    }
  }

  void _drawOrbitalParticles(Canvas canvas, Offset center, double radius, List<double> bands) {
    final p = Paint()..style = PaintingStyle.fill;
    int count = 40;
    for (int i = 0; i < count; i++) {
       double t = i / count;
       double bandVal = bands[(i % 7)];
       double angle = t * 2 * math.pi + animationValue * 2 * math.pi * 0.2;
       double r = radius + 20 + bandVal * 40 * math.sin(animationValue * 5 + i);
       Offset pos = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
       p.color = color.withOpacity(0.3 + bandVal * 0.7);
       canvas.drawCircle(pos, 2 + bandVal * 4, p);
    }
  }

  void _drawCrystalField(Canvas canvas, Size size, List<double> bands) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
    double w = size.width;
    double h = size.height;
    for (int i = 0; i < 7; i++) {
        double val = bands[i];
        if (val < 0.1) continue;
        p.color = color.withOpacity(val * 0.3);
        double rectW = w * 0.4 * val;
        double rectH = h * 0.4 * val;
        canvas.drawRect(Rect.fromCenter(center: size.center(Offset.zero), width: rectW, height: rectH), p);
    }
  }

  void _drawGenericSpectrum(Canvas canvas, Size size, Offset center, double radius, List<double> bands, int mode) {
     // A versatile painter that changes behavior based on mode index
     final p = Paint()..strokeWidth = 2.0..strokeCap = StrokeCap.round;
     int bars = 28 + (mode % 5) * 4;
     double stripW = isRound ? (radius * 2 * math.pi) / bars : size.width / bars;
     
     for (int i = 0; i < bars; i++) {
        double t = i / bars;
        int bIdx = (t * 6.9).floor();
        double val = bands[bIdx];
        
        if (isRound) {
           double angle = t * 2 * math.pi - (math.pi / 2);
           double barLen = 10 + val * 60;
           Offset p1 = center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
           Offset p2 = center + Offset(math.cos(angle) * (radius + barLen), math.sin(angle) * (radius + barLen));
           p.color = color.withOpacity(0.4 + val * 0.6);
           canvas.drawLine(p1, p2, p);
        } else {
           double x = i * stripW + stripW/2;
           double barH = 5 + val * size.height * 0.3;
           p.color = color.withOpacity(0.4 + val * 0.6);
           canvas.drawLine(Offset(x, size.height), Offset(x, size.height - barH), p);
        }
     }
  }

  void _drawWaveform(Canvas canvas, Offset center, double radius, double low, double mid, double high, Paint p, {required bool isRound, Size? size}) {
     int layers = 3;
     for (int l = 0; l < layers; l++) {
        Path path = Path();
        int res = 80; 
        double width = isRound ? radius * 2 * math.pi : size!.width;
        double layerOffset = l * 15.0; // Spacing between ripples
        double layerAnim = (animationValue * 2 + l * 0.3) % 1.0;
        
        List<Offset> points = [];
        for(int i=0; i<=res; i++) {
            double t = i/res;
            double envelope = isRound ? 1.0 : math.sin(t * math.pi);
            double noiseVal = (low * 30 + mid * 15) * envelope;
            
            // Frequency modulation based on spectrum
            double noise = math.sin(t * 10 * math.pi + animationValue * 10) * noiseVal 
                         + math.sin(t * 20 * math.pi - animationValue * 15) * (high * 10);
            
            // The "Wave heading out" logic: radius + static offset + animated expansion
            if (isRound) {
                double angle = t * 2 * math.pi - (math.pi/2);
                double r = radius + layerOffset + (layerAnim * 20) + noise;
                points.add(center + Offset(math.cos(angle)*r, math.sin(angle)*r));
            } else {
                double x = t * size!.width;
                // For square frame, waves push towards top/bottom/sides? 
                // Let's stick to vertical displacement for now but push outside the frame
                double yCenter = size.height / 2;
                double direction = yCenter > center.dy ? 1 : -1; 
                double y = yCenter + (direction * (layerOffset + layerAnim * 20 + noise));
                points.add(Offset(x, y));
            }
        }
        
        if (points.isNotEmpty) {
            path.moveTo(points[0].dx, points[0].dy);
            for(int i=0; i<points.length-1; i++) {
                Offset p1 = points[i];
                Offset p2 = points[i+1];
                Offset control = (p1 + p2) / 2;
                path.quadraticBezierTo(p1.dx, p1.dy, control.dx, control.dy);
            }
            if (isRound) path.close();
        }
        
        double opacity = (1.0 - (l / layers)) * (1.0 - layerAnim);
        canvas.drawPath(path, p..color = color.withOpacity(opacity * 0.4)..strokeWidth = 3.0..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)..style = PaintingStyle.stroke);
        canvas.drawPath(path, p..color = Colors.white.withOpacity(opacity * 0.7)..strokeWidth = 1.0..maskFilter = null..style = PaintingStyle.stroke);
     }
  }

  void _drawPerimeterBars(Canvas canvas, Size size, double low, double mid, double high) {
    int barsX = 16; 
    double maxLen = 60.0;
    double baseOffset = 6.0;
    
    final barPaint = Paint()..strokeCap = StrokeCap.round..style = PaintingStyle.stroke..strokeWidth = 4.0;
    
    void processSide(Offset start, Offset dir, int index, int count) {
         double t = index / count;
         double val = (t < 0.5) 
            ? low * (1.0 - t) + mid * t 
            : mid * (1.0 - (t-0.5)) + high * (t-0.5);
            
         val = (val * 1.5).clamp(0.0, 1.0) * maxLen;
         double peakVal = peaks[index % peaks.length] * maxLen; 
         
         Offset pos = start + dir * baseOffset;
         
         if (val > 2) {
             canvas.drawLine(pos, pos + dir * 60, Paint()..color = color.withOpacity(0.1)..strokeWidth = 4.0..strokeCap = StrokeCap.round);
             
             barPaint.color = color.withOpacity(0.8);
             barPaint.shader = LinearGradient(
                 begin: Alignment.center, end: Alignment.bottomCenter,
                 colors: [color, color.withOpacity(0.5)]
             ).createShader(Rect.fromPoints(pos, pos + dir * val));
             
             canvas.drawLine(pos, pos + dir * val, barPaint);
             barPaint.shader = null;
         }
         
         if (peakVal > val + 2) {
             canvas.drawCircle(pos + dir * peakVal, 2.5, Paint()..color = Colors.white.withOpacity(0.8));
         }
    }

    for (int i = 0; i < barsX; i++) {
      double x = (size.width - 40) / (barsX - 1) * i + 20; 
      processSide(Offset(x, 0), const Offset(0, -1), i, barsX); // Top
      processSide(Offset(x, size.height), const Offset(0, 1), i + 20, barsX); // Bottom
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => 
    old.bands != bands || old.animationValue != animationValue;
}

class SideVerticalSpectrumPainter extends CustomPainter {
  final Color color;
  final Map<String, double>? spectrum;
  final bool alignLeft;
  SideVerticalSpectrumPainter(this.color, this.spectrum, {this.alignLeft = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final glowPaint = Paint()..color = color.withOpacity(0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    
    double w = size.width;
    double h = size.height;
    int count = 6;
    double itemH = h / count;
    double low = spectrum?['low'] ?? 0;
    double mid = spectrum?['mid'] ?? 0;
    double high = spectrum?['high'] ?? 0;
    
    for (int i = 0; i < count; i++) {
      double t = i / (count - 1);
      double val = t < 0.5 ? low * (1.0 - t * 2) + mid * (t * 2) : mid * (1.0 - (t - 0.5) * 2) + high * ((t - 0.5) * 2);
      double width = (val * w * 0.8 + 4.0).clamp(4.0, w);
      double x = alignLeft ? 0 : w - width;
      final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(x, i * itemH + 2, width, itemH - 4), Radius.circular(itemH / 2));
      if (val > 0.05) canvas.drawRRect(rrect, glowPaint);
      canvas.drawRRect(rrect, paint);
    }
  }
  @override
  bool shouldRepaint(covariant SideVerticalSpectrumPainter old) => true;
}

class HorizontalSpectrumPainter extends CustomPainter {
  final Color color;
  final Map<String, double>? spectrum;
  HorizontalSpectrumPainter(this.color, this.spectrum);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final glowPaint = Paint()..color = color.withOpacity(0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    double w = size.width;
    double h = size.height;
    int count = 18; 
    double itemW = w / count;
    
    for (int i = 0; i < count; i++) {
        double t = i / (count - 1);
        double val = t < 0.5 
            ? (spectrum?['low'] ?? 0) * (1.0 - t * 2) + (spectrum?['mid'] ?? 0) * (t * 2)
            : (spectrum?['mid'] ?? 0) * (1.0 - (t - 0.5) * 2) + (spectrum?['high'] ?? 0) * ((t - 0.5) * 2);

        double barH = (val * h * 0.9).clamp(4.0, h);
        final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(i * itemW + 2, h - barH, itemW - 4, barH), Radius.circular(itemW / 2));
        
        if (val > 0.1) {
           canvas.drawRRect(rrect, glowPaint..color = color.withOpacity(val * 0.4));
        }
        canvas.drawRRect(rrect, paint);
    }
  }
  @override
  bool shouldRepaint(covariant HorizontalSpectrumPainter old) => true;
}
