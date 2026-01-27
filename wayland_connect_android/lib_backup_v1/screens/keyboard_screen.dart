import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';

class KeyboardScreen extends StatefulWidget {
  final Socket? socket;
  const KeyboardScreen({super.key, required this.socket});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  final TextEditingController _textController = TextEditingController();

  void _sendKey(String key) {
    if (widget.socket != null) {
      final event = {"type": "keypress", "data": {"key": key}};
      widget.socket!.write("${jsonEncode(event)}\n");
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.keyboard_alt_outlined, size: 64, color: Colors.white10),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: TextField(
             controller: _textController,
             autofocus: false, // Don't pop keyboard automatically
             decoration: InputDecoration(
                hintText: "TAP TO TYPE...",
                hintStyle: const TextStyle(color: Colors.white10, letterSpacing: 2, fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white.withOpacity(0.02),
             ),
             textAlign: TextAlign.center,
             style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w300),
             onChanged: (val) {
                if (val.isNotEmpty) {
                  _sendKey(val.characters.last);
                  _textController.clear();
                }
             },
          ),
        ),
        const SizedBox(height: 60),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             _SpecialKey(label: "ESC", icon: Icons.close, onTap: () => _sendKey("Escape")),
             const SizedBox(width: 16),
             _SpecialKey(label: "ENTER", icon: Icons.keyboard_return, onTap: () => _sendKey("Enter")),
             const SizedBox(width: 16),
             _SpecialKey(label: "BKSP", icon: Icons.backspace_outlined, onTap: () => _sendKey("Backspace")),
          ],
        )
      ],
    );
  }
}

class _SpecialKey extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SpecialKey({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 80, padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04), 
            borderRadius: BorderRadius.circular(12), 
            border: Border.all(color: Colors.white10)
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white70, size: 20), 
              const SizedBox(height: 8), 
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold))
            ]
          ),
        ),
      ),
    );
  }
}
