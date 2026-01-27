import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:typed_data';
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
  double _currentPosition = 0; // In seconds
  double _totalDuration = 0; // In seconds
  bool _isPlaying = false;
  
  bool _shuffle = false;
  String _repeat = "None";
  double _volume = 1.0;
  String _playerDisplayName = "Media Player";

  late AnimationController _playPauseController;
  late AnimationController _equalizerController;
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    // Faster, more rhythmic equalizer controller
    _equalizerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 450))..repeat();

    _fetchStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchStatus();
    });

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPlaying && _totalDuration > 0) {
        setState(() {
          _currentPosition += 1;
          if (_currentPosition > _totalDuration) {
             _currentPosition = _totalDuration;
          }
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
                final oldTitle = _metadata?['title'];
                _metadata = json['metadata'];
                _isLoading = false;
                if (_metadata != null) {
                  _isPlaying = _metadata!['status'] == "Playing";
                  _totalDuration = (_metadata!['duration'] as num).toDouble() / 1000000;
                  
                  // SYNC POSITION: Only sync if track changed or the jump is huge (>3s)
                  double newPos = (_metadata!['position'] as num).toDouble() / 1000000;
                  if (oldTitle != _metadata!['title'] || (newPos - _currentPosition).abs() > 3 || !_isPlaying) {
                    _currentPosition = newPos;
                  }

                  _shuffle = _metadata!['shuffle'] ?? false;
                  _repeat = _metadata!['repeat'] ?? "None";
                  _volume = (_metadata!['volume'] as num?)?.toDouble() ?? 1.0;
                  
                  String rawName = _metadata!['player_name'] ?? "Media Player";
                  _playerDisplayName = rawName.split('.').first.replaceAll('_', ' ').replaceAll('-', ' ');
                  if (_playerDisplayName.isNotEmpty) {
                    _playerDisplayName = _playerDisplayName.substring(0, 1).toUpperCase() + _playerDisplayName.substring(1);
                  }

                  if (_isPlaying) {
                    _playPauseController.forward();
                    if (!_equalizerController.isAnimating) _equalizerController.repeat();
                  } else {
                    _playPauseController.reverse();
                    _equalizerController.stop();
                  }
                  
                  if (oldTitle != _metadata!['title']) {
                    _updatePalette();
                  }
                }
              });
            }
          } catch (_) {}
        });
    }
  }

  Future<void> _updatePalette() async {
    final artUrl = _metadata?['art_url'];
    if (artUrl != null && artUrl.isNotEmpty && (artUrl.startsWith('http') || artUrl.startsWith('file'))) {
      try {
        final imageProvider = CachedNetworkImageProvider(artUrl);
        final palette = await PaletteGenerator.fromImageProvider(imageProvider);
        if (mounted) {
          setState(() {
            _palette = palette;
          });
        }
      } catch (e) {
        debugPrint("Palette error: $e");
      }
    } else {
       if (mounted) {
        setState(() {
          _palette = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _progressTimer?.cancel();
    _socketSubscription?.cancel();
    _playPauseController.dispose();
    _equalizerController.dispose();
    super.dispose();
  }

  void _fetchStatus() {
    if (widget.socket != null) {
      final event = {"type": "media_get_status"};
      try {
        widget.socket!.write("${jsonEncode(event)}\n");
      } catch (_) {}
    }
  }

  void _sendCommand(String action) {
    if (widget.socket != null) {
      final event = {
        "type": "media_control",
        "data": {"action": action}
      };
      try {
        widget.socket!.write("${jsonEncode(event)}\n");
        HapticFeedback.lightImpact();
        
        // Optimistic UI update for Play/Pause
        if (action == "play_pause") {
          setState(() {
            _isPlaying = !_isPlaying;
            if (_isPlaying) {
              _playPauseController.forward();
              _equalizerController.repeat();
            } else {
              _playPauseController.reverse();
              _equalizerController.stop();
            }
          });
        }
      } catch (_) {}
    }
  }

  void _setVolume(double value) {
     if (widget.socket != null) {
      final event = {
        "type": "media_control",
        "data": {"action": "volume:$value"}
      };
      try {
        widget.socket!.write("${jsonEncode(event)}\n");
        setState(() => _volume = value);
      } catch (_) {}
    }
  }

  String _formatTime(double seconds) {
    if (seconds < 0) seconds = 0;
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = (seconds % 60).toInt();
    return "$minutes:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  Widget _getPlayerIcon(String name, {double size = 20}) {
    String lower = name.toLowerCase();
    if (lower.contains("spotify")) return Icon(Icons.music_note, color: const Color(0xFF1DB954), size: size);
    if (lower.contains("chromium") || lower.contains("chrome") || lower.contains("google")) return Icon(Icons.language, color: const Color(0xFF4285F4), size: size);
    if (lower.contains("vlc")) return Icon(Icons.motion_photos_on, color: const Color(0xFFFF8800), size: size);
    if (lower.contains("firefox")) return Icon(Icons.language, color: const Color(0xFFFF7139), size: size);
    if (lower.contains("mpv")) return Icon(Icons.play_circle_outline, color: Colors.white, size: size);
    if (lower.contains("clementine")) return Icon(Icons.music_note_rounded, color: Colors.orange, size: size);
    return Icon(Icons.music_note, color: Colors.white54, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _palette?.vibrantColor?.color ?? Colors.blueAccent;
    final dominantColor = _palette?.dominantColor?.color ?? Colors.black;

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            SizedBox(height: 24),
            Text("SYNCING MEDIA...", style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2)),
          ],
        )
      );
    }

    if (_metadata == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note_rounded, size: 80, color: Colors.white.withOpacity(0.05)),
            const SizedBox(height: 32),
            const Text("No Media Detected", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("Play something on your PC to see details here.", 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5)
            ),
            const SizedBox(height: 40),
            IconButton(
              onPressed: _fetchStatus,
              icon: const Icon(Icons.refresh, color: Colors.white),
            )
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Dynamic Background
          AnimatedContainer(
            duration: const Duration(seconds: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dominantColor.withOpacity(0.6),
                  Colors.black,
                  Colors.black,
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("NOW PLAYING", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _getPlayerIcon(_playerDisplayName, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _playerDisplayName.toUpperCase(), 
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                         _Equalizer(color: accentColor, isPlaying: _isPlaying),
                      ],
                    ),
                    
                    const SizedBox(height: 46),
                    
                    // Album Art
                    Center(
                      child: Container(
                        width: math.min(MediaQuery.of(context).size.width * 0.8, 320),
                        height: math.min(MediaQuery.of(context).size.width * 0.8, 320),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withOpacity(0.35),
                              blurRadius: 60,
                              spreadRadius: 2,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _metadata?['art_url']?.isNotEmpty == true
                              ? CachedNetworkImage(
                                  imageUrl: _metadata!['art_url'],
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.white.withOpacity(0.02)),
                                  errorWidget: (context, url, e) => _PlaceholderArt(),
                                )
                              : _PlaceholderArt(),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 46),
                    
                    // Title & Artist
                    Column(
                      children: [
                        Text(
                          _metadata?['title'] ?? "Unknown Track",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.8),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _metadata?['artist'] ?? "Unknown Artist",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 46),
                    
                    // Progress Slider
                    Column(
                      children: [
                         SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            thumbShape: SliderComponentShape.noThumb,
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: accentColor,
                            inactiveTrackColor: Colors.white.withOpacity(0.1),
                          ),
                          child: Slider(
                            value: _currentPosition.clamp(0, _totalDuration > 0 ? _totalDuration : 1),
                            max: _totalDuration > 0 ? _totalDuration : 1,
                            onChanged: (v) {},
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatTime(_currentPosition), style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                            // ALWAYS show total duration, or 0:00 if unknown, but don't hide it
                            Text(_formatTime(_totalDuration), style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          ],
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 46),
                    
                    // Control Hub
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.shuffle, 
                                    color: _shuffle ? accentColor : Colors.white24, 
                                    size: 22
                                  ),
                                  onPressed: () => _sendCommand("toggle_shuffle"),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous_rounded, size: 48, color: Colors.white),
                                  onPressed: () => _sendCommand("previous"),
                                ),
                                const SizedBox(width: 16),
                                // Play/Pause
                                GestureDetector(
                                  onTap: () => _sendCommand("play_pause"),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 25, spreadRadius: 2)
                                      ]
                                    ),
                                    child: Center(
                                      child: AnimatedIcon(
                                        icon: AnimatedIcons.play_pause,
                                        progress: _playPauseController,
                                        color: Colors.black,
                                        size: 38,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                IconButton(
                                  icon: const Icon(Icons.skip_next_rounded, size: 48, color: Colors.white),
                                  onPressed: () => _sendCommand("next"),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    _repeat == "Track" ? Icons.repeat_one : Icons.repeat, 
                                    color: _repeat != "None" ? accentColor : Colors.white24, 
                                    size: 22
                                  ),
                                  onPressed: () => _sendCommand("toggle_loop"),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          
                          // Volume Hub
                          Row(
                            children: [
                              const Icon(Icons.volume_mute, color: Colors.white24, size: 18),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: Colors.white60,
                                    inactiveTrackColor: Colors.white.withOpacity(0.05),
                                    thumbColor: Colors.white,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  ),
                                  child: Slider(
                                    value: _volume,
                                    onChanged: (v) => _setVolume(v),
                                  ),
                                ),
                              ),
                              const Icon(Icons.volume_up, color: Colors.white60, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderArt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.01),
      child: Center(
        child: Icon(Icons.music_note_rounded, size: 100, color: Colors.white.withOpacity(0.02)),
      ),
    );
  }
}

class _Equalizer extends StatefulWidget {
  final Color color;
  final bool isPlaying;

  const _Equalizer({required this.color, required this.isPlaying});

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final math.Random _random = math.Random();
  final List<double> _heights = List.filled(5, 4.0);
  final List<double> _targets = List.filled(5, 4.0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_updateHeights);
    
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(_Equalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _controller.repeat();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _controller.stop();
    }
  }

  void _updateHeights() {
    if (!widget.isPlaying) return;
    
    setState(() {
      for (int i = 0; i < 5; i++) {
        // Pulse logic: if we are near target, pick a new random target
        if ((_heights[i] - _targets[i]).abs() < 1.0) {
          // Simulate "beats" with higher probability of high spikes
          double base = _random.nextDouble();
          if (base > 0.8) {
            _targets[i] = 15 + _random.nextDouble() * 13; // Big spike (kick)
          } else {
            _targets[i] = 4 + _random.nextDouble() * 12; // Normal flutter
          }
        }
        
        // Linear interpolation/decay for smoothness
        // Fast rise, medium decay
        double speed = _targets[i] > _heights[i] ? 0.4 : 0.15;
        _heights[i] = lerpDouble(_heights[i], _targets[i], speed)!;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (index) {
          double h = widget.isPlaying ? _heights[index] : 4.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: widget.isPlaying 
                ? widget.color.withOpacity(0.4 + (h / 28 * 0.6)) 
                : Colors.white12,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                if (h > 18 && widget.isPlaying) 
                  BoxShadow(color: widget.color.withOpacity(0.3), blurRadius: 4)
              ]
            ),
          );
        }),
      ),
    );
  }
}
