import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../utils/protocol.dart';
import 'package:wayland_connect_android/l10n/app_localizations.dart';
import '../widgets/pointer_painter.dart';
import '../widgets/pointer_widgets.dart';
import '../widgets/pointer_shape_painter.dart';

class PointerScreen extends StatefulWidget {
  final Socket? socket;
  final bool isActiveTab;
  final Stream<String>? volumeStream;
  final bool zoomEnabled;

  const PointerScreen({super.key, required this.socket, this.isActiveTab = false, this.volumeStream, this.zoomEnabled = false});

  @override
  State<PointerScreen> createState() => _PointerScreenState();
}

class _PointerScreenState extends State<PointerScreen> with TickerProviderStateMixin {
  int _currentMode = 0; // Start with Dot (New mapping)
  bool _pointerActive = false;
  
  double _pitch = 0.5;
  double _roll = 0.5;
  
  // Filters for smooth movement (exponential smoothing)
  double _filteredX = 0.5;
  double _filteredY = 0.5;
  
  // Velocity filters for jitter reduction
  double _filteredXVel = 0.0;
  double _filteredYVel = 0.0;
  
  // Raw accelerometer values for calibration
  double _lastRawX = 0.0;
  double _lastRawZ = 0.0;
  
  // Calibration offsets (set when user calibrates)
  double _offsetX = 0;
  double _offsetY = 0;
  
  DateTime _lastSendTime = DateTime.now();
  static const _minSendInterval = Duration(milliseconds: 10);
  
  // User adjustable sensitivity
  double _sensitivity = 1.0; 
  
  // User adjustable pointer size
  double _pointerSize = 1.0;
  
  // Double tap detection
  DateTime _lastTapTime = DateTime.now();

  late AnimationController _particleController;
  late AnimationController _morphController; // Added for morph animation
  late AnimationController _lifeController; // For particle lifecycle
  
  // Customization state
  Color _pointerColor = Colors.white; 
  String? _customImagePath; // Path to custom dot image
  int _particleType = 0; // 0: Default, 1: Star, 2: Fire, 3: Electric

  double _zoomScale = 1.0; 
  double _stretchFactor = 1.0; 
  double _pulseIntensity = 0.0; // 0.0 to 1.0
  double _pulseSpeed = 2.0; // 1.0 to 5.0
  int _frequency = 60; // 30, 60, or 120
  
  // Sensor subscription for proper cleanup
  dynamic _sensorSubscription;
  StreamSubscription? _volumeSubscription;

  OverlayEntry? _currentOverlay;

  // Particle System
  final List<PointerParticle> _particles = [];
  final ValueNotifier<int> _particleUpdateNotifier = ValueNotifier(0);
  final math.Random _random = math.Random();
  Size _screenSize = Size.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
    if (_particles.isEmpty && _screenSize != Size.zero) {
      _initParticles();
    }
  }

  void _initParticles() {
    _particles.clear();
    for (int i = 0; i < 50; i++) {
        _particles.add(PointerParticle(
          x: _random.nextDouble() * _screenSize.width,
          y: _random.nextDouble() * _screenSize.height,
          vx: (_random.nextDouble() - 0.5) * 0.5,
          vy: (_random.nextDouble() - 0.5) * 0.5,
          size: _random.nextDouble() * 3 + 1,
          life: _random.nextDouble(),
          hueShift: (_random.nextDouble() - 0.5) * 40.0, // +/- 20 degrees variation
        ));
    }
  }

  void _updateParticles() {
    // "Partikel idle saat gak di hold" -> Float randomly
    // "Saat di hold partikel idle itu menuju poni hp" -> Suck to top center
    // "Intro & Death animation" -> handled by velocity changes on state switch
    
    // Top Center (Notch)
    final targetX = _screenSize.width / 2;
    final targetY = 0.0; 

    for (var p in _particles) {
       if (_pointerActive) {
          // SUCTION MODE (Active)
          double dx = targetX - p.x;
          double dy = targetY - p.y;
          double dist = math.sqrt(dx*dx + dy*dy);
          
          if (dist < 20) {
             // Reset to bottom if absorbed
             p.x = _random.nextDouble() * _screenSize.width;
             p.y = _screenSize.height + 10;
             p.vx = 0; p.vy = 0;
          } else {
             // Accelerate towards notch (Balanced Speed)
             p.vx += (dx / dist) * 0.7; // Reduced from 1.6 to match user preference
             p.vy += (dy / dist) * 0.7;
             // Fluid damping
             p.vx *= 0.94;
             p.vy *= 0.94;
          }
       } else {
          // IDLE MODE (Float) - Organic random movement
          p.vx += (_random.nextDouble() - 0.5) * 0.08;
          p.vy += (_random.nextDouble() - 0.5) * 0.08;
          
          // Friction to prevent indefinite acceleration
          p.vx *= 0.98;
          p.vy *= 0.98;
          
          // Screen wrap
          if (p.x < 0) p.x = _screenSize.width;
          if (p.x > _screenSize.width) p.x = 0;
          if (p.y < 0) p.y = _screenSize.height;
          if (p.y > _screenSize.height) p.y = 0;
       }
       
       p.x += p.vx;
       p.y += p.vy;
       
       // Twinkle life
       p.life += 0.02;
       if (p.life > 1.0) p.life = 0;
    }
    _particleUpdateNotifier.value++; // Increment to trigger repaint via ValueListenableBuilder
  }

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
        ..addListener(_updateParticles)
        ..repeat();
    
    _morphController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    // Life Controller for Particle Beam (Smooth Birth/Death)
    _lifeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    
    _loadSettings();
    _setupSensors();
    
    // Listen to global stream
    _volumeSubscription = widget.volumeStream?.listen((event) {
       if (!mounted) return;
       if (!widget.isActiveTab || !_pointerActive) return;

       if (event == 'volume_up') {
         _updatePointerSize((_pointerSize + 0.1).clamp(0.01, 3.0));
       } else if (event == 'volume_down') {
         _updatePointerSize((_pointerSize - 0.1).clamp(0.01, 3.0));
       } else if (event == 'power_down') {
          // Power Button Down -> Left Click Down
          _sendClick('left', isDown: true);
       } else if (event == 'power_up') {
          // Power Button Up -> Left Click Up
          _sendClick('left', isDown: false);
       }
    });

  }

  Widget _buildFrequencySelector({VoidCallback? onUpdate}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("UPDATE RATE", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
            Text("$_frequency Hz", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () { _updateFrequency(30); if (onUpdate != null) onUpdate(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _frequency == 30 ? Colors.white : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _frequency == 30 ? Colors.white : Colors.white10),
                  ),
                  alignment: Alignment.center,
                  child: Text("30Hz", style: TextStyle(color: _frequency == 30 ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () { _updateFrequency(60); if (onUpdate != null) onUpdate(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _frequency == 60 ? Colors.white : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _frequency == 60 ? Colors.white : Colors.white10),
                  ),
                  alignment: Alignment.center,
                  child: Text("60Hz", style: TextStyle(color: _frequency == 60 ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () { _updateFrequency(120); if (onUpdate != null) onUpdate(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _frequency == 120 ? Colors.white : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _frequency == 120 ? Colors.white : Colors.white10),
                  ),
                  alignment: Alignment.center,
                  child: Text("120Hz", style: TextStyle(color: _frequency == 120 ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text("Higher = smoother, more battery use", style: TextStyle(color: Colors.white24, fontSize: 9)),
      ],
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _sensitivity = prefs.getDouble('pointer_sensitivity') ?? 1.0;
      _pointerSize = prefs.getDouble('pointer_size') ?? 1.0;
      _currentMode = prefs.getInt('pointer_mode') ?? 0;
      _pointerColor = Color(prefs.getInt('pointer_color') ?? Colors.white.value);
      _customImagePath = prefs.getString('pointer_custom_image');
      _particleType = prefs.getInt('pointer_particle_type') ?? 0;
      _zoomScale = prefs.getDouble('pointer_zoom_scale') ?? 1.0;
      _pulseIntensity = prefs.getDouble('pointer_pulse_intensity') ?? 0.0;
      _pulseSpeed = prefs.getDouble('pointer_pulse_speed') ?? 2.0;

      // Ensure default 60Hz on first install
      if (!prefs.containsKey('pointer_frequency')) {
        _frequency = 60;
        prefs.setInt('pointer_frequency', 60);
      } else {
        _frequency = prefs.getInt('pointer_frequency') ?? 60;
      }
    });
    // Send initial data once settings are loaded
    _sendPointerData();
  }

  Future<void> _updateSensitivity(double val, {VoidCallback? onUpdate}) async {
    setState(() => _sensitivity = val);
    if (onUpdate != null) onUpdate();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pointer_sensitivity', val);
    _sendPointerData(); // Ensure state is fresh
  }

  Future<void> _updatePointerSize(double val, {VoidCallback? onUpdate}) async {
    setState(() => _pointerSize = val);
    if (onUpdate != null) onUpdate();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pointer_size', val);
    _sendPointerData(); 
  }

  Future<void> _updateFrequency(int freq) async {
    setState(() => _frequency = freq);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pointer_frequency', freq);
    _setupSensors();
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _volumeSubscription?.cancel();
    _particleController.dispose();
    _morphController.dispose();
    _lifeController.dispose();
    _particleUpdateNotifier.dispose();
    super.dispose();
  }

  void _setupSensors() {
    debugPrint('🎯 Setting up gyroscope sensor at $_frequency Hz...');
    _sensorSubscription?.cancel();
    
    // Convert Hz to sampling period
    int ms = (1000 / _frequency).round();
    
    _sensorSubscription = gyroscopeEventStream(samplingPeriod: Duration(milliseconds: ms)).listen((GyroscopeEvent event) {
      if (!_pointerActive) return;

      // SENSITIVITY: Higher = Faster cursor movement
      const double sensitivity = 0.04;
      
      // DEADZONE: Ignore tiny sensor noise, but allow micro-movements
      const double deadzone = 0.002; // Reduced from 0.03 to capture slow movements
      
      // GYROSCOPE MAPPING:
      // event.x = pitch (tilting forward/backward)
      // event.y = roll (tilting left/right)
      // 
      // For intuitive control:
      // - Tilt phone FORWARD (up) → event.x positive → pointer UP (Y decrease)
      // - Tilt phone BACKWARD (down) → event.x negative → pointer DOWN (Y increase)
      // - Tilt phone LEFT → event.y positive → pointer LEFT (X decrease)
      // - Tilt phone RIGHT → event.y negative → pointer RIGHT (X increase)
      
      // AIR MOUSE LOGIC:
      // Follow the "top" of the phone as it points.
      // event.x = Pitch (Tilting top up/down)
      // event.z = Yaw (Rotating top left/right)
      
      double pitchVel = event.x; // Nodding
      double yawVel = event.z;   // Shaking/Pointing left-right
      
      // 1. FILTERING
      _filteredXVel = _filteredXVel * 0.5 + yawVel * 0.5;
      _filteredYVel = _filteredYVel * 0.5 + pitchVel * 0.5;

      // 2. MAPPING TO SCREEN
      double moveX = _filteredXVel;
      double moveY = _filteredYVel;
      
      if (moveX.abs() < deadzone) moveX = 0;
      if (moveY.abs() < deadzone) moveY = 0;
      
      if (moveX == 0 && moveY == 0) return;

      // Sensitivity Tuning for Air Mouse
      // Reduced base multiplier from 2.0 to 1.4 for better control
      double finalSensitivity = 0.035 * _sensitivity;
      
      double dx = -moveX * finalSensitivity * 1.4; 
      double dy = -moveY * finalSensitivity * 1.4;
      
      // 3. INTEGRATION
      _filteredX = (_filteredX + dx).clamp(0.0, 1.0);
      _filteredY = (_filteredY + dy).clamp(0.0, 1.0);
      
      _roll = _filteredX;
      _pitch = _filteredY;
      
      // 4. SMOOTH NETWORK SYNC
      final now = DateTime.now();
      // Reduced interval from 14ms to 7ms for lower latency (towards 144Hz input rate)
      if (now.difference(_lastSendTime) >= const Duration(milliseconds: 7)) {
        _lastSendTime = now;
        _sendPointerData();
      }
    });
  }

  void _handleButtonTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds < 400) {
      // DOUBLE TAP DETECTED - Cycle through all 7 modes
      _changeMode((_currentMode + 1) % 7);
      
      // Trigger "Mixing" Animation
      _morphController.forward(from: 0.0).then((_) => _morphController.reverse());
      
      HapticFeedback.vibrate();
    }
    _lastTapTime = now;
  }



  void _showTopNotification(String message, {bool isError = false}) {
    _currentOverlay?.remove();
    _currentOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: isError ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isError ? Colors.redAccent.withOpacity(0.5) : Colors.white24, 
                    width: 1.5
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: -5)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isError ? Colors.redAccent : Colors.white, 
                        shape: BoxShape.circle
                      ),
                      child: Icon(
                        isError ? Icons.error_outline_rounded : Icons.check, 
                        color: isError ? Colors.white : Colors.black, 
                        size: 14
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        message, 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_currentOverlay!);
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentOverlay != null) {
        _currentOverlay?.remove();
        _currentOverlay = null;
      }
    });
  }

  void _changeMode(int newMode) async {
    if (_currentMode == newMode) return;
    HapticFeedback.selectionClick();
    setState(() => _currentMode = newMode);
    _sendPointerData();
    
    // Save mode choice
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pointer_mode', newMode);
  }

  void _sendKey(String key) {
    if (widget.socket != null) {
       try {
         final event = {"type": "keypress", "data": {"key": key}};
         widget.socket!.add(ProtocolHandler.encodePacket(event));
       } catch (_) {}
    }
  }

  void _sendPointerData() {
    if (widget.socket != null) {
      final data = {
        'type': 'pointer_data',
        'data': {
          'active': _pointerActive,
          'mode': _currentMode,
          'pitch': _pitch,
          'roll': _roll,
          'size': _pointerSize, // Send RAW size, let PC handle pulse
          'color': '#${_pointerColor.value.toRadixString(16).padLeft(8, '0')}',
          'has_image': _customImagePath != null,
          'particle_type': _particleType,
          'zoom_scale': _zoomScale,
          'stretch_factor': _stretchFactor,
          'pulse_speed': _pulseSpeed,
          'pulse_intensity': _pulseIntensity,
        }
      };
      try {
        widget.socket!.add(ProtocolHandler.encodePacket(data));
      } catch (e) {
        debugPrint('❌ Send error: $e');
      }
    } else {
      debugPrint('⚠️ Socket is null - not connected!');
    }
  }

  void _sendClick(String button, {bool isDown = true}) {
    if (widget.socket != null) {
       try {
         final data = {
           "type": "mouse_click",
           "data": {
             "button": button,
             "state": isDown ? "down" : "up" 
           }
         };
         widget.socket!.add(ProtocolHandler.encodePacket(data));
       } catch (_) {}
    }
  }

  void _sendSlideControl(String action) {
    if (widget.socket != null) {
      HapticFeedback.mediumImpact();
      final data = {
        'type': 'presentation_control',
        'data': {'action': action}
      };
      try {
        widget.socket!.add(ProtocolHandler.encodePacket(data));
      } catch (_) {}
    }
  }

  void _setPointerActive(bool active) {
    if (active) {
      // Recenter on start for consistent "Pick up and point" feel
      _filteredX = 0.5;
      _filteredY = 0.5;
      _roll = 0.5;
      _pitch = 0.5;
      HapticFeedback.mediumImpact(); // Add feedback
      _lifeController.forward(); // Animate In
    
    } else {
      // DEATH ANIMATION: Explode particles outwards
      for (var p in _particles) {
         p.vx = (_random.nextDouble() - 0.5) * 15.0; // Explosion velocity
         p.vy = (_random.nextDouble() - 0.5) * 15.0;
      }
      
      _lifeController.reverse(); // Animate Out
    }
    setState(() => _pointerActive = active);
    _sendPointerData();
  }



  void _calibrateCenter() {
     // Called when becoming active - establishes new 'zero'
     setState(() {
      _filteredX = 0.5;
      _filteredY = 0.5;
     });
  }


  @override
  Widget build(BuildContext context) {
      if (widget.socket == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_off, size: 48, color: Colors.white24),
                SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.disconnected, style: const TextStyle(color: Colors.white24, letterSpacing: 2))
              ],
            ),
          );
      }
      return Container(
      decoration: const BoxDecoration(
        color: Colors.black, // Pure Dark Background
      ),
      child: Stack(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _particleUpdateNotifier,
            builder: (context, _, __) => RepaintBoundary(
              child: CustomPaint(
                painter: PointerPainter(
                  animValue: _particleController.value, 
                  morphValue: _morphController.value,
                  lifeValue: _lifeController.value, 
                  isActive: _pointerActive,
                  mode: _currentMode,
                  pointerScale: _pointerSize,
                  color: _pointerColor,
                  particleType: _particleType,
                  particles: _particles,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Header with Settings Button (Centered Title)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                       Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                        child: Text(AppLocalizations.of(context)!.presentationController.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: _showSettingsPanel, 
                          icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                          tooltip: "Settings",
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),

                // Unified Visualization Container
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       SizedBox(
                         height: 250, 
                         width: 300,
                         child: Center(child: _buildPointerVisual()),
                       ),
                       const SizedBox(height: 20),
                       _buildModeName(),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Mode Selector (Restored)
                _buildModeSelector(),
                const SizedBox(height: 10),
                
                // Fixed at bottom (Always visible)
                _buildFixedControlPanel(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setPanelState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Container(
                  width: 50, height: 5,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                 ),
                 const SizedBox(height: 30),
                 Text(AppLocalizations.of(context)!.pointerSettings, style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 3, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 30),
                 
                  _buildCustomizationControls(onUpdate: () => setPanelState(() {})),
                  const SizedBox(height: 30),
                  _buildSensitivitySlider(onUpdate: () => setPanelState(() {})),
                  const SizedBox(height: 20),
                   _buildSizeSlider(onUpdate: () => setPanelState(() {})),
                   const SizedBox(height: 20),
                   _buildPulseControls(onUpdate: () => setPanelState(() {})),
                   const SizedBox(height: 20),
                   _buildFrequencySelector(onUpdate: () => setPanelState(() {})),
                   const SizedBox(height: 30),
                  // Moved zoom indicator here for visibility without overlap
                  if (widget.zoomEnabled) 
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded, color: Colors.blueAccent, size: 14),
                          SizedBox(width: 8),
                          Text("ZOOM ENGINE ACTIVE", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ],
                      ),
                    ),
               ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomizationControls({VoidCallback? onUpdate}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CustomControlBtn(
              icon: Icons.palette_rounded, 
              label: AppLocalizations.of(context)!.color,
              onTap: () { Navigator.pop(context); _pickColor(); },
            ),
            if (_currentMode == 6) ...[
               CustomControlBtn(
                 icon: Icons.image_outlined, 
                 label: "IMAGE", 
                 onTap: () async { 
                   await _pickImage(); 
                   if (onUpdate != null) onUpdate();
                 }
               ),
               CustomControlBtn(
                 icon: Icons.auto_awesome_mosaic_rounded, 
                 label: "SHAPE", 
                 onTap: () async { 
                    _pickParticle(); 
                    // Note: _pickParticle opens its own sheet, so we don't need update hook here
                 }
               ),
            ],
            // Magnifier is available for specific modes
            if (_currentMode == 1 || _currentMode == 4 || _currentMode == 5 || _currentMode == 6)
              Opacity(
                opacity: widget.zoomEnabled ? 1.0 : 0.4,
                child: CustomControlBtn(
                  icon: Icons.loupe_rounded,
                  label: AppLocalizations.of(context)!.magnifier,
                  onTap: widget.zoomEnabled ? () { Navigator.pop(context); _pickZoom(); } : () {
                    HapticFeedback.vibrate();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Enable Zoom in Desktop App settings first"))
                    );
                  },
                ),
              ),
          ],
        ),
        if (_customImagePath != null && _currentMode == 6)
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image_rounded, color: Colors.blueAccent, size: 14),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.customTextureActive, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      setState(() => _customImagePath = null);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('pointer_custom_image');
                      
                      // Sync removal to PC
                      if (widget.socket != null) {
                         widget.socket!.add(ProtocolHandler.encodePacket({"type": "pointer_image", "data": ""}));
                      }

                      _sendPointerData();
                      if (onUpdate != null) onUpdate();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 14),
                    ),
                  )
                ],
              ),
            ),
          )
      ],
    );
  }

  void _pickColor() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
            border: Border.all(color: Colors.white10, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60, height: 6,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 30),
              const Text("AESTHETIC HUE", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4)),
              const SizedBox(height: 10),
              const Text("Select a signature color for your pointer", style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 40),
              
              StatefulBuilder(
                builder: (context, setPanelState) => Column(
                  children: [
                    SizedBox(
                      height: 380,
                      child: HueRingPicker(
                        pickerColor: _pointerColor,
                        onColorChanged: (color) {
                          setState(() => _pointerColor = color);
                          setPanelState(() {});
                          _sendPointerData(); // LIVE SYNC TO PC
                        },
                        enableAlpha: false,
                        displayThumbColor: true,
                      ),
                    ),
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt('pointer_color', _pointerColor.value);
                        _sendPointerData();
                        HapticFeedback.heavyImpact();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_pointerColor.withOpacity(0.8), _pointerColor],
                            begin: Alignment.topLeft, end: Alignment.bottomRight
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(color: _pointerColor.withOpacity(0.4), blurRadius: 25, spreadRadius: 2),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text("INITIALIZE COLOR", style: TextStyle(
                          color: _pointerColor.computeLuminance() > 0.5 ? Colors.black : Colors.white, 
                          fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 3)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Pick RAW image to check resolution manually
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    // Check resolution
    final bytes = await File(pickedFile.path).readAsBytes();
    final decodedImage = await decodeImageFromList(bytes);

    if (decodedImage.width > 256 || decodedImage.height > 256) {
       HapticFeedback.heavyImpact();
       _showTopNotification("FAILED: Image ${decodedImage.width}x${decodedImage.height} exceeds 256x256 limit!", isError: true);
       return;
    }

    setState(() => _customImagePath = pickedFile.path);
    
    // Save it locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pointer_custom_image', pickedFile.path);
    
    // SYNC TO PC: Send the image data
    if (widget.socket != null) {
      try {
        final b64 = base64Encode(bytes);
        final msg = {
          "type": "pointer_image",
          "data": b64
        };
        widget.socket!.write('${jsonEncode(msg)}\n');
      } catch (e) {
        debugPrint("Failed to sync image to PC: $e");
      }
    }

    _sendPointerData();
    HapticFeedback.mediumImpact();
    _showTopNotification("Texture Applied (${decodedImage.width}x${decodedImage.height})");
  }

  void _pickParticle() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
            border: Border.all(color: Colors.white10, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60, height: 6,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 30),
              const Text("GEOMETRIC IDENTITY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 3, fontSize: 18)),
              const SizedBox(height: 10),
              const Text("Choose the core manifestation of the pointer", style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ParticleIconButton(icon: Icons.lens_rounded, label: "CIRCLE", active: _particleType == 0, activeColor: _pointerColor, onTap: () => _setParticle(0)),
                  ParticleIconButton(icon: Icons.star_rounded, label: "CELESTIAL", active: _particleType == 1, activeColor: _pointerColor, onTap: () => _setParticle(1)),
                  ParticleIconButton(icon: Icons.local_fire_department_rounded, label: "PLASMA", active: _particleType == 2, activeColor: _pointerColor, onTap: () => _setParticle(2)),
                  ParticleIconButton(icon: Icons.electric_bolt_rounded, label: "KINETIC", active: _particleType == 3, activeColor: _pointerColor, onTap: () => _setParticle(3)),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _setParticle(int type) async {
    setState(() => _particleType = type);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pointer_particle_type', type);
    Navigator.pop(context);
    _sendPointerData();
    HapticFeedback.mediumImpact();
  }

  void _pickZoom() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
            border: Border.all(color: Colors.white10, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60, height: 6,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 30),
              const Text("DIMENSIONAL SCALE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 3, fontSize: 18)),
              const SizedBox(height: 40),
              StatefulBuilder(
                builder: (context, setModalState) => Column(
                  children: [
                     SliderTheme(
                       data: SliderThemeData(
                          activeTrackColor: _pointerColor,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                       ),
                       child: Slider(
                         value: _zoomScale,
                         min: 1.0, max: 4.0,
                         onChanged: (val) {
                           setState(() => _zoomScale = val);
                           setModalState(() {});
                           _sendPointerData();
                         },
                       ),
                     ),
                     const SizedBox(height: 10),
                     Text("${_zoomScale.toStringAsFixed(1)}x ${AppLocalizations.of(context)!.magnification}", 
                        style: TextStyle(color: _pointerColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    ).then((_) async {
       final prefs = await SharedPreferences.getInstance();
       await prefs.setDouble('pointer_zoom_scale', _zoomScale);
    });
  }

  Widget _buildModeButton(int id, IconData icon, String label) {
    bool isSelected = _currentMode == id;
    return GestureDetector(
      onTap: () => _changeMode(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 10)] : null,
          border: Border.all(color: isSelected ? Colors.white : Colors.transparent),
        ),
        child: Row(
          children: [
             Icon(icon, color: isSelected ? Colors.black : Colors.white70, size: 20),
             if (isSelected) ...[
                const SizedBox(width: 8),
                Text(label.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))
             ]
          ],
        ),
      ),
    );
  }

  Widget _buildSensitivitySlider({VoidCallback? onUpdate}) {
    return Column(
      children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(AppLocalizations.of(context)!.sensitivity.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
             Text("${(_sensitivity * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
           ],
         ),
         SliderTheme(
           data: SliderThemeData(
             activeTrackColor: Colors.white,
             inactiveTrackColor: Colors.white12,
             thumbColor: Colors.white,
             overlayColor: Colors.white.withOpacity(0.1),
             trackHeight: 2,
             thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
             overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
           ),
           child: Slider(
             value: _sensitivity,
             min: 0.2, max: 2.0,
             onChanged: (val) => _updateSensitivity(val, onUpdate: onUpdate),
           ),
         ),
      ],
    );
  }

  Widget _buildSizeSlider({VoidCallback? onUpdate}) {
     return Column(
      children: [
         _buildStretchSlider(), // Add here
         if (_currentMode == 4 || _currentMode == 5) const SizedBox(height: 10),
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(AppLocalizations.of(context)!.pointerSize.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
             Text("${(_pointerSize * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
           ],
         ),
         SliderTheme(
           data: SliderThemeData(
             activeTrackColor: Colors.white,
             inactiveTrackColor: Colors.white12,
             thumbColor: Colors.white,
             overlayColor: Colors.white.withOpacity(0.1),
             trackHeight: 2,
             thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
             overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
           ),
           child: Slider(
             value: _pointerSize,
             min: 0.01, max: 3.0,
             onChanged: (val) => _updatePointerSize(val, onUpdate: onUpdate),
           ),
         ),
      ],
    );

  }

  Widget _buildStretchSlider() {
     // Only for Hollow Modes (4 & 5)
     if (_currentMode != 4 && _currentMode != 5) return const SizedBox.shrink();
     
     return Column(
       children: [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_currentMode == 4 ? AppLocalizations.of(context)!.horiStretch.toUpperCase() : AppLocalizations.of(context)!.vertStretch.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text("${(_stretchFactor * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.1),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _stretchFactor,
              min: 0.5, max: 2.0,
              onChanged: (val) {
                 setState(() => _stretchFactor = val);
                 _sendPointerData();
              },
            ),
          ),
       ],
    );
  }

  Widget _buildPulseControls({VoidCallback? onUpdate}) {
     return Column(
       children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(AppLocalizations.of(context)!.pulseIntensity.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
             Text("${(_pulseIntensity * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
           ],
         ),
         SliderTheme(
           data: SliderThemeData(
             activeTrackColor: Colors.blueAccent,
             inactiveTrackColor: Colors.white12,
             thumbColor: Colors.white,
             trackHeight: 2,
             thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
           ),
           child: Slider(
             value: _pulseIntensity,
             min: 0.0, max: 1.0,
             onChanged: (val) async {
               setState(() => _pulseIntensity = val);
               if (onUpdate != null) onUpdate();
               final prefs = await SharedPreferences.getInstance();
               await prefs.setDouble('pointer_pulse_intensity', val);
               _sendPointerData();
             },
           ),
         ),
         if (_pulseIntensity > 0) ...[
           const SizedBox(height: 10),
           Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               Text(AppLocalizations.of(context)!.pulseSpeed.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
               Text("${_pulseSpeed.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
             ],
           ),
           SliderTheme(
             data: SliderThemeData(
               activeTrackColor: Colors.blueAccent.withOpacity(0.6),
               inactiveTrackColor: Colors.white12,
               thumbColor: Colors.white,
               trackHeight: 2,
               thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
             ),
             child: Slider(
               value: _pulseSpeed,
               min: 1.0, max: 5.0,
               onChanged: (val) async {
                 setState(() => _pulseSpeed = val);
                 if (onUpdate != null) onUpdate();
                 final prefs = await SharedPreferences.getInstance();
                 await prefs.setDouble('pointer_pulse_speed', val);
                 _sendPointerData();
               },
             ),
           ),
         ],
       ],
     );
  }

  Widget _buildPointerVisual() {
    // Trigger Hot Reload Check
    // Morphing parameters based on mode
    double width = 40;
    double height = 40;
    BoxDecoration decoration;
    final color = _pointerColor;
    const duration = Duration(milliseconds: 50);
    const curve = Curves.fastOutSlowIn;
    // Scale down large shapes for preview so they fit in the fixed container
    const double previewScale = 0.6;

    // VOLUMETRIC HIGH-END GLOW
    final solidShadow = [
      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, spreadRadius: 1),
      BoxShadow(color: color.withOpacity(0.5), blurRadius: 15, spreadRadius: 2),
      BoxShadow(color: color.withOpacity(0.2), blurRadius: 40, spreadRadius: 5),
    ];

    final hollowShadow = [
      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 2, spreadRadius: 0.5),
      BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, spreadRadius: 1),
      BoxShadow(color: color.withOpacity(0.1), blurRadius: 30, spreadRadius: 4),
    ];

    switch (_currentMode) {
      case 0: // Dot - Matches Linux 40px
        width = 40; height = 40;
        decoration = BoxDecoration(
          color: color,
          shape: BoxShape.rectangle, 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: solidShadow,
        );
        break;
      case 1: // Precision Ring
        width = 90; height = 90;
        decoration = BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(45),
          border: Border.all(color: color, width: 4), 
          boxShadow: hollowShadow,
        );
        break;

      case 2: // Vertical Beam (Solid) - Matches Linux 8x450
        width = 8; height = 450 * previewScale;
        decoration = BoxDecoration(
          color: color, 
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(4), // radius 4
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: solidShadow,
        );
        break;
      case 3: // Horizontal Beam (Solid) - Matches Linux 450x8
        width = 450 * previewScale; height = 8;
        decoration = BoxDecoration(
          color: color, 
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(4), // radius 4
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: solidShadow,
        );
        break;
      case 4: // Hollow Horiz
        height = 20; 
        width = 400 * previewScale * _stretchFactor; // Apply Stretch & Preview Scale
        decoration = BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 4),
          boxShadow: hollowShadow,
        );
        break;
      case 5: // Hollow Vert
        width = 20;
        height = 400 * previewScale * _stretchFactor; // Apply Stretch & Preview Scale
        decoration = BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 4),
          boxShadow: hollowShadow,
        );
        break;
      case 6: // Comet Tail - Matches Linux design (Ring + Core Dot)
        width = 35 * _zoomScale; // Applied Zoom to Comet
        height = 35 * _zoomScale;
        decoration = BoxDecoration(
          color: _customImagePath == null ? Colors.transparent : Colors.black26,
          image: _customImagePath != null ? DecorationImage(
            image: FileImage(File(_customImagePath!)),
            fit: BoxFit.contain,
          ) : null,
          shape: BoxShape.circle, 
          border: Border.all(
            color: _customImagePath == null ? color : Colors.white24, 
            width: 2.0 * _zoomScale
          ), 
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, spreadRadius: 1),
          ],
        );
        break;
      default:
        width = 40; height = 40;
        decoration = BoxDecoration(
          color: color, 
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2),
        );
        break;
    }

    // Apply Zoom to other hollow modes correctly
    // REMOVED: Zoom should not affect pointer size, only magnifier level
    // if (_currentMode == 1 || _currentMode == 4 || _currentMode == 5) {
    //    width *= _zoomScale;
    //    height *= _zoomScale;
    // }

    // Pulsing logic for Preview
    double pulse = math.sin(_particleController.value * math.pi * 2 * _pulseSpeed);
    double animatedPointerSize = _pointerSize + (pulse * 0.3 * _pulseIntensity * _pointerSize).clamp(-(_pointerSize * 0.5), 10.0);
    double scaledWidth = width * animatedPointerSize;
    double scaledHeight = height * animatedPointerSize;

    // Final Dimension Clamping for APP PREVIEW ONLY
    void applyClamping() {
       if (_currentMode == 2 || _currentMode == 5) {
         height = 110; 
       } else if (_currentMode == 3 || _currentMode == 4) {
         width = 110;
       } else {
         double maxDim = math.max(width, height);
         if (maxDim > 110) {
           double fitScale = 110 / maxDim;
           width *= fitScale;
           height *= fitScale;
         }
       }
    }
    applyClamping();

    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, _) {
        // Pulsing logic for Preview
        double pulse = math.sin(_particleController.value * math.pi * 2 * _pulseSpeed);
        double animSize = 1.0 + (pulse * 0.3 * _pulseIntensity).clamp(-0.5, 2.0);
        double sWidth = width * animSize;
        double sHeight = height * animSize;

        return TweenAnimationBuilder<PointerVisualState>(
          duration: duration,
          curve: curve,
          tween: PointerVisualStateTween(
            begin: PointerVisualState(
               width: sWidth, height: sHeight, 
                radius: (_currentMode == 1 ? 45.0 : (_currentMode == 6 ? 17.5 * _zoomScale : (decoration.borderRadius as BorderRadius).topLeft.x)) * animSize,
                strokeWidth: (_currentMode == 0 || _currentMode == 2 || _currentMode == 3 ? 0.0 : (_currentMode == 6 ? 2.5 * _zoomScale : 4.0)) * animSize,
                color: color, 
                fillAlpha: _currentMode == 0 || _currentMode == 2 || _currentMode == 3 ? 1.0 : 0.0
             ),
             end: PointerVisualState(
                width: sWidth, height: sHeight, 
                radius: (_currentMode == 1 ? 45.0 : (_currentMode == 6 ? 17.5 * _zoomScale : (decoration.borderRadius as BorderRadius).topLeft.x)) * animSize,
               strokeWidth: (_currentMode == 0 || _currentMode == 2 || _currentMode == 3 ? 0.0 : (_currentMode == 6 ? 2.5 * _zoomScale : 4.0)) * animSize,
               color: color, 
               fillAlpha: _currentMode == 0 || _currentMode == 2 || _currentMode == 3 ? 1.0 : 0.0
            ),
          ),
          builder: (context, val, _) {
            return CustomPaint(
              size: Size(val.width, val.height),
              painter: PointerShapePainter(
                color: val.color,
                radius: val.radius,
                strokeWidth: val.strokeWidth,
                fillAlpha: val.fillAlpha,
                mode: _currentMode,
                particleType: _particleType,
                zoomScale: _zoomScale,
                customImagePath: _customImagePath,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSymmetricIcon(int mode, IconData icon, double width) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => _changeMode(mode),
      child: Container(
        width: width,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent, 
            borderRadius: BorderRadius.circular(15)
          ),
          child: Icon(icon, color: isSelected ? Colors.black : Colors.white38, size: 20),
        ),
      ),
    );
  }


  Widget _buildModeSelector() {
    return SizedBox(
      height: 60,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            _buildModeIcon(0, Icons.circle),
            _buildModeIcon(1, Icons.radio_button_unchecked),
            _buildModeIcon(2, Icons.vertical_align_center),
            _buildModeIcon(3, Icons.horizontal_distribute),
            _buildModeIcon(4, Icons.check_box_outline_blank), // Hollow H
            _buildModeIcon(5, Icons.check_box_outline_blank_rounded), // Hollow V (rotated visual ideally)
            _buildModeIcon(6, Icons.auto_awesome),
          ],
        ),
      ),
    );
  }

  Widget _buildModeIcon(int mode, IconData icon) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => _changeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? Colors.white : Colors.white10),
        ),
        child: Icon(icon, color: isSelected ? Colors.black : Colors.white38, size: 24),
      ),
    );
  }

  Widget _buildModeName() {
    String name = "";
    switch (_currentMode) {
      case 0: name = 'LASER DOT'; break;
      case 1: name = 'PRECISION RING'; break;
      case 2: name = 'VERTICAL BEAM'; break;
      case 3: name = 'HORIZONTAL BEAM'; break;
      case 4: name = 'HOLLOW HORIZ'; break;
      case 5: name = 'HOLLOW VERT'; break;
      case 6: name = 'COMET TAIL'; break;
    }
    return Text(name, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold));
  }

  Widget _buildFixedControlPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, spreadRadius: -5),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // PREV BUTTON
            AestheticButton(
               icon: Icons.arrow_back_ios_new_rounded, 
                onTap: () => _sendSlideControl('prev'),
            ),

            // MAIN POINTER BUTTON (Center)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 20, spreadRadius: 5),
                ]
              ),
              child: PointerTouchButton(
                isCircle: true,
                width: 80, height: 80,
                icon: Icons.gps_fixed, 
                onActiveChanged: (val) {
                  if (val) _calibrateCenter();
                  _setPointerActive(val);
                },
                onTap: _handleButtonTap,
              ),
            ),

            // NEXT BUTTON
            AestheticButton(
               icon: Icons.arrow_forward_ios_rounded, 
               onTap: () => _sendSlideControl('next'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET CLASSES (FIXED & FINISHED) ---

