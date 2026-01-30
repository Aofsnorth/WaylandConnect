import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';
import '../utils/protocol.dart';
import 'package:wayland_connect_android/l10n/app_localizations.dart';

class KeyboardScreen extends StatefulWidget {
  final Socket? socket;
  const KeyboardScreen({super.key, required this.socket});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  void _sendKey(String key) {
    if (widget.socket != null) {
      final event = {
        "type": "keypress",
        "data": {"key": key}
      };
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Colors.white;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
          opacity: 0.1,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              // --- HEADER (Consistent with Touchpad) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("REMOTE", style: TextStyle(color: accentColor.withOpacity(0.5), fontWeight: FontWeight.bold, letterSpacing: 4, fontSize: 10)),
                        const Text("KEYBOARD", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -1)),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
  
              // --- ELEGANT INPUT FIELD ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutExpo,
                  padding: const EdgeInsets.all(2), // Outer glow border
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: _isFocused 
                      ? LinearGradient(colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.05)])
                      : LinearGradient(colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)]),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextField(
                       controller: _textController,
                       focusNode: _focusNode,
                       decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.inputHint,
                          hintStyle: TextStyle(color: Colors.white24, letterSpacing: 3, fontSize: 9, fontWeight: FontWeight.bold),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Icon(Icons.webhook_rounded, color: _isFocused ? Colors.white : Colors.white24, size: 20),
                          ),
                       ),
                       textAlign: TextAlign.start,
                       style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                       onChanged: (val) {
                          if (val.isNotEmpty) {
                            _sendKey(val.characters.last);
                            _textController.clear();
                          }
                       },
                    ),
                  ),
                ),
              ),
  
              const SizedBox(height: 20),
  
              // --- PREMIUM SPECIAL KEYS GRID ---
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 0, 25, 95),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _SpecialKey(label: AppLocalizations.of(context)!.esc, icon: Icons.terminal_rounded, onTap: () => _sendKey("Escape"), flex: 1),
                        const SizedBox(width: 12),
                        _SpecialKey(label: AppLocalizations.of(context)!.tab, icon: Icons.keyboard_tab_rounded, onTap: () => _sendKey("Tab"), flex: 1),
                        const SizedBox(width: 12),
                        _SpecialKey(label: AppLocalizations.of(context)!.enter, icon: Icons.keyboard_return_rounded, onTap: () => _sendKey("Enter"), flex: 2, isPrimary: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SpecialKey(label: AppLocalizations.of(context)!.ctrl, icon: Icons.control_point_duplicate_rounded, onTap: () => _sendKey("Control_L"), flex: 1),
                        const SizedBox(width: 12),
                        _SpecialKey(label: AppLocalizations.of(context)!.alt, icon: Icons.alt_route_rounded, onTap: () => _sendKey("Alt_L"), flex: 1),
                        const SizedBox(width: 12),
                        _SpecialKey(label: AppLocalizations.of(context)!.delete, icon: Icons.backspace_outlined, onTap: () => _sendKey("Backspace"), flex: 2),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SpecialKey(label: AppLocalizations.of(context)!.superKey, icon: Icons.window_rounded, onTap: () => _sendKey("Super_L"), flex: 1),
                        const SizedBox(width: 12),
                        _SpecialKey(label: AppLocalizations.of(context)!.spacebar, icon: Icons.space_bar_rounded, onTap: () => _sendKey("space"), flex: 3),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecialKey extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int flex;
  final bool isPrimary;
  const _SpecialKey({required this.label, required this.icon, required this.onTap, required this.flex, this.isPrimary = false});
  @override
  State<_SpecialKey> createState() => _SpecialKeyState();
}

class _SpecialKeyState extends State<_SpecialKey> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: widget.flex,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _isPressed 
              ? Colors.white.withOpacity(0.2) 
              : (widget.isPrimary ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.04)), 
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(
              color: _isPressed ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.08), 
              width: 1.2
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: _isPressed ? Colors.white : Colors.white30, size: 18), 
              const SizedBox(height: 8), 
              Text(
                widget.label, 
                style: TextStyle(
                  color: _isPressed ? Colors.white : Colors.white24, 
                  fontSize: 8, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 2
                )
              )
            ]
          ),
        ),
      ),
    );
  }
}
