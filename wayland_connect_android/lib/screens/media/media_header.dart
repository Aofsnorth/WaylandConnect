import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SmartFrameToggle extends StatelessWidget {
  final int current;
  final Color accent;
  final bool isPlaying;
  final ValueChanged<int> onChanged;
  const SmartFrameToggle({
    super.key,
    required this.current,
    required this.accent,
    required this.onChanged,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        onChanged((current + 1) % 3);
        HapticFeedback.mediumImpact();
      },
      child: AnimatedContainer(
        duration: isPlaying ? const Duration(milliseconds: 100) : const Duration(milliseconds: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isPlaying ? accent.withOpacity(0.9) : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isPlaying ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 10, spreadRadius: -2)] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedRotation(
              duration: isPlaying ? const Duration(milliseconds: 100) : const Duration(milliseconds: 10),
              turns: current * 0.33,
              child: Icon(
                current == 0 ? Icons.crop_square_rounded :
                current == 1 ? Icons.crop_landscape_rounded : Icons.circle_outlined,
                size: 16,
                color: isPlaying ? Colors.black87 : Colors.white24,
              ),
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("DISPLAY MODE", style: TextStyle(color: isPlaying ? Colors.black54 : Colors.white24, fontSize: 5, fontWeight: FontWeight.bold)),
                Text(
                  current == 0 ? "SQUARE" : current == 1 ? "WIDE" : "VINYL",
                  style: TextStyle(color: isPlaying ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TechCard extends StatelessWidget {
  final Color color;
  final String label;
  final bool alignRight;
  const TechCard({super.key, required this.color, required this.label, this.alignRight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignRight) ...[
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 6, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Container(width: 4, height: 4, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ] else ...[
            Container(width: 4, height: 4, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 6, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }
}
