import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wayland_connect_android/l10n/app_localizations.dart';

import '../utils/protocol.dart';
import './media/particle_field.dart';
import './media/equalizer_view.dart';
import './media/album_art_view.dart';
import './media/player_controls.dart';
import './media/media_header.dart';
import './media/album_info_view.dart';
import './media/particle_drawing_modal.dart';

class MediaScreen extends StatefulWidget {
  final Socket? socket;
  final Stream<Uint8List>? socketStream;
  final bool isActiveTab;
  final Stream<String>? volumeStream;

  const MediaScreen({super.key, required this.socket, this.socketStream, this.isActiveTab = false, this.volumeStream});

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
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(1.0);
  final ValueNotifier<double> _positionNotifier = ValueNotifier(0.0);
  String _playerDisplayName = "PLAYER";
  String _rawPlayerName = "";
  DateTime? _lastDataTime;
  Timer? _watchdogTimer;

  late AnimationController _playPauseController;
  late AnimationController _floatController;
  late AnimationController _particleController;
  late AnimationController _eqButtonController;
  AnimationController? _breathingController;
  AnimationController? _vinylController;
  StreamSubscription? _socketSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  double _tiltX = 0;
  double _tiltY = 0;
  final ValueNotifier<Offset> _tiltNotifier = ValueNotifier(Offset.zero);
  bool _isDraggingSlider = false;
  int _eqMode = 0; 
  int _frameShape = 1; 
  int _colorIndex = 0; 
  double _eqSensitivity = 1.0; 
  double _particleSpeed = 1.0;
  double _particleDensity = 1.0;
  double _particleSize = 1.0;
  int _particleShape = 0; // 0: Random, 1: Circle, 2: Square, 3: Triangle, 4: Star, 5: Heart, 6: Hexagon, 7: Custom
  int _colorVariantsCount = 2;
  List<Color> _extractedPalette = [];
  List<Offset>? _customParticlePath;
  final List<Color?> _presetColors = [null, Colors.redAccent, Colors.cyanAccent, Colors.pinkAccent, Colors.orangeAccent, Colors.purpleAccent];
  List<String> _colorNames(BuildContext context) => [
    AppLocalizations.of(context)!.colorDynamic,
    AppLocalizations.of(context)!.colorCrimson,
    AppLocalizations.of(context)!.colorNeon,
    AppLocalizations.of(context)!.colorRose,
    AppLocalizations.of(context)!.colorAmber,
    AppLocalizations.of(context)!.colorPurple
  ];
  final ValueNotifier<Map<String, double>?> _spectrumNotifier = ValueNotifier(null);
  final ProtocolHandler _protocolHandler = ProtocolHandler();

  int _abstractTextIndex = 0;
  Timer? _abstractTextTimer;
  List<String> _abstractTexts(BuildContext context) => [
    AppLocalizations.of(context)!.abstractText1,
    AppLocalizations.of(context)!.abstractText2,
    AppLocalizations.of(context)!.abstractText3,
    AppLocalizations.of(context)!.abstractText4,
    AppLocalizations.of(context)!.abstractText5,
    AppLocalizations.of(context)!.abstractText6,
    AppLocalizations.of(context)!.abstractText7
  ];

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _eqButtonController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

    if (_isPlaying) _eqButtonController.forward();
    _setupConnection();
    _initGyro();
    _loadParticleSettings();
    _startAbstractTextTimer();
    
    widget.volumeStream?.listen((event) {
       if (!widget.isActiveTab || !mounted) return;
       if (event == 'volume_up') {
          _volumeNotifier.value = (_volumeNotifier.value + 0.05).clamp(0.0, 1.0);
          _setVolume(_volumeNotifier.value);
       } else if (event == 'volume_down') {
          _volumeNotifier.value = (_volumeNotifier.value - 0.05).clamp(0.0, 1.0);
          _setVolume(_volumeNotifier.value);
       }
    });
  }

  @override
  void didUpdateWidget(covariant MediaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.socket != oldWidget.socket || widget.socketStream != oldWidget.socketStream) {
       debugPrint("🔄 MediaScreen: Socket updated, resyncing connection...");
       _setupConnection();
    }
  }

  void _setupConnection() {
    _socketSubscription?.cancel();
    _statusTimer?.cancel();
    _progressTimer?.cancel();
    _watchdogTimer?.cancel();

    _lastDataTime = DateTime.now();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_lastDataTime != null && DateTime.now().difference(_lastDataTime!).inSeconds > 5) {
        if (!_isSearching) {
          debugPrint("⏰ MediaScreen: Watchdog triggered (no data for 5s). Resetting state...");
          _resetToEmptyState();
        }
      }
    });

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
        _positionNotifier.value += 1;
        if (_positionNotifier.value > _totalDuration) _positionNotifier.value = _totalDuration;
      }
    });

    if (widget.socketStream != null) {
      _socketSubscription = widget.socketStream!.listen(
        (data) {
          if (!mounted) return;
          _lastDataTime = DateTime.now();
          try {
            final packets = _protocolHandler.process(data);
            for (final packet in packets) {
               if (packet is! Map) continue;
               final Map<dynamic, dynamic> json = packet;
               
               // Binary Packet: Spectrum (t="s")
                if (json['t'] == 's') {
                   final d = json['d'] ?? json;
                   if (d['bands'] != null) {
                     final List<dynamic> bands = d['bands'];
                     final Map<String, double> specMap = {};
                     for (int i = 0; i < bands.length; i++) {
                       specMap['band_$i'] = (bands[i] as num).toDouble();
                     }
                     // Keep 'low', 'mid', 'high' for legacy components if needed, 
                     // but mapping to indices is better for 7+ bands
                     specMap['low'] = specMap['band_0'] ?? 0.0;
                     specMap['mid'] = specMap['band_3'] ?? 0.0;
                     specMap['high'] = specMap['band_6'] ?? 0.0;
                     _spectrumNotifier.value = specMap;
                   }
                   continue;
                }

               // Standard Control Packets
               final type = json['type']?.toString();
               final data = json['data'];
               
               if (type == 'media_status') {
                  setState(() {
                    _isSearching = false;
                    final oldTitle = _metadata?['title'];
                    _metadata = (data != null && data['metadata'] != null) 
                        ? Map<String, dynamic>.from(data['metadata']) 
                        : null;
                    _isLoading = false;
                    if (_metadata != null) {
                      _isPlaying = _metadata!['status'] == "Playing";
                      _totalDuration = (_metadata!['duration'] as num).toDouble() / 1000000;
                      double newPos = (_metadata!['position'] as num).toDouble() / 1000000;
                      if (!_isDraggingSlider) {
                        if (oldTitle != _metadata!['title'] || (newPos - _positionNotifier.value).abs() > 3 || !_isPlaying) {
                          _positionNotifier.value = newPos;
                        }
                      }
                      _shuffle = _metadata!['shuffle'] ?? false;
                      _repeat = _metadata!['repeat'] ?? "None";
                      _volumeNotifier.value = (_metadata!['volume'] as num?)?.toDouble() ?? 1.0;
                      _rawPlayerName = (_metadata!['player_name'] ?? "Player").toString().toLowerCase();
                      _playerDisplayName = _rawPlayerName.split('.').first.toUpperCase();

                      if (_isPlaying) {
                         _playPauseController.forward();
                         _eqButtonController.forward();
                         _floatController.repeat(reverse: true);
                         _breathingController?.repeat(reverse: true);
                         _vinylController?.repeat();
                         _startAbstractTextTimer();
                      } else {
                         _playPauseController.reverse();
                         _eqButtonController.reverse();
                         _floatController.stop();
                         _breathingController?.stop();
                         _vinylController?.stop();
                         _abstractTextTimer?.cancel();
                         _spectrumNotifier.value = {'low': 0.0, 'mid': 0.0, 'high': 0.0};
                      }
                      if (oldTitle != _metadata!['title']) _updatePalette();
                    }
                  });
               }
            }
          } catch (_) {}
        },
        onDone: () {
          debugPrint("📡 MediaScreen: Socket stream closed.");
          _resetToEmptyState();
        },
        onError: (e) {
          debugPrint("❌ MediaScreen: Socket stream error: $e");
          _resetToEmptyState();
        },
      );
    }
  }

  Future<void> _updatePalette() async {
    final artUrl = _metadata?['art_url'];
    if (artUrl != null && artUrl.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(artUrl));
        _extractedPalette = palette.colors.toList();
        if (mounted) setState(() => _palette = palette);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _gyroSubscription?.cancel();
    _statusTimer?.cancel();
    _progressTimer?.cancel();
    _playPauseController.dispose();
    _floatController.dispose();
    _particleController.dispose();
    _eqButtonController.dispose();
    _breathingController?.dispose();
    _vinylController?.dispose();
    _spectrumNotifier.dispose();
    _volumeNotifier.dispose();
    _positionNotifier.dispose();
    _tiltNotifier.dispose();
    _abstractTextTimer?.cancel();
    super.dispose();
  }

  void _initGyro() {
    _gyroSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      if (!mounted || !widget.isActiveTab) return;
      _tiltY = (_tiltY + event.y * 0.02).clamp(-0.2, 0.2);
      _tiltX = (_tiltX - event.x * 0.02).clamp(-0.2, 0.2);
      _tiltX *= 0.88; 
      _tiltY *= 0.88;
      _tiltNotifier.value = Offset(_tiltX, _tiltY);
    });
  }

  void _startAbstractTextTimer() {
    _abstractTextTimer?.cancel();
    _abstractTextTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _abstractTextIndex = (_abstractTextIndex + 1) % _abstractTexts(context).length);
    });
  }

  Future<void> _loadParticleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _particleDensity = prefs.getDouble('media_particle_density') ?? 1.0;
      _particleSpeed = prefs.getDouble('media_particle_speed') ?? 1.0;
      _particleSize = prefs.getDouble('media_particle_size') ?? 1.0;
      _particleShape = prefs.getInt('media_particle_shape') ?? 0;
      _colorVariantsCount = prefs.getInt('media_color_variants') ?? 2;
      
      String? customPathString = prefs.getString('media_custom_particle_path');
      if (customPathString != null) {
        try {
          List<dynamic> points = jsonDecode(customPathString);
          _customParticlePath = points.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList();
        } catch (e) {
          debugPrint("Failed to load custom particle path: $e");
        }
      }
    });
  }

  Future<void> _saveParticleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('media_particle_density', _particleDensity);
    await prefs.setDouble('media_particle_speed', _particleSpeed);
    await prefs.setDouble('media_particle_size', _particleSize);
    await prefs.setInt('media_particle_shape', _particleShape);
    await prefs.setInt('media_color_variants', _colorVariantsCount);
    
    if (_customParticlePath != null) {
      String json = jsonEncode(_customParticlePath!.map((p) => {'x': p.dx, 'y': p.dy}).toList());
      await prefs.setString('media_custom_particle_path', json);
    }
  }

  void _fetchStatus() {
    if (widget.socket != null) {
      final event = {"type": "media_get_status"};
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
    }
  }

  void _resetToEmptyState() {
    if (!mounted) return;
    setState(() {
      _metadata = null;
      _isPlaying = false;
      _isSearching = true;
      _positionNotifier.value = 0;
      _totalDuration = 0;
      _isLoading = false;
    });
    _playPauseController.reverse();
    _eqButtonController.reverse();
    _floatController.stop();
    _breathingController?.stop();
    _vinylController?.stop();
    _abstractTextTimer?.cancel();
    _spectrumNotifier.value = null;
  }

  void _sendCommand(String action) {
    if (widget.socket != null) {
      final event = {
        "type": "media_control", 
        "data": {"action": action}
      };
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
    }
    if (action == "next" || action == "previous") {
      setState(() {
        _metadata ??= {
          'title': AppLocalizations.of(context)!.syncing,
          'artist': AppLocalizations.of(context)!.fastTrackJump,
          'status': "Playing",
          'art_url': _metadata?['art_url'],
          'duration': 0.0,
          'position': 0.0,
          'player_name': _metadata?['player_name'],
        };
        _positionNotifier.value = 0;
      });
      HapticFeedback.mediumImpact();
    } else if (action == "play_pause") {
      setState(() {
        _isPlaying = !_isPlaying;
        if (_isPlaying) {
          _playPauseController.forward();
          _eqButtonController.forward();
          _floatController.repeat(reverse: true);
          _breathingController?.repeat(reverse: true);
          _vinylController?.repeat();
        } else {
          _playPauseController.reverse();
          _eqButtonController.reverse();
          _floatController.stop();
          _breathingController?.stop();
          _vinylController?.stop();
        }
      });
      HapticFeedback.mediumImpact();
    }
    try { widget.socket?.flush(); } catch (_) {}
  }

  void _seek(double seconds) {
    if (widget.socket != null) {
      final usecs = (seconds * 1000000).toInt();
      final event = {
        "type": "media_control",
        "data": {"action": "seek:$usecs"}
      };
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
    }
  }

  void _setVolume(double value) {
     if (widget.socket != null) {
      final event = {
        "type": "media_control",
        "data": {"action": "volume:$value"}
      };
      try { widget.socket!.add(ProtocolHandler.encodePacket(event)); } catch (_) {}
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
    return Icons.settings_input_component_rounded;
  }

  @override
  Widget build(BuildContext context) {
    _breathingController ??= AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _vinylController ??= AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    if (!_isPlaying) {
      _floatController.stop();
      _breathingController?.stop();
      _vinylController?.stop();
    }
    Color accentColor;
    Color dominantColor;
    Color bgColor = Colors.black;
    if (_colorIndex == 0) {
       final p = _palette;
       accentColor = p?.vibrantColor?.color ?? p?.lightVibrantColor?.color ?? p?.darkVibrantColor?.color ?? p?.lightMutedColor?.color ?? p?.dominantColor?.color ?? Colors.blueAccent;
       dominantColor = _palette?.dominantColor?.color ?? _palette?.darkMutedColor?.color ?? Colors.black;
       if (dominantColor.computeLuminance() < 0.05) dominantColor = accentColor.withOpacity(0.5);
       Color baseForBg = dominantColor.computeLuminance() < 0.01 ? accentColor : dominantColor;
       bgColor = Color.lerp(Colors.black, baseForBg, 0.2) ?? Colors.black;
    } else {
       accentColor = _presetColors[_colorIndex]!;
       // Make background more distinct for presets (darker but color-tinted)
       bgColor = Color.lerp(Colors.black, accentColor, 0.15) ?? const Color(0xFF050505);
       dominantColor = accentColor.withOpacity(0.2);
    }

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (_colorIndex == 0 && _metadata?['art_url'] != null && _metadata!['art_url'].isNotEmpty)
            Positioned.fill(
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                      CachedNetworkImage(
                        imageUrl: _metadata!['art_url'], 
                        fit: BoxFit.cover, 
                        memCacheHeight: 200, 
                        memCacheWidth: 200,
                        errorWidget: (context, url, error) => const SizedBox.shrink()
                      ),
                      BackdropFilter(filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60), child: Container(color: Colors.black.withOpacity(0.7))),
                  ],
                ),
              ),
            ),
          if (_metadata != null) ...[
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, _) => CustomPaint(painter: CyberPainter(dominantColor.withOpacity(0.3), accentColor.withOpacity(0.15), _particleController.value, _isPlaying), size: Size.infinite),
              ),
            ),
            Positioned.fill(
               child: ValueListenableBuilder<Map<String, double>?>(
                 valueListenable: _spectrumNotifier,
                 builder: (context, spectrum, _) {
                   List<Color> palette = [];
                   if (_colorIndex == 0) {
                     palette = _extractedPalette.take(_colorVariantsCount).toList();
                     if (palette.isEmpty) palette = [dominantColor, accentColor];
                   } else {
                     palette = [accentColor];
                   }
                   
                   return MusicParticleField(
                     isPlaying: _isPlaying,
                     accent: accentColor,
                     spectrum: spectrum,
                     frameShape: _frameShape,
                     speedMultiplier: _particleSpeed,
                     densityMultiplier: _particleDensity,
                     sizeMultiplier: _particleSize,
                     particleShape: _particleShape,
                     customShapePath: _customParticlePath,
                     paletteColors: palette,
                   );
                 },
               ),
            ),
          ],
          if (_eqMode == 4 && _isPlaying && _metadata != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: _frameShape == 2 ? const Alignment(-1.0, 0.2) : const Alignment(1.0, -0.4),
                  child: SizedBox(
                     width: 30,
                     height: 160,
                     child: ValueListenableBuilder<Map<String, double>?>(
                        valueListenable: _spectrumNotifier,
                        builder: (context, spec, _) => CustomPaint(painter: SideVerticalSpectrumPainter(accentColor, spec, alignLeft: _frameShape == 2))
                     )
                  ),
                ),
              ),
            ),
           if (_isLoading) _buildSpinner()
           else if (_isSearching) _buildSearchingState()
           else if (_metadata == null) _buildEmptyState()
           else Positioned.fill(child: SafeArea(child: Padding(padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
             if (_frameShape != 2) _buildVerticalEQ(accentColor),
             const SizedBox(width: 12),
             Expanded(child: Column(children: [
               const SizedBox(height: 12),
               _buildHeader(accentColor),
               const SizedBox(height: 8),
               Expanded(child: _buildLayout(accentColor)),
             ])),
           ])))),
           Positioned(top: 35, left: 0, right: 0, child: IgnorePointer(child: _buildTopHUD(accentColor))),
        ],
      ),
    );
  }

  Widget _buildLayout(Color accent) {
    if (_frameShape == 2) return _buildCircleLayout(accent);
    return _buildSquareLayout(accent); // Square and Wide share logic
  }

  // Helper widgets that assemble the modules
  Widget _buildHeader(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: _isPlaying ? accent.withOpacity(0.9) : Colors.white10, borderRadius: BorderRadius.circular(6), boxShadow: _isPlaying ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 10, spreadRadius: -2)] : []),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_getPlayerIcon(), color: _isPlaying ? Colors.black87 : Colors.white24, size: 16),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.of(context)!.nowPlaying, style: TextStyle(color: _isPlaying ? Colors.black54 : Colors.white24, fontSize: 5, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2)])),
              Text(_playerDisplayName, style: TextStyle(color: _isPlaying ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 4)])),
            ]),
          ]),
        ),
        Expanded(child: Center(child: GestureDetector(
          onTap: () => setState(() => _colorIndex = (_colorIndex + 1) % _presetColors.length),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withOpacity(0.3), width: 0.8), boxShadow: [BoxShadow(color: accent.withOpacity(0.1), blurRadius: 10, spreadRadius: -2)]), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(_colorNames(context)[_colorIndex], style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
          ])),
        ))),
        SmartFrameToggle(current: _frameShape, accent: accent, isPlaying: _isPlaying, onChanged: (s) => setState(() => _frameShape = s)),
      ],
    );
  }

  Widget _buildTopHUD(Color accent) {
    if (_metadata == null) return const SizedBox.shrink();
    return SizedBox(height: 35, child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
      SizedBox(width: 250, child: AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: GlitchyAbstractText(
        text: _abstractTexts(context)[_abstractTextIndex], 
        key: ValueKey(_abstractTextIndex),
        style: TextStyle(color: accent.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2.5, shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 4)]),
        isPlaying: _isPlaying,
        accent: accent,
      ))),
      Positioned(right: 20, child: Opacity(opacity: 0.6, child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield_outlined, color: accent.withOpacity(0.2), size: 10),
        const SizedBox(width: 8),
        Text(AppLocalizations.of(context)!.secureLink, style: TextStyle(color: accent.withOpacity(0.15), fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 1, shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2)])),
      ]))),
    ]));
  }

  Widget _buildSquareLayout(Color accent) {
    return Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(flex: 4, child: Row(children: [
        Expanded(child: Align(alignment: Alignment.center, child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          RepaintBoundary(child: RotatingOrbitalGlow(accent: accent, isPlaying: _isPlaying, size: 240, orbitRadius: 90)),
          _buildInteractiveStage(accent),
        ]))),
      ])),
      Expanded(flex: 6, child: Align(alignment: Alignment.bottomCenter, child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 4), physics: const NeverScrollableScrollPhysics(), children: [
        _buildInfoCluster(accent),
        const SizedBox(height: 8),
        _buildSeekingModule(accent),
        const SizedBox(height: 4),
        _buildDock(accent, isVertical: false),
        const SizedBox(height: 10),
      ]))),
    ]);
  }

  Widget _buildCircleLayout(Color accent) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        SizedBox(height: 140, width: 40, child: Column(children: [
          Text(AppLocalizations.of(context)!.volume, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: ValueListenableBuilder<double>(
            valueListenable: _volumeNotifier,
            builder: (context, vol, _) => ParticleVolumeBar(value: vol, color: accent, isVertical: true, onChanged: (v) => _volumeNotifier.value = v, onChangeEnd: _setVolume),
          )),
        ])),
        _buildVerticalEQ(accent, compact: true),
      ]),
      const SizedBox(width: 8),
      Expanded(flex: 12, child: Column(children: [
        Expanded(child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
          Transform.translate(offset: const Offset(-30, 20), child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Container(width: 320, height: 320, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent.withOpacity(0.08), width: 1.5)), child: RepaintBoundary(child: CustomPaint(painter: OrbitalRingPainter(accent)))),
            Transform.scale(scale: 1.1, child: _buildInteractiveStage(accent)),
          ])),
          Positioned(top: 15, left: -10, child: OrbitalStatus(accent: accent, label: "SYS_NODE", value: "LINKED")),
          Positioned(bottom: 15, left: 72, child: OrbitalStatus(accent: accent, label: "BUFFER", value: "STABLE")),
        ])),
      ])),
      Expanded(flex: 8, child: Stack(clipBehavior: Clip.none, children: [
        Positioned(top: 10, left: -80, right: 0, child: Align(alignment: Alignment.centerLeft, child: VinylInfoCard(accent: accent, metadata: _metadata, isPlaying: _isPlaying))),
        Positioned(bottom: 0, left: 0, child: _buildDock(accent, isVertical: true)),
      ])),
      const SizedBox(width: 8),
      Container(width: 44, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.08))), child: Row(children: [
        Expanded(child: _buildVerticalSeeking(accent)),
      ])),
    ]));
  }

  Widget _buildVerticalSeeking(Color accent) {
    return ValueListenableBuilder<double>(
      valueListenable: _positionNotifier,
      builder: (context, pos, _) {
        double progress = (pos / (_totalDuration > 0 ? _totalDuration : 1)).clamp(0.0, 1.0);
        return Column(children: [
          Text(_formatTime(_totalDuration), style: const TextStyle(color: Colors.white12, fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(child: QuantumProgressBar(value: progress, color: accent, isVertical: true, onChanged: (v) { _isDraggingSlider = true; _positionNotifier.value = v * _totalDuration; }, onChangeEnd: (v) { _isDraggingSlider = false; _seek(v * _totalDuration); })),
          const SizedBox(height: 12),
          Text(_formatTime(pos), style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        ]);
      }
    );
  }

  Widget _buildDock(Color accent, {required bool isVertical}) {
    // Buttons list for reuse
    final buttons = [
      _buildControlBtn(Icons.shuffle_rounded, 18, _shuffle ? accent : Colors.white24, () => _sendCommand("toggle_shuffle")),
      if (isVertical) const SizedBox(height: 16) else const SizedBox(width: 8),
      _buildControlBtn(Icons.skip_previous_rounded, 26, Colors.white, () => _sendCommand("previous")),
      if (isVertical) const SizedBox(height: 16) else const SizedBox(width: 12),
      GestureDetector(
        onTap: () => _sendCommand("play_pause"), 
        child: Container(
          width: 56, height: 56, 
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent.withOpacity(0.3), blurRadius: 20)]), 
          child: Center(child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _playPauseController, color: Colors.black, size: 28))
        )
      ),
      if (isVertical) const SizedBox(height: 16) else const SizedBox(width: 12),
      _buildControlBtn(Icons.skip_next_rounded, 26, Colors.white, () => _sendCommand("next")),
      if (isVertical) const SizedBox(height: 16) else const SizedBox(width: 8),
      _buildControlBtn(_repeat == "Track" ? Icons.repeat_one_rounded : Icons.repeat_rounded, 18, _repeat != "None" ? accent : Colors.white24, () => _sendCommand("toggle_loop")),
    ];

    final content = Column(mainAxisSize: MainAxisSize.min, children: [
      if (!isVertical) ...[
        Row(children: [
          Icon(Icons.volume_down_rounded, size: 16, color: Colors.white.withOpacity(0.4)),
          const SizedBox(width: 12),
          Expanded(child: ValueListenableBuilder<double>(
            valueListenable: _volumeNotifier,
            builder: (context, vol, _) => ParticleVolumeBar(value: vol, color: accent, onChanged: (v) => _volumeNotifier.value = v, onChangeEnd: _setVolume),
          )),
          const SizedBox(width: 12),
          Icon(Icons.volume_up_rounded, size: 16, color: Colors.white.withOpacity(0.4)),
        ]),
        const SizedBox(height: 12),
      ],
      FittedBox(
        fit: BoxFit.scaleDown, 
        child: isVertical 
            ? Column(mainAxisAlignment: MainAxisAlignment.spaceAround, children: buttons)
            : Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: buttons),
      ),
    ]);

    if (isVertical) return Container(padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white.withOpacity(0.08))), child: content);
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))), child: content)));
  }

  Widget _buildSeekingModule(Color accent) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05)), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.02), Colors.transparent])), child: Column(children: [
      ValueListenableBuilder<double>(
        valueListenable: _positionNotifier,
        builder: (context, pos, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_formatTime(pos), style: TextStyle(color: accent.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
          Text(_formatTime(_totalDuration), style: const TextStyle(color: Colors.white24, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        ]),
      ),
      const SizedBox(height: 12),
      ValueListenableBuilder<double>(
        valueListenable: _positionNotifier,
        builder: (context, pos, _) {
          double progress = (pos / (_totalDuration > 0 ? _totalDuration : 1)).clamp(0.0, 1.0);
          return ValueListenableBuilder<Map<String, double>?>(
            valueListenable: _spectrumNotifier,
            builder: (context, spectrum, _) => RepaintBoundary(child: QuantumProgressBar(value: progress, color: accent, spectrum: spectrum, onChanged: (v) { _isDraggingSlider = true; _positionNotifier.value = v * _totalDuration; }, onChangeEnd: (v) { _isDraggingSlider = false; _seek(v * _totalDuration); })),
          );
        }
      ),
    ]));
  }

  Widget _buildVerticalEQ(Color accent, {bool compact = false}) {
    return Container(
      width: 38,
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (compact) 
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       GestureDetector(
                        onTap: () => _showParticleSettings(accent),
                        child: Icon(Icons.blur_on_rounded, size: 14, color: accent.withOpacity(0.6)),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _showEQSettings(accent),
                        child: Icon(Icons.tune_rounded, size: 14, color: accent.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _eqMode = (_eqMode + 1) % 15),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    if (!compact) ...[
                      RotatedBox(
                        quarterTurns: 3,
                        child: Text(AppLocalizations.of(context)!.equalizerSystem, style: TextStyle(color: accent.withOpacity(0.3), fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 3))
                      ),
                      const SizedBox(height: 24),
                    ],
                    Icon(_getEqIcon(_eqMode), size: 16, color: _eqMode == 14 ? Colors.white24 : accent),
                    const SizedBox(height: 12),
                    RotatedBox(
                      quarterTurns: 3,
                      child: Text(_getEqName(_eqMode), style: TextStyle(color: _eqMode == 14 ? Colors.white24 : accent, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1))
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
              ],
            ],
          ),
          if (!compact) ...[
            Positioned(
              top: 4,
              child: GestureDetector(
                onTap: () => _showParticleSettings(accent),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.transparent, shape: BoxShape.circle),
                  child: Icon(Icons.blur_on_rounded, size: 14, color: accent.withOpacity(0.6)),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              child: GestureDetector(
                onTap: () => _showEQSettings(accent),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.transparent, shape: BoxShape.circle),
                  child: Icon(Icons.tune_rounded, size: 14, color: accent.withOpacity(0.6)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showEQSettings(Color accent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: accent.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: accent.withOpacity(0.05), blurRadius: 40, spreadRadius: 10)],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: accent, size: 20),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.visualIntensity, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: 18)),
              ],
            ),
            const SizedBox(height: 32),
            StatefulBuilder(builder: (context, setModalState) => Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    activeTrackColor: accent,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: accent,
                    overlayColor: accent.withOpacity(0.1),
                  ),
                  child: Slider(
                    value: _eqSensitivity,
                    min: 0.1,
                    max: 3.0,
                    onChanged: (v) {
                      setModalState(() => _eqSensitivity = v);
                      setState(() => _eqSensitivity = v);
                      if (widget.socket != null) {
                         try {
                           final packet = { "type": "set_audio_sensitivity", "data": { "value": v } };
                           widget.socket!.add(ProtocolHandler.encodePacket(packet));
                         } catch (e) { print("Error sending sensitivity: $e"); }
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppLocalizations.of(context)!.min, style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8, fontWeight: FontWeight.bold)),
                      Text("${_eqSensitivity.toStringAsFixed(1)}X", style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900)),
                      Text(AppLocalizations.of(context)!.max, style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            )),
          ],
        ),
      ),
    );
  }

  void _showParticleSettings(Color accent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: 550,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: accent.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: accent.withOpacity(0.05), blurRadius: 40, spreadRadius: 10)],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.blur_on_rounded, color: accent, size: 20),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.particleEnvironment, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: 18)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: StatefulBuilder(builder: (context, setModalState) => ListView(
                children: [
                   _buildParticleSlider("DENSITY", _particleDensity, (v) => setState(() => _particleDensity = v), setModalState, accent),
                   const SizedBox(height: 12),
                   _buildParticleSlider("SPEED", _particleSpeed, (v) => setState(() => _particleSpeed = v), setModalState, accent),
                   const SizedBox(height: 12),
                   _buildParticleSlider("SIZE", _particleSize, (v) => setState(() => _particleSize = v), setModalState, accent),
                   const SizedBox(height: 12),
                   if (_colorIndex == 0) ...[
                     _buildParticleSlider("COLOR VARIANTS", _colorVariantsCount.toDouble(), (v) => setState(() => _colorVariantsCount = v.toInt()), setModalState, accent, min: 2, max: 6, divisions: 4),
                     const SizedBox(height: 12),
                   ],
                   _buildParticleShapeSelector(setModalState, accent),
                   const SizedBox(height: 24),
                   _buildTemplatesSection(setModalState, accent, context),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesSection(StateSetter setModalState, Color accent, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.presets, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTemplateBtn(AppLocalizations.of(context)!.cosmic, 2.0, 1.5, 1.0, 4, setModalState, accent), // Density, Speed, Size, Shape (Star)
              _buildTemplateBtn(AppLocalizations.of(context)!.rain, 3.0, 2.5, 0.5, 2, setModalState, accent), // Square/Line
              _buildTemplateBtn(AppLocalizations.of(context)!.neon, 1.2, 0.8, 1.8, 1, setModalState, accent), // Circle
              _buildTemplateBtn(AppLocalizations.of(context)!.heartbeat, 1.5, 1.0, 1.2, 5, setModalState, accent), // Heart
              _buildTemplateBtn(AppLocalizations.of(context)!.cyber, 1.0, 1.0, 1.0, 6, setModalState, accent), // Hexagon
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateBtn(String name, double d, double sp, double sz, int sh, StateSetter setModalState, Color accent) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _particleDensity = d;
          _particleSpeed = sp;
          _particleSize = sz;
          _particleShape = sh;
        });
        setModalState(() {});
        _saveParticleSettings();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildParticleSlider(String label, double value, Function(double) onChanged, StateSetter setModalState, Color accent, {double min = 0.2, double max = 3.0, int? divisions}) {
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
             Text("${value.toStringAsFixed(divisions != null ? 0 : 1)}${divisions != null ? '' : 'X'}", style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900)),
           ],
         ),
         SliderTheme(
           data: SliderThemeData(
             trackHeight: 2,
             thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
             activeTrackColor: accent,
             inactiveTrackColor: Colors.white10,
             thumbColor: accent,
             overlayColor: accent.withOpacity(0.1),
           ),
           child: Slider(
             value: value,
             min: min,
             max: max,
             divisions: divisions,
             onChanged: (v) {
               setModalState(() => onChanged(v));
             },
           ),
         ),
       ],
     );
  }

  Widget _buildParticleShapeSelector(StateSetter setModalState, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.particleGeometry, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildShapeBtn(0, Icons.shuffle_rounded, setModalState, accent),
              _buildShapeBtn(1, Icons.circle, setModalState, accent),
              _buildShapeBtn(2, Icons.crop_square_rounded, setModalState, accent),
              _buildShapeBtn(3, Icons.change_history_rounded, setModalState, accent),
              _buildShapeBtn(4, Icons.star_rounded, setModalState, accent),
              _buildShapeBtn(5, Icons.favorite_rounded, setModalState, accent),
              _buildShapeBtn(6, Icons.hexagon_rounded, setModalState, accent),
              _buildShapeBtn(7, Icons.draw_rounded, setModalState, accent, isCustom: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShapeBtn(int index, IconData icon, StateSetter setModalState, Color accent, {bool isCustom = false}) {
    bool isSelected = _particleShape == index;
    return GestureDetector(
      onTap: () {
        if (isCustom) {
           _openShapeDrawer();
        } else {
          setModalState(() => _particleShape = index);
          setState(() => _particleShape = index);
          _saveParticleSettings();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? accent : Colors.transparent),
        ),
        child: Icon(icon, color: isSelected ? accent : Colors.white24, size: 20),
      ),
    );
  }

  void _openShapeDrawer() {
     showDialog(
       context: context,
       builder: (context) => ParticleDrawingModal(
         accent: _presetColors[_colorIndex == 0 ? 1 : _colorIndex] ?? Colors.cyan,
          onSave: (points) {
            setState(() {
              _customParticlePath = points;
              _particleShape = 7;
            });
            _saveParticleSettings();
            Navigator.pop(context); // Close dialog
            Navigator.pop(context); // Close setting sheet
            _showParticleSettings(_presetColors[_colorIndex == 0 ? 1 : _colorIndex] ?? Colors.cyan); // Reopen settings to update UI
          },
       ),
     );
  }

  IconData _getEqIcon(int mode) {
    switch(mode) {
      case 0: return Icons.waves_rounded;
      case 1: return Icons.grid_3x3_rounded; // Cyber
      case 2: return Icons.blur_circular_rounded; // Orbit
      case 3: return Icons.filter_drama_rounded; // Aurora
      case 4: return Icons.hexagon_outlined; // Hex
      case 5: return Icons.brightness_7_rounded; // Eclipse
      case 6: return Icons.cyclone_rounded; // Vortex
      case 7: return Icons.cable_rounded; // DNA
      case 8: return Icons.show_chart_rounded; // Oscilloscope
      case 9: return Icons.qr_code_2_rounded; // Matrix
      case 10: return Icons.flare_rounded; // Solar
      case 11: return Icons.auto_awesome_rounded; // Stardust
      case 12: return Icons.wifi_tethering_rounded; // Ripple
      case 13: return Icons.remove_rounded; // Minimal
      case 14: return Icons.not_interested_rounded; // OFF
      default: return Icons.graphic_eq_rounded;
    }
  }

  String _getEqName(int mode) {
    const names = [
      "PULSE", "CYBER", "PLANETARY", "NORTHERN",
      "HIVE", "BLACK HOLE", "NEBULA", "HELIX", "WAVEFORM",
      "DIGITAL RAIN", "SUNBURST", "SPARKLE", "SHOCKWAVE", "ZEN", "OFF"
    ];
    return (mode >= 0 && mode < names.length) ? names[mode] : "UNKNOWN";
  }

  Widget _buildInteractiveStage(Color accent) {
    return GestureDetector(
      onPanUpdate: (d) {
        _tiltY += d.delta.dx / 100;
        _tiltX -= d.delta.dy / 100;
        _tiltX = _tiltX.clamp(-0.4, 0.4);
        _tiltY = _tiltY.clamp(-0.4, 0.4);
        _tiltNotifier.value = Offset(_tiltX, _tiltY);
      },
      onPanEnd: (_) {
        _tiltX = 0;
        _tiltY = 0;
        _tiltNotifier.value = Offset.zero;
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_floatController, _breathingController!]),
        builder: (context, child) {
          double float = 12 * math.sin(_floatController.value * 2 * math.pi);
          return ValueListenableBuilder<Offset>(
            valueListenable: _tiltNotifier,
            builder: (context, tilt, _) {
              return ValueListenableBuilder<Map<String, double>?>(
                valueListenable: _spectrumNotifier,
                builder: (context, spectrum, child) {
                  double bass = spectrum?['low'] ?? 0.0;
                  double scale = ((_eqMode == 1 || _eqMode == 2) && bass > 0.15) ? 1.0 + (bass * 0.05) : 1.0;
                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(tilt.dy) // Note: dy is tiltX in original logic
                      ..rotateY(tilt.dx) // Note: dx is tiltY in original logic
                      ..translate(0.0, float)
                      ..scale(scale),
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (_frameShape == 2)
                          RepaintBoundary(
                            child: RotatingOrbitalGlow(
                              accent: accent,
                              isPlaying: _isPlaying,
                              size: 240,
                              orbitRadius: 110,
                            ),
                          )
                        else
                          Container(
                            width: _frameShape == 1 ? 230 : 180,
                            height: _frameShape == 1 ? 130 : 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.6),
                                  blurRadius: 80,
                                  spreadRadius: -10,
                                )
                              ],
                            ),
                          ),
                        if (_isPlaying && _frameShape != 2)
                          Positioned(
                            bottom: -18,
                            child: Container(
                              width: _frameShape == 1 ? 140 : 100,
                              height: 24,
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withOpacity(0.8),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  )
                                ],
                              ),
                            ),
                          ),
                        RotationTransition(
                          turns: _frameShape == 2 ? _vinylController! : const AlwaysStoppedAnimation(0),
                          child: SizedBox(
                            width: _frameShape == 1 ? 230 : (_frameShape == 2 ? 240 : 180),
                            height: _frameShape == 1 ? 130 : (_frameShape == 2 ? 240 : 180),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    shape: _frameShape == 2 ? BoxShape.circle : BoxShape.rectangle,
                                    borderRadius: _frameShape == 2 ? null : BorderRadius.circular(24),
                                  ),
                                  child: _buildGlassAlbum(accent),
                                ),
                                if (_eqMode != 14)
                                  FrameEqualizerOverlay(
                                    color: accent,
                                    mode: _eqMode,
                                    spectrumNotifier: _spectrumNotifier,
                                    isRound: _frameShape == 2,
                                    isPlaying: _isPlaying,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGlassAlbum(Color accent) {
    bool isRound = _frameShape == 2;
    return Container(decoration: BoxDecoration(shape: isRound ? BoxShape.circle : BoxShape.rectangle, borderRadius: isRound ? null : BorderRadius.circular(24), boxShadow: [BoxShadow(color: accent.withOpacity(0.3), blurRadius: 100, spreadRadius: -20), BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 30)]), child: Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: isRound ? BorderRadius.circular(300) : BorderRadius.circular(24), child: _metadata?['art_url']?.isNotEmpty == true ? CachedNetworkImage(
        imageUrl: _metadata!['art_url'], 
        fit: BoxFit.cover,
        memCacheHeight: 600,
        memCacheWidth: 600,
      ) : Center(child: Icon(Icons.music_note_rounded, size: 64, color: Colors.white.withOpacity(0.1)))),
      Container(decoration: BoxDecoration(shape: isRound ? BoxShape.circle : BoxShape.rectangle, borderRadius: isRound ? null : BorderRadius.circular(24), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.15), Colors.transparent, Colors.black.withOpacity(0.2)]))),
    ]));
  }

  Widget _buildInfoCluster(Color accent) {
    final statusColor = _isPlaying ? Colors.greenAccent : Colors.white24;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.15), width: 1), boxShadow: [BoxShadow(color: accent.withOpacity(0.2), blurRadius: 40, offset: const Offset(0, -10))]), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        ScrollableText(text: (_metadata?['title'] ?? AppLocalizations.of(context)!.noSignal).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.2), padding: const EdgeInsets.symmetric(horizontal: 8)),
        const SizedBox(height: 2),
        Text(_getHexTitle(_metadata?['title'] ?? AppLocalizations.of(context)!.noSignal), textAlign: TextAlign.center, style: TextStyle(color: accent.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      const SizedBox(height: 8),
      Transform.translate(
        offset: const Offset(3, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: statusColor.withOpacity(0.2), width: 0.5)), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 3, height: 3, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(_isPlaying ? AppLocalizations.of(context)!.live : AppLocalizations.of(context)!.paused, style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ])),
          const SizedBox(width: 8),
          Container(width: 1, height: 10, color: Colors.white12),
          const SizedBox(width: 0),
          Flexible(child: ScrollableText(text: (_metadata?['artist'] ?? AppLocalizations.of(context)!.dataStreaming).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 2), padding: const EdgeInsets.symmetric(horizontal: 8))),
        ]),
      ),
    ]);
  }

  Widget _buildControlBtn(IconData icon, double size, Color color, VoidCallback onPressed) => IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: Icon(icon, size: size, color: color), onPressed: onPressed);
  String _getHexTitle(String title) { try { return utf8.encode(title.length > 12 ? title.substring(0, 12) : title).map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase(); } catch (_) { return "NULL_PTR"; } }
  Widget _buildSpinner() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.white24, strokeWidth: 1), SizedBox(height: 16), Text(AppLocalizations.of(context)!.synchronizingPaths, style: TextStyle(color: Colors.white12, letterSpacing: 3, fontSize: 10))]));
  Widget _buildSearchingState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.radar_rounded, color: Colors.white10, size: 64), SizedBox(height: 24), Text(AppLocalizations.of(context)!.locatingMediaSignal, style: TextStyle(color: Colors.white24, letterSpacing: 3, fontWeight: FontWeight.bold, fontSize: 11))]));
  Widget _buildEmptyState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.waves_rounded, color: Colors.white.withOpacity(0.05), size: 100), SizedBox(height: 24), Text(AppLocalizations.of(context)!.noActiveSessions, style: TextStyle(color: Colors.white24, letterSpacing: 4, fontWeight: FontWeight.w900, fontSize: 12)), SizedBox(height: 12), Text(AppLocalizations.of(context)!.pleaseStartPlayer, style: TextStyle(color: Colors.white10, letterSpacing: 1, fontSize: 10))]));
}

