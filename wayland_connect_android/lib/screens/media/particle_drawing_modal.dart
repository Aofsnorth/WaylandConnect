import 'package:flutter/material.dart';
import 'dart:ui';

class ParticleDrawingModal extends StatefulWidget {
  final Color accent;
  final Function(List<Offset>) onSave;

  const ParticleDrawingModal({super.key, required this.accent, required this.onSave});

  @override
  State<ParticleDrawingModal> createState() => _ParticleDrawingModalState();
}

class _ParticleDrawingModalState extends State<ParticleDrawingModal> {
  List<Offset> _points = [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: widget.accent.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: widget.accent.withOpacity(0.1), blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("DRAW SHAPE", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 20),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.white10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: GestureDetector(
                onPanUpdate: (details) {
                  RenderBox box = context.findRenderObject() as RenderBox;
                  Offset localPos = box.globalToLocal(details.globalPosition);
                  // We need to map global to the 200x200 box local.
                  // Since we are inside a dialog, handling coordinates is tricky.
                  // Better to use a LayoutBuilder or just use the delta.
                  
                  setState(() {
                    _points.add(details.localPosition);
                  });
                },
                onPanStart: (details) {
                  setState(() {
                    _points.clear();
                    _points.add(details.localPosition);
                  });
                },
                child: CustomPaint(
                  painter: _DrawingPainter(_points, widget.accent),
                  size: const Size(200, 200),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text("Draw a continuous line", style: TextStyle(color: Colors.white24, fontSize: 10)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white38)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_points.length < 5) return;
                    // Normalize points to 0.0 - 1.0 range based on 200x200 box
                    List<Offset> normalized = _points.map((p) => Offset(p.dx / 200.0, p.dy / 200.0)).toList();
                    widget.onSave(normalized);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  _DrawingPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    
    // Close the loop visually just for check
    if (points.length > 2) {
      path.lineTo(points[0].dx, points[0].dy);
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) => true;
}
