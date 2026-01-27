import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PointerScreen extends StatefulWidget {
  final Socket? socket;
  const PointerScreen({super.key, required this.socket});

  @override
  State<PointerScreen> createState() => _PointerScreenState();
}

class _PointerScreenState extends State<PointerScreen> with TickerProviderStateMixin {
  int _currentMode = 2; // Start with Laser Dot
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
  
  // Double tap detection
  DateTime _lastTapTime = DateTime.now();

  late AnimationController _particleController;
  
  // Sensor subscription for proper cleanup
  dynamic _sensorSubscription;

  OverlayEntry? _currentOverlay;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))..repeat();
    
    _loadSettings();
    _setupSensors();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sensitivity = prefs.getDouble('pointer_sensitivity') ?? 1.0;
    });
  }

  Future<void> _updateSensitivity(double val) async {
    setState(() => _sensitivity = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pointer_sensitivity', val);
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _particleController.dispose();
    super.dispose();
  }

  void _setupSensors() {
    debugPrint('🎯 Setting up gyroscope sensor...');
    // Use GYROSCOPE for velocity-based control (relative movement)
    // Using a manual duration to avoid SensorInterval versioning issues
    _sensorSubscription = gyroscopeEventStream(samplingPeriod: const Duration(milliseconds: 5)).listen((GyroscopeEvent event) {
      if (!_pointerActive) return;

      // SENSITIVITY: Higher = Faster cursor movement
      const double sensitivity = 0.04;
      
      // DEADZONE: Ignore tiny drifts
      const double deadzone = 0.03;
      
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
      if (now.difference(_lastSendTime) >= const Duration(milliseconds: 14)) {
        _lastSendTime = now;
        _sendPointerData();
      }
    });
  }

  void _handleButtonTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds < 400) {
      _changeMode((_currentMode + 1) % 5);
      HapticFeedback.vibrate();
    }
    _lastTapTime = now;
  }

  void _calibrateCenter() {
    // Set current orientation as "center" by storing current raw values as offsets
    _offsetX = _lastRawX;
    _offsetY = _lastRawZ;
    // Also reset filtered position to center
    _filteredX = 0.5;
    _filteredY = 0.5;
    // HapticFeedback.heavyImpact(); // Maybe too annoying if automatic
    
    // _showTopNotification('Pointer Calibrated - Center Set'); // Silent auto-calibration
  }

  void _showTopNotification(String message) {
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
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: -5)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.black, size: 14),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
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
    Future.delayed(const Duration(seconds: 2), () {
      if (_currentOverlay != null) {
        _currentOverlay?.remove();
        _currentOverlay = null;
      }
    });
  }

  void _changeMode(int newMode) {
    if (_currentMode == newMode) return;
    HapticFeedback.selectionClick();
    setState(() => _currentMode = newMode);
    _sendPointerData();
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
        }
      };
      try {
        widget.socket!.write('${jsonEncode(data)}\n');
        // Debug: uncomment to see sends
        // debugPrint('📤 Sent: pitch=${_pitch.toStringAsFixed(2)}, roll=${_roll.toStringAsFixed(2)}');
      } catch (e) {
        debugPrint('❌ Send error: $e');
      }
    } else {
      debugPrint('⚠️ Socket is null - not connected!');
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
        widget.socket!.write('${jsonEncode(data)}\n');
      } catch (_) {}
    }
  }

  void _setPointerActive(bool active) {
    if (active) {
      // Recenter on start for consistent "Pick up and point" feel
      _filteredX = 0.5;
      _filteredY = 0.5;
    }
    setState(() => _pointerActive = active);
    _sendPointerData();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A)],
        ),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, _) => CustomPaint(
              painter: _ParticlePainter(_particleController.value, _pointerActive),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 60),
                const Text('PRESENTATION TOOLS', style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w900)),
                
                // Visualization in middle
                Expanded(
                  child: Center(
                    child: _buildPointerVisual(),
                  ),
                ),
                
                const SizedBox(height: 10),
                _buildSensitivitySlider(),
                const SizedBox(height: 20),
                _buildModeShortcuts(),
                const SizedBox(height: 30),

                // NEW LAYOUT: Control Panel Fixed at Bottom
                _buildFixedControlPanel(),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointerVisual() {
    // Morphing parameters based on mode
    double width, height;
    BoxDecoration decoration;
    final color = Colors.white;
    const duration = Duration(milliseconds: 300);
    const curve = Curves.fastOutSlowIn;

    // HIGH CONTRAST STYLE (Simulated Invert)
    // All modes now have a strong black border/shadow to be visible on white backgrounds
    final highContrastShadow = [
      BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 4, spreadRadius: 1), // Outline feel
      BoxShadow(color: color.withOpacity(0.6), blurRadius: 15, spreadRadius: 2) // Glow
    ];

    switch (_currentMode) {
      case 0: // Horizontal
        width = 200; height = 8;
        decoration = BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: highContrastShadow,
        );
        break;
      case 1: // Vertical
        width = 8; height = 200;
        decoration = BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: highContrastShadow,
        );
        break;
      case 3: // Ring (Highlight)
        width = 90; height = 90;
        decoration = BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(45),
          border: Border.all(color: color, width: 4),
          boxShadow: [
             BoxShadow(color: Colors.black, blurRadius: 2, spreadRadius: 0, offset: const Offset(1,1)),
             BoxShadow(color: color.withOpacity(0.3), blurRadius: 20)
          ],
        );
        break;
      case 4: // Comet / Tail
        width = 30; height = 30;
        decoration = BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(15), 
            bottomLeft: Radius.circular(15), 
            topRight: Radius.circular(5), 
            bottomRight: Radius.circular(5)
          ), 
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: highContrastShadow,
        );
        break;
      case 2: // Dot (Default)
      default:
        width = 40; height = 40;
        decoration = BoxDecoration(
          color: color,
          // ALWAYS use rectangle shape with radius to avoid lerp errors with BoxShape.circle
          shape: BoxShape.rectangle, 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: highContrastShadow,
        );
        break;
    }

    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: width,
      height: height,
      decoration: decoration,
      // Add a subtle opacity change if not active to show preview
      child: Opacity(
        opacity: _pointerActive ? 1.0 : 0.3,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildSensitivitySlider() {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("SENSITIVITY", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              Text("${(_sensitivity * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.1),
            ),
            child: Slider(
              value: _sensitivity,
              min: 0.2,
              max: 2.0,
              onChanged: _updateSensitivity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeShortcuts() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeIcon(0, Icons.maximize),
          _modeIcon(1, Icons.more_vert),
          _modeIcon(2, Icons.radio_button_checked),
          _modeIcon(3, Icons.panorama_fish_eye),
          _modeIcon(4, Icons.flash_on), // Tail Icon
        ],
      ),
    );
  }

  Widget _modeIcon(int mode, IconData icon) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => _changeMode(mode),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(15)),
        child: Icon(icon, color: isSelected ? Colors.black : Colors.white38, size: 20),
      ),
    );
  }

  Widget _buildModePreview() {
    switch (_currentMode) {
      case 0: return _previewText('HORIZONTAL');
      case 1: return _previewText('VERTICAL');
      case 2: return _previewText('LASER DOT');
      case 3: return _previewText('PRECISION RING');
      case 4: return _previewText('LASER TAIL');
      default: return const SizedBox();
    }
  }

  Widget _previewText(String text) {
     return Text(text, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold));
  }

  // --- NEW FIXED CONTROL PANEL ---
  Widget _buildFixedControlPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 120, // Tall area for controls
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Prev Slide (Tall Button)
            Expanded(
              child: _SlideButton(
                icon: Icons.keyboard_arrow_left_rounded,
                onTap: () => _sendSlideControl('prev'),
              ),
            ),
            
            const SizedBox(width: 15),
            
            // Pointer Button (Circle in Middle)
            Center(
              child: _PointerTouchButton(
                isCircle: true,
                width: 100, height: 100,
                icon: Icons.gps_fixed,
                onActiveChanged: (val) {
                  if (val) _calibrateCenter(); // Auto-calibrate on press
                  _setPointerActive(val);
                },
                onTap: _handleButtonTap,
              ),
            ),
            
            const SizedBox(width: 15),
            
            // Next Slide (Tall Button)
            Expanded(
              child: _SlideButton(
                icon: Icons.keyboard_arrow_right_rounded,
                onTap: () => _sendSlideControl('next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET CLASSES (MOVED TO TOP LEVEL) ---

class _PointerTouchButton extends StatefulWidget {
  final IconData icon;
  final Function(bool) onActiveChanged;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isCircle;
  final double width;
  final double height;

  const _PointerTouchButton({
    required this.icon,
    required this.onActiveChanged,
    this.onTap,
    this.onLongPress,
    this.isCircle = false,
    this.width = 70,
    this.height = 70,
  });

  @override
  State<_PointerTouchButton> createState() => _PointerTouchButtonState();
}

class _PointerTouchButtonState extends State<_PointerTouchButton> {
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
          // Small delay before setting inactive to allow 'onTap' (mode change) 
          // to happen without the overlay disappearing instantly
          Future.delayed(const Duration(milliseconds: 50), () {
            if (!_isPressed) widget.onActiveChanged(false);
          });
        },
        onPointerCancel: (_) {
          setState(() => _isPressed = false);
          widget.onActiveChanged(false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : BorderRadius.circular(20),
            gradient: _isPressed 
                ? (widget.isCircle 
                    ? RadialGradient(colors: [Colors.white, Colors.white.withOpacity(0.7)])
                    : LinearGradient(colors: [Colors.white, Colors.white70], begin: Alignment.topLeft, end: Alignment.bottomRight))
                : null,
            color: _isPressed ? null : Colors.white10,
            border: Border.all(
              color: _isPressed ? Colors.white : Colors.white24,
              width: _isPressed ? 2.5 : 1.5,
            ),
            boxShadow: _isPressed ? [
              BoxShadow(color: Colors.white.withOpacity(0.4), blurRadius: 25, spreadRadius: 4)
            ] : [],
          ),
          child: Icon(
            widget.icon,
            color: _isPressed ? Colors.black : (widget.isCircle ? Colors.white70 : Colors.white38),
            size: widget.isCircle ? 28 : 32,
          ),
        ),
      ),
    );
  }
}

class _SlideButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  
  const _SlideButton({required this.icon, required this.onTap});

  @override
  State<_SlideButton> createState() => _SlideButtonState();
}

class _SlideButtonState extends State<_SlideButton> {
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
        decoration: BoxDecoration(
          color: _isPressed ? Colors.white24 : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isPressed ? Colors.white : Colors.white10),
        ),
        child: Icon(widget.icon, size: 40, color: Colors.white),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double animValue;
  final bool isActive;
  
  _ParticlePainter(this.animValue, this.isActive);
  
  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive) return;
    final paint = Paint()..color = Colors.white.withOpacity(0.1);
    final random = math.Random(42);
    for (int i = 0; i < 20; i++) {
        final x = random.nextDouble() * size.width;
        final y = (random.nextDouble() * size.height + animValue * 100) % size.height;
        canvas.drawCircle(Offset(x, y), 1.5, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
