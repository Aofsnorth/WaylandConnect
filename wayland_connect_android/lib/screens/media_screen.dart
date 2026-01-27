import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;

class MediaScreen extends StatefulWidget {
  final Socket? socket;
  final Stream<Uint8List>? socketStream;

  const MediaScreen({super.key, required this.socket, this.socketStream});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _metadata;
  PaletteGenerator? _palette;
  Timer? _statusTimer;
  Timer? _progressTimer;
  bool _isLoading = true;
  bool _isSearching = true;
  double _currentPosition = 0;
  double _totalDuration = 0;
  bool _isPlaying = false;
  
  bool _shuffle = false;
  String _repeat = "None";
  double _volume = 1.0;
  String _playerDisplayName = "PLAYER";
  String _rawPlayerName = "";

  late AnimationController _playPauseController;
  late AnimationController _floatController;
  late AnimationController _particleController;
  StreamSubscription? _socketSubscription;

  double _tiltX = 0;
  double _tiltY = 0;
  bool _isDraggingSlider = false;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();

    _setupConnection();
  }

  @override
  void didUpdateWidget(MediaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.socketStream != oldWidget.socketStream || widget.socket != oldWidget.socket) {
      _setupConnection();
    }
  }

  void _setupConnection() {
    _socketSubscription?.cancel();
    _statusTimer?.cancel();
    _progressTimer?.cancel();

    _fetchStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchStatus();
      if (timer.tick > 5) {
        timer.cancel();
        _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStatus());
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPlaying && _totalDuration > 0 && !_isDraggingSlider) {
        setState(() {
          _currentPosition += 1;
          if (_currentPosition > _totalDuration) _currentPosition = _totalDuration;
        });
      }
    });

    if (widget.socketStream != null) {
      _socketSubscription = widget.socketStream!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!mounted) return;
          try {
            final json = jsonDecode(line);
            if (json.containsKey('metadata')) {
               setState(() {
                _isSearching = false;
                final oldTitle = _metadata?['title'];
                _metadata = json['metadata'];
                _isLoading = false;
                if (_metadata != null) {
                  _isPlaying = _metadata!['status'] == "Playing";
                  _totalDuration = (_metadata!['duration'] as num).toDouble() / 1000000;
                  
                  double newPos = (_metadata!['position'] as num).toDouble() / 1000000;
                  if (!_isDraggingSlider) {
                    if (oldTitle != _metadata!['title'] || (newPos - _currentPosition).abs() > 3 || !_isPlaying) {
                      _currentPosition = newPos;
                    }
                  }

                  _shuffle = _metadata!['shuffle'] ?? false;
                  _repeat = _metadata!['repeat'] ?? "None";
                  _volume = (_metadata!['volume'] as num?)?.toDouble() ?? 1.0;
                  
                  _rawPlayerName = (_metadata!['player_name'] ?? "Player").toString().toLowerCase();
                  _playerDisplayName = _rawPlayerName.split('.').first.toUpperCase();

                  if (_isPlaying) _playPauseController.forward();
                  else _playPauseController.reverse();
                  
                  if (oldTitle != _metadata!['title']) _updatePalette();
                }
              });
            }
          } catch (_) {}
        });
    }
  }

  Future<void> _updatePalette() async {
    final artUrl = _metadata?['art_url'];
    if (artUrl != null && artUrl.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(artUrl));
        if (mounted) setState(() => _palette = palette);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _statusTimer?.cancel();
    _progressTimer?.cancel();
    _playPauseController.dispose();
    _floatController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  void _fetchStatus() {
    if (widget.socket != null) {
      final event = {"type": "media_get_status"};
      try { widget.socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
    }
  }

  void _sendCommand(String action) {
    if (widget.socket != null) {
      final event = {"type": "media_control", "data": {"action": action}};
      try {
        widget.socket!.write("${jsonEncode(event)}\n");
        HapticFeedback.lightImpact();
        
        setState(() {
          if (action == "play_pause") {
            _isPlaying = !_isPlaying;
            if (_isPlaying) _playPauseController.forward(); else _playPauseController.reverse();
          } else if (action == "toggle_shuffle") {
            _shuffle = !_shuffle;
          } else if (action == "toggle_loop") {
            if (_repeat == "None") _repeat = "Track";
            else if (_repeat == "Track") _repeat = "Playlist";
            else _repeat = "None";
          }
        });
      } catch (_) {}
    }
  }

  void _seek(double seconds) {
    if (widget.socket != null) {
      final usecs = (seconds * 1000000).toInt();
      final event = {"type": "media_control", "data": {"action": "seek:$usecs"}};
      try { widget.socket!.write("${jsonEncode(event)}\n"); } catch (_) {}
    }
  }

  void _setVolume(double value) {
     if (widget.socket != null) {
      final event = {"type": "media_control", "data": {"action": "volume:$value"}};
      try {
        widget.socket!.write("${jsonEncode(event)}\n");
        setState(() => _volume = value);
      } catch (_) {}
    }
  }

  String _formatTime(double seconds) {
    if (seconds < 0) seconds = 0;
    final int min = seconds ~/ 60;
    final int sec = (seconds % 60).toInt();
    return "$min:${sec.toString().padLeft(2, '0')}";
  }

  IconData _getPlayerIcon() {
    if (_rawPlayerName.contains("spotify")) return Icons.music_note_rounded;
    if (_rawPlayerName.contains("chrome") || _rawPlayerName.contains("firefox") || _rawPlayerName.contains("browser")) return Icons.language_rounded;
    if (_rawPlayerName.contains("vlc")) return Icons.movie_filter_rounded;
    if (_rawPlayerName.contains("strawberry") || _rawPlayerName.contains("lollypop") || _rawPlayerName.contains("rhythmbox")) return Icons.library_music_rounded;
    return Icons.settings_input_component_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _palette?.vibrantColor?.color ?? Colors.blueAccent;
    final dominantColor = _palette?.dominantColor?.color ?? Colors.black;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildPlasmaBackground(dominantColor, accentColor),
          
          if (_isLoading) 
             _buildSpinner()
          else if (_isSearching)
             _buildSearchingState()
          else if (_metadata == null) 
             _buildEmptyState()
          else
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Column(
                  children: [
                    _buildHeader(accentColor),
                    const SizedBox(height: 24),
                    _buildInteractiveStage(accentColor),
                    const SizedBox(height: 32),
                    _buildInfoCluster(),
                    const SizedBox(height: 28),
                    _buildSeekingModule(accentColor),
                    const SizedBox(height: 28),
                    _buildDock(accentColor),
                    const SizedBox(height: 28),
                    _buildVolumeSuite(),
                    const SizedBox(height: 40), 
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpinner() {
    return const Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Colors.white24, strokeWidth: 1),
        const SizedBox(height: 16),
        const Text("SYNCHRONIZING PATHS", style: TextStyle(color: Colors.white12, letterSpacing: 3, fontSize: 10)),
      ],
    ));
  }

  Widget _buildSearchingState() {
     return const Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.radar_rounded, color: Colors.white10, size: 64),
        const SizedBox(height: 24),
        const Text("LOCATING MEDIA SIGNAL...", style: TextStyle(color: Colors.white24, letterSpacing: 3, fontWeight: FontWeight.bold, fontSize: 11)),
      ],
    ));
  }

  Widget _buildEmptyState() {
    return Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.waves_rounded, color: Colors.white.withOpacity(0.05), size: 100),
        const SizedBox(height: 24),
        const Text("NO ACTIVE SESSIONS", style: TextStyle(color: Colors.white24, letterSpacing: 4, fontWeight: FontWeight.w900, fontSize: 12)),
        const SizedBox(height: 12),
        const Text("PLEASE START A MEDIA PLAYER ON YOUR PC", style: TextStyle(color: Colors.white10, letterSpacing: 1, fontSize: 10)),
      ],
    ));
  }

  Widget _buildPlasmaBackground(Color dom, Color acc) {
    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, _) => CustomPaint(
        painter: _CyberPainter(dom.withOpacity(0.3), acc.withOpacity(0.15), _particleController.value, _isPlaying),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildHeader(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: accent.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(_getPlayerIcon(), color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Text(_playerDisplayName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ],
        ),
        _ZenEqualizer(color: accent, isPlaying: _isPlaying),
      ],
    );
  }

  Widget _buildInteractiveStage(Color accent) {
    return GestureDetector(
      onPanUpdate: (d) => setState(() {
        _tiltY += d.delta.dx / 100; _tiltX -= d.delta.dy / 100;
        _tiltX = _tiltX.clamp(-0.4, 0.4); _tiltY = _tiltY.clamp(-0.4, 0.4);
      }),
      onPanEnd: (_) => setState(() => { _tiltX = 0, _tiltY = 0 }),
      child: AnimatedBuilder(
        animation: _floatController,
        builder: (context, child) {
          double float = 12 * math.sin(_floatController.value * 2 * math.pi);
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(_tiltX)
              ..rotateY(_tiltY)
              ..translate(0.0, float),
            alignment: Alignment.center,
            child: child,
          );
        },
        child: _buildGlassAlbum(accent),
      ),
    );
  }

  Widget _buildGlassAlbum(Color accent) {
    return Container(
      width: 260, height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.3), blurRadius: 100, spreadRadius: -20),
          BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 30),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _metadata?['art_url']?.isNotEmpty == true
                ? CachedNetworkImage(imageUrl: _metadata!['art_url'], fit: BoxFit.cover)
                : Container(color: Colors.white.withOpacity(0.05)),
            Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.15), Colors.transparent, Colors.black.withOpacity(0.2)],
              )
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCluster() {
    return Column(
      children: [
        Text(
          _metadata?['title'] ?? "NO SIGNAL",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
          child: Text(
            (_metadata?['artist'] ?? "SOURCE UNKNOWN").toUpperCase(),
            style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekingModule(Color accent) {
    double progress = (_currentPosition / (_totalDuration > 0 ? _totalDuration : 1)).clamp(0.0, 1.0);
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 5),
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            overlayColor: accent.withOpacity(0.1),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Container(
            height: 20,
            child: Stack(
              alignment: Alignment.centerLeft, // Key: Align left to match Slider behavior
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6), // Compensate for Slider thumb radius
                    height: 4, width: double.infinity,
                    color: Colors.white.withOpacity(0.05),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [accent, Colors.white]),
                          boxShadow: [BoxShadow(color: accent.withOpacity(0.5), blurRadius: 10)],
                        ),
                      ),
                    ),
                  ),
                ),
                Slider(
                  value: progress,
                  onChanged: (v) {
                    setState(() {
                      _isDraggingSlider = true;
                      _currentPosition = v * _totalDuration;
                    });
                  },
                  onChangeEnd: (v) {
                    setState(() => _isDraggingSlider = false);
                    _seek(v * _totalDuration);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatTime(_currentPosition), style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
            Text(_formatTime(_totalDuration), style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
          ],
        ),
      ],
    );
  }

  Widget _buildDock(Color accent) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: Icon(Icons.shuffle_rounded, size: 20, color: _shuffle ? accent : Colors.white24), onPressed: () => _sendCommand("toggle_shuffle")),
              IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 32, color: Colors.white), onPressed: () => _sendCommand("previous")),
              GestureDetector(
                onTap: () => _sendCommand("play_pause"),
                child: Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 40)]),
                  child: Center(child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _playPauseController, color: Colors.black, size: 36)),
                ),
              ),
              IconButton(icon: const Icon(Icons.skip_next_rounded, size: 32, color: Colors.white), onPressed: () => _sendCommand("next")),
              IconButton(
                icon: Icon(
                  _repeat == "Track" ? Icons.repeat_one_rounded : Icons.repeat_rounded, 
                  size: 22, 
                  color: _repeat != "None" ? accent : Colors.white24
                ), 
                onPressed: () => _sendCommand("toggle_loop")
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeSuite() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          const Icon(Icons.volume_off_rounded, color: Colors.white12, size: 16),
          Expanded(child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 1, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), activeTrackColor: Colors.white30),
            child: Slider(value: _volume, onChanged: _setVolume),
          )),
          const Icon(Icons.volume_up_rounded, color: Colors.white12, size: 16),
        ],
      ),
    );
  }
}

class _ZenEqualizer extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  const _ZenEqualizer({required this.color, required this.isPlaying});
  @override
  State<_ZenEqualizer> createState() => _ZenEqualizerState();
}

class _ZenEqualizerState extends State<_ZenEqualizer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<double> _h = List.filled(15, 3.0);
  final List<double> _t = List.filled(15, 3.0);
  final math.Random _r = math.Random();

  @override
  void initState() {
    super.initState();
    // Slow Wave Logic: High amplitude, slow frequency
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..addListener(() {
      if (!widget.isPlaying) return;
      setState(() {
        for (int i = 0; i < 15; i++) {
          if ((_h[i] - _t[i]).abs() < 2) {
            // Restore height range (4 to 30+)
            _t[i] = 4 + _r.nextDouble() * 28 * (i % 2 == 0 ? 1 : 0.6);
          }
          // Fluid interpolation for "wave" effect
          _h[i] = lerpDouble(_h[i], _t[i], 0.12)!;
        }
      });
    });
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_ZenEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying) _ctrl.repeat(); else _ctrl.stop();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(15, (i) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.2),
        width: 2.2, height: widget.isPlaying ? _h[i] : 3,
        decoration: BoxDecoration(
          color: widget.isPlaying ? widget.color.withOpacity(0.3 + (i / 15 * 0.4)) : Colors.white12,
          borderRadius: BorderRadius.circular(5),
        ),
      )),
    );
  }
}

class _CyberPainter extends CustomPainter {
  final Color c1, c2;
  final double v;
  final bool active;
  _CyberPainter(this.c1, this.c2, this.v, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Layer 1: Deep Plasma
    final g1 = RadialGradient(
      center: Alignment(math.sin(v * 2 * math.pi) * 0.3, math.cos(v * 2 * math.pi) * 0.4),
      radius: 1.8,
      colors: [c2.withOpacity(0.4), c1.withOpacity(0.2), Colors.transparent],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = g1);

    // Layer 2: Secondary accent wash
    final g2 = RadialGradient(
      center: Alignment(math.cos(v * math.pi) * 0.8, -math.sin(v * math.pi) * 0.5),
      radius: 1.2,
      colors: [c2.withOpacity(0.25), Colors.transparent],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = g2);

    // Layer 3: High Density Particles
    final p = Paint()..color = Colors.white.withOpacity(active ? 0.08 : 0.03);
    final count = active ? 120 : 60; // Doubled particle count
    
    for (int i = 0; i < count; i++) {
        final ran = math.Random(i);
        // Complex movement: Sine wave vertical drift + horizontal wind
        double rx = (ran.nextDouble() * size.width + math.sin(v * 2 * math.pi + i) * 20 + v * 50) % size.width;
        double ry = (ran.nextDouble() * size.height + math.cos(v * 2 * math.pi + i) * 30) % size.height;
        
        double radius = ran.nextDouble() * (active ? 2.5 : 1.5);
        if (ran.nextDouble() > 0.95) radius *= 2; // Occasional large bokeh
        
        canvas.drawCircle(Offset(rx, ry), radius, p);
    }
    
    // Layer 4: Subtle Grid lines (Holographic effect)
    if (active) {
       final gridPaint = Paint()..color = Colors.white.withOpacity(0.02)..strokeWidth = 1;
       double gridOffset = (v * 100) % 40;
       for (double i = 0; i < size.height; i += 40) {
         canvas.drawLine(Offset(0, i + gridOffset), Offset(size.width, i + gridOffset), gridPaint);
       }
    }
  }
  @override
  bool shouldRepaint(covariant _CyberPainter old) => true;
}
