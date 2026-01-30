import 'package:flutter/material.dart';

class AestheticButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  
  const AestheticButton({super.key, required this.icon, required this.onTap});

  @override
  State<AestheticButton> createState() => _AestheticButtonState();
}

class _AestheticButtonState extends State<AestheticButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
         setState(() => _isPressed = false);
         widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: _isPressed ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _isPressed ? Colors.white54 : Colors.white12),
          boxShadow: _isPressed ? [BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 10)] : [],
        ),
        child: Icon(widget.icon, color: Colors.white, size: 24),
      ),
    );
  }
}
