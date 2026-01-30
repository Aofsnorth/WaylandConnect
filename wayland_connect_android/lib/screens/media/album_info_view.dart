import 'dart:math' as math;
import 'package:flutter/material.dart';

class VinylInfoCard extends StatelessWidget {
  final Color accent;
  final Map<String, dynamic>? metadata;
  final bool isPlaying;

  const VinylInfoCard({
    super.key,
    required this.accent,
    required this.metadata,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.15, 0.85, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isPlaying ? accent : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isPlaying ? "LIVE" : "PAUSED",
                  style: TextStyle(
                    color: isPlaying ? Colors.black : Colors.white54,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              MarqueeText(
                text: (metadata?['title'] ?? "NO SIGNAL").toString().toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
                isPlaying: isPlaying,
                padding: EdgeInsets.zero,
                useFadeMask: false, // Turn off internal mask
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 3, height: 3, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: MarqueeText(
                      text: (metadata?['artist'] ?? "IDLE").toString().toUpperCase(),
                      style: TextStyle(
                        color: accent.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.5,
                      ),
                      isPlaying: isPlaying,
                      padding: EdgeInsets.zero,
                      useFadeMask: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool isPlaying;
  final EdgeInsetsGeometry padding;
  final bool useFadeMask;
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.isPlaying = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.useFadeMask = true,
  });
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trigger());
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _isAnimating = false;
      Future.delayed(const Duration(milliseconds: 100), () => _trigger());
    }
    if (widget.isPlaying && !old.isPlaying) _trigger();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _trigger() async {
    if (_isAnimating || !widget.isPlaying || !mounted) return;
    _isAnimating = true;

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !widget.isPlaying || !_scrollController.hasClients) {
      _isAnimating = false;
      return;
    }

    final max = _scrollController.position.maxScrollExtent;
    if (max > 0) {
      await _scrollController.animateTo(max, duration: Duration(seconds: (max / 30).round() + 2), curve: Curves.linear);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !widget.isPlaying) {
        _isAnimating = false;
        return;
      }
      await _scrollController.animateTo(0.0, duration: Duration(seconds: (max / 30).round() + 2), curve: Curves.linear);
      await Future.delayed(const Duration(seconds: 2));
    }
    _isAnimating = false;
    if (widget.isPlaying && mounted) _trigger();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: widget.padding,
      child: Text(widget.text, style: widget.style),
    );

    if (!widget.useFadeMask) return content;

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
      child: content,
    );
  }
}

class GlitchyAbstractText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool isPlaying;
  final Color accent;

  const GlitchyAbstractText({
    super.key,
    required this.text,
    required this.style,
    required this.isPlaying,
    required this.accent,
  });

  @override
  State<GlitchyAbstractText> createState() => _GlitchyAbstractTextState();
}

class _GlitchyAbstractTextState extends State<GlitchyAbstractText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final math.Random _random = math.Random();
  final String _glitchChars = r"X%&#?!@*01<>/[]{}";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 80))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!widget.isPlaying) {
          return Text(widget.text, style: widget.style, textAlign: TextAlign.center);
        }
        final chars = widget.text.split('');
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: chars.map((char) {
            if (char == ' ') return Text(' ', style: widget.style);
            bool glitch = _random.nextDouble() < 0.15;
            String displayChar = glitch ? _glitchChars[_random.nextInt(_glitchChars.length)] : char;
            double dy = glitch ? (_random.nextDouble() - 0.5) * 8 : (_random.nextDouble() - 0.5) * 2;
            return Transform.translate(
              offset: Offset(0, dy),
              child: Text(
                displayChar,
                style: widget.style.copyWith(
                  color: glitch ? widget.accent.withOpacity(0.8) : widget.style.color,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
