import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PointerTouchButton extends StatefulWidget {
  final IconData icon;
  final Function(bool) onActiveChanged;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isCircle;
  final double width;
  final double height;

  const PointerTouchButton({
    required this.icon,
    required this.onActiveChanged,
    this.onTap,
    this.onLongPress,
    this.isCircle = false,
    this.width = 70,
    this.height = 70,
  });

  @override
  State<PointerTouchButton> createState() => _PointerTouchButtonState();
}

class _PointerTouchButtonState extends State<PointerTouchButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Listener(
        onPointerDown: (_) {
          setState(() => _isPressed = true);
          widget.onActiveChanged(true);
        },
        onPointerUp: (_) {
          setState(() => _isPressed = false);
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!_isPressed) widget.onActiveChanged(false);
          });
        },
        onPointerCancel: (_) {
          setState(() => _isPressed = false);
          widget.onActiveChanged(false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : BorderRadius.circular(20),
            gradient: _isPressed 
                ? RadialGradient(
                    colors: [Colors.white, Colors.grey.withOpacity(0.5), Colors.transparent],
                    stops: const [0.2, 0.6, 1.0],
                  )
                : const RadialGradient( 
                    colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)], 
                  ),
            color: _isPressed ? null : Colors.black,
            border: Border.all(
              color: _isPressed ? Colors.white : Colors.white10,
              width: _isPressed ? 3.0 : 1.0,
            ),
            boxShadow: _isPressed ? [
              BoxShadow(color: Colors.white.withOpacity(0.6), blurRadius: 30, spreadRadius: 5),
              BoxShadow(color: Colors.white.withOpacity(0.8), blurRadius: 10, spreadRadius: 1)
            ] : [
               BoxShadow(color: Colors.black, blurRadius: 5, spreadRadius: 0)
            ],
          ),
          child: Icon(
            widget.icon, 
            color: _isPressed ? Colors.black : Colors.white24,
            size: 32,
          ),
        ),
      ),
    );
  }
}

class AestheticButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  
  const AestheticButton({required this.icon, required this.onTap});

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
         HapticFeedback.lightImpact();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 60, height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _isPressed ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isPressed ? Colors.white54 : Colors.white12),
          boxShadow: _isPressed ? [BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 15)] : [],
        ),
        child: Icon(widget.icon, color: _isPressed ? Colors.white : Colors.white70, size: 26),
      ),
    );
  }
}

class CustomControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const CustomControlBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10),
            ),
            child: Icon(icon, color: Colors.white70, size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class ParticleIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const ParticleIconButton({
    required this.icon, 
    required this.label, 
    required this.active, 
    required this.onTap,
    this.activeColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: active ? activeColor : Colors.white.withOpacity(0.03),
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? activeColor.withOpacity(0.5) : Colors.white12, 
                width: 1.5
              ),
              boxShadow: active ? [
                BoxShadow(color: activeColor.withOpacity(0.6), blurRadius: 20, spreadRadius: 0),
                BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 40, spreadRadius: 5),
              ] : [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)
              ],
            ),
            child: Icon(
              icon, 
              color: active ? Colors.black : Colors.white30, 
              size: 26
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label, 
            style: TextStyle(
              color: active ? Colors.white : Colors.white24, 
              fontSize: 9, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 2
            )
          ),
        ],
      ),
    );
  }
}
