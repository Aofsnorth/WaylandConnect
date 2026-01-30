import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import '../utils/protocol.dart';
import 'package:wayland_connect_android/l10n/app_localizations.dart';

class ScreenShareScreen extends StatefulWidget {
  final Socket? socket;
  final Stream<Uint8List>? socketStream;
  const ScreenShareScreen({super.key, required this.socket, this.socketStream});

  @override
  State<ScreenShareScreen> createState() => _ScreenShareScreenState();
}

class _ScreenShareScreenState extends State<ScreenShareScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Uint8List? _lastFrame;
  List<dynamic> _apps = [];
  List<dynamic> _filteredApps = [];
  bool _isLoadingApps = false;
  StreamSubscription? _socketSub;
  bool _showControls = true;
  int _frameCount = 0;
  int _currentFps = 0;
  Timer? _fpsTimer;
  DateTime? _lastFrameTime;
  double _latency = 0; // Latency in ms
  bool _isMirroring = false; // Manual toggle state
  bool _isMenuOpen = false;
  bool _isAwaitingApproval = false;
  String? _rejectionReason;
  List<dynamic> _monitors = [];
  int _selectedMonitorIndex = 0;

  // Stream Settings
  int _streamWidth = 854;
  int _streamHeight = 480;
  int _streamFps = 30; // Smoother default
  
  // Floating UI Position
  double _fabTop = 100;
  double _fabRight = 20;
  
  late AnimationController _magnetController;
  late Animation<double> _fabRightAnimation;
  
  // App Launcher state
  final TextEditingController _searchController = TextEditingController();
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _rotateController;
  
  // Keyboard management
  final FocusNode _keyboardFocusNode = FocusNode();
  final TextEditingController _keyboardController = TextEditingController();
  bool _isKeyboardFocused = false;

  @override
  void initState() {
    super.initState();
    _setupListener();
    _fetchApps();
    _fetchMonitors();
    // _startMirroring(); // Disabled auto-start as per user request
    _searchController.addListener(_filterApps);
    _keyboardFocusNode.addListener(() {
      if (mounted) setState(() => _isKeyboardFocused = _keyboardFocusNode.hasFocus);
    });
    
    _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
    )..forward();

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true); // 0.0 -> 1.0 -> 0.0

    _magnetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentFps = _frameCount;
          _frameCount = 0;
        });
      }
    });
  }

  @override
  void didUpdateWidget(ScreenShareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.socketStream != oldWidget.socketStream || widget.socket != oldWidget.socket) {
      _socketSub?.cancel();
      _setupListener();
      if (_isMirroring) _startMirroring(); // Only reconnect if active
      _fetchApps();
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _searchController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _rotateController.dispose();
    _magnetController.dispose();
    _fpsTimer?.cancel();
    _keyboardController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  final ProtocolHandler _protocolHandler = ProtocolHandler(); // Add this instance
  
  void _setupListener() {
    if (widget.socketStream != null) {
      _socketSub = widget.socketStream!.listen((data) {
        if (!mounted) return;
        try {
           final packets = _protocolHandler.process(data);
           for (final packet in packets) {
              if (packet is! Map) continue;
              final Map<dynamic, dynamic> json = packet;
              // Binary Packet handling (Spectrum/Frame)
              if (json.containsKey('t')) {
                 final t = json['t'];
                 final d = json['d'];
                 
                 if (t == 'f' && d != null) { // Binary Frame
                    // Robust extraction of frame bytes
                    final frameData = (d is Map) ? (d['b'] ?? d['data'] ?? d[0]) : d;
                    
                    if (frameData != null) {
                       final Uint8List bytes;
                       if (frameData is Uint8List) {
                         bytes = frameData;
                       } else if (frameData is List<int>) {
                         bytes = Uint8List.fromList(frameData);
                       } else if (frameData is List) {
                         // Handle List<dynamic> or other list types
                         bytes = Uint8List.fromList(frameData.cast<int>());
                       } else {
                         debugPrint("⚠️ Unknown frame data type: ${frameData.runtimeType}");
                         continue;
                       }

                       if (bytes.isNotEmpty) {
                         setState(() {
                           _frameCount++;
                           if (_lastFrameTime != null) {
                             _latency = DateTime.now().difference(_lastFrameTime!).inMilliseconds.toDouble();
                           }
                           _lastFrameTime = DateTime.now();
                           _lastFrame = bytes;
                         });
                       }
                    }
                 } else if (t == 's' && d != null) { // Spectrum
                    // Handle spectrum if needed here, but usually handled in MediaScreen
                 }
                 continue; // Handled binary packet
              }

              // Standard Control Packets (with 'type')
              final type = json['type']?.toString();
              if (type == 'apps_list') {
                setState(() {
                  _apps = json['data']?['apps'] ?? [];
                  _filteredApps = _apps;
                  _isLoadingApps = false;
                });
              } else if (json['type'] == 'mirror_status') {
                final allowed = json['data']?['allowed'] ?? true;
                final message = json['data']?['message'] ?? "REJECTED";
                setState(() {
                   _isAwaitingApproval = false;
                   if (!allowed) {
                     _isMirroring = false;
                     _rejectionReason = message;
                   } else {
                     _isMirroring = true; 
                     _rejectionReason = null;
                   }
                });
                  setState(() {
                    _monitors = json['data']?['monitors'] ?? [];
                  });
                } else if (json['type'] == 'stop_mirroring') {
                  setState(() {
                    _isMirroring = false;
                    _lastFrame = null;
                    _currentFps = 0;
                  });
                }
           }
        } catch (e) {
          // debugPrint("Frame decode error: $e");
        }
      },
      onDone: () {
        if (mounted) setState(() { _isMirroring = false; _lastFrame = null; });
      },
      onError: (e) {
        if (mounted) setState(() { _isMirroring = false; _lastFrame = null; });
      },
      );
    }
  }

  void _startMirroring() {
    setState(() {
      _isAwaitingApproval = true;
      _rejectionReason = null;
    });
    if (widget.socket != null) {
       final event = {
        'type': 'start_mirroring',
        'data': {
          'width': _streamWidth,
          'height': _streamHeight,
          'fps': _streamFps,
          'monitor': _selectedMonitorIndex
        }
      };
      widget.socket!.add(ProtocolHandler.encodePacket(event));
    }
  }

  void _stopMirroring() {
    setState(() {
      _isMirroring = false;
      _lastFrame = null; // Clear frame to show standby
      _currentFps = 0;
    });
    if (widget.socket != null) {
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'stop_mirroring'}));
    }
  }

  void _toggleKeyboard() {
    if (_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.unfocus();
    } else {
      _keyboardFocusNode.requestFocus();
    }
    setState(() {});
  }

  void _sendText(String text) {
    if (widget.socket != null && text.isNotEmpty) {
      for (var i = 0; i < text.length; i++) {
        widget.socket!.add(ProtocolHandler.encodePacket({
          'type': 'keypress',
          'data': {'key': text[i]}
        }));
      }
    }
  }

  void _fetchApps() {
    if (widget.socket != null) {
      setState(() => _isLoadingApps = true);
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'get_apps'}));
    }
  }

  void _fetchMonitors() {
    if (widget.socket != null) {
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'get_monitors'}));
    }
  }

  void _launchApp(String cmd) {
    if (widget.socket != null) {
      HapticFeedback.heavyImpact();
      widget.socket!.add(ProtocolHandler.encodePacket({
        'type': 'launch_app',
        'data': {'command': cmd}
      }));
      
      // Auto collapse sheet on launch
      _sheetController.animateTo(0.08, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 12),
              Text("${AppLocalizations.of(context)!.launching} ${cmd.split(' ').first.toUpperCase()}", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
            ],
          ),
          backgroundColor: Colors.black.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5)),
          margin: const EdgeInsets.only(bottom: 110, left: 30, right: 30),
          duration: const Duration(seconds: 2),
        )
      );
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _apps
          .where((app) => 
              app['name'].toString().toLowerCase().contains(query) || 
              app['exec'].toString().toLowerCase().contains(query))
          .toList();
    });
  }

  void _handleInput(String type, Offset pos, BuildContext context) {
    if (widget.socket == null) return;
    
    final renderBox = context.findRenderObject() as RenderBox;
    final screenSize = renderBox.size;
    
    const double targetAspect = 16 / 9;
    final double screenAspect = screenSize.width / screenSize.height;
    
    double imgW, imgH, offsetX, offsetY;
    if (screenAspect > targetAspect) {
      imgH = screenSize.height; imgW = imgH * targetAspect;
      offsetX = (screenSize.width - imgW) / 2; offsetY = 0;
    } else {
      imgW = screenSize.width; imgH = imgW / targetAspect;
      offsetX = 0; offsetY = (screenSize.height - imgH) / 2;
    }
    
    double normX = (pos.dx - offsetX) / imgW;
    double normY = (pos.dy - offsetY) / imgH;
    normX = normX.clamp(0.0, 1.0);
    normY = normY.clamp(0.0, 1.0);

    if (type == 'move') {
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'move_absolute', 'data': {'x': normX, 'y': normY}}));
    } else if (type == 'left_click') {
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'click', 'data': {'button': 'left'}}));
    } else if (type == 'right_click') {
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'click', 'data': {'button': 'right'}}));
    }
  }
  
  void _sendSetMonitor(int index) {
    if (widget.socket != null) {
      HapticFeedback.mediumImpact();
      setState(() => _selectedMonitorIndex = index);
      widget.socket!.add(ProtocolHandler.encodePacket({
        'type': 'set_pointer_monitor',
        'data': {'monitor': index}
      }));
      
      // If we are mirroring, restart with the new monitor?
      // For now, pointersync is enough, but we should probably restart stream if auto-select is possible.
      if (_isMirroring) _startMirroring();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${AppLocalizations.of(context)!.switchingToMonitor} $index", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2)),
          backgroundColor: Colors.black.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 110, left: 30, right: 30),
          duration: const Duration(seconds: 1),
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF050505),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 1. AMBIENT BACKGROUND
              Positioned.fill(child: Container(color: Colors.black)),

              // 2. MIRROR CONTENT
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                  child: (_isMirroring && _lastFrame != null)
                      ? _buildActiveMirror()
                      : _buildStandbyState(),
                ),
              ),

              // 4. CONTROL OVERLAYS
              if (_showControls) ...[
                _buildTopStatus(),
                _buildBottomInstructions(),
                _buildActionPanel(constraints), // FAB on top of instructions
              ],

              // 5. APPS LAUNCHER SHEET (MUST BE LAST to cover status and instructions when expanded)
              _buildAppsSheet(),
            ],
          );
        }
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_sheetController.isAttached && _sheetController.size > 0.1) {
       _sheetController.animateTo(0.08, duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    }
  }


  Widget _buildActiveMirror() {
    return Builder(
      builder: (context) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        
        return Stack(
          children: [
          // 1. AMBIENT GESTURE LAYER (Tap background to toggle UI)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),

          // 2. MIRROR & INTERACTION LAYER
          Center(
            child: ListenableBuilder(
              listenable: _sheetController,
              builder: (context, _) {
                // Ignore mirror interaction when apps sheet is pulled up
                final isAppsSheetOpen = _sheetController.isAttached && _sheetController.size > 0.15;
                return IgnorePointer(
                  ignoring: isAppsSheetOpen,
                  child: GestureDetector(
                    onPanStart: (details) => _handleInput('move', details.localPosition, context),
                    onPanUpdate: (details) => _handleInput('move', details.localPosition, context),
                    onTapDown: (details) {
                      HapticFeedback.selectionClick();
                      _handleInput('move', details.localPosition, context);
                    },
                    onTapUp: (details) => _handleInput('left_click', details.localPosition, context),
                    onLongPressStart: (details) {
                      HapticFeedback.heavyImpact();
                      _handleInput('right_click', details.localPosition, context);
                    },
                    onTap: () {
                      if (_showControls) _toggleControls();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, spreadRadius: 10),
                        ],
                      ),
                      child: RepaintBoundary(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(isLandscape ? 0 : 4),
                                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    _lastFrame!,
                                    gaplessPlayback: true,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ),
                );
              },
            ),
          ),

            // 3. OVERLAY CONTROLS (Settings, Keyboard, Disconnect)
            if (_showControls) ...[
              // Action Buttons (Top Right)
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                right: 20,
                child: Row(
                  children: [
                    _buildActionIcon(Icons.keyboard_outlined, _toggleKeyboard,
                      color: _keyboardFocusNode.hasFocus ? Colors.blueAccent : Colors.white),
                    if (!isLandscape) ...[
                      const SizedBox(width: 12),
                      _buildActionIcon(Icons.settings_outlined, _showStreamSettings),
                    ],
                  ],
                ),
              ),

              // Bottom Disconnect (Portrait only)
                Positioned(
                  bottom: 150, // Raised from 120
                  left: 0, right: 0,
                  child: Center(
                    child: _buildStopButton(),
                  ),
                ),
            ],

            // 4. HIDDEN KEYBOARD INPUT
            Positioned(
              top: -100,
              child: SizedBox(
                width: 1, height: 1,
                child: TextField(
                  focusNode: _keyboardFocusNode,
                  controller: _keyboardController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (val) {
                    if (val.isNotEmpty) {
                      _sendText(val);
                      _keyboardController.clear();
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStopButton() {
    return GestureDetector(
      onTap: _stopMirroring,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: -5),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            const Text("STOP MIRRORING", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2)),
          ],
        ),
      ),
    );
  }

  Widget _buildStandbyState() {
    return Center(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.heavyImpact();
          _startMirroring();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMirroring ? Colors.white.withOpacity(0.02) : (_isAwaitingApproval ? Colors.amber.withOpacity(0.15) : Colors.greenAccent.withOpacity(0.1)), 
                  border: Border.all(color: _isMirroring ? Colors.white.withOpacity(0.05) : (_isAwaitingApproval ? Colors.amberAccent : Colors.greenAccent.withOpacity(0.5))),
                  boxShadow: [
                    if (!_isMirroring) BoxShadow(color: (_isAwaitingApproval ? Colors.amberAccent : Colors.greenAccent).withOpacity(0.2), blurRadius: 40, spreadRadius: 5)
                  ]
                ),
                child: _isAwaitingApproval 
                  ? RotationTransition(
                      turns: Tween(begin: -0.15, end: 0.15).animate(CurvedAnimation(parent: _rotateController, curve: Curves.easeInOut)), // +/- 54 degrees (~90 degree sweep)
                      child: const Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.amberAccent),
                    )
                  : Icon(
                   _isMirroring ? Icons.cast_connected_rounded : Icons.power_settings_new_rounded, 
                   size: 64, 
                   color: _rejectionReason != null ? Colors.redAccent : (_isMirroring ? Colors.blueAccent : Colors.greenAccent)
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _rejectionReason != null ? "MIRROR REJECTED" : (_isAwaitingApproval ? "WAITING FOR PC..." : (_isMirroring ? "WAITING FOR SIGNAL..." : "START MIRRORING")), 
              style: TextStyle(
                color: _rejectionReason != null ? Colors.redAccent : (_isAwaitingApproval ? Colors.amberAccent : (_isMirroring ? Colors.blueAccent : Colors.greenAccent)), 
                fontSize: 13, 
                fontWeight: FontWeight.w900, 
                letterSpacing: 4
              )
            ),
            const SizedBox(height: 8),
            Text(
              _rejectionReason ?? (_isAwaitingApproval ? "PLEASE ACCEPT ON YOUR PC" : (_isMirroring ? "WAITING FOR VIDEO FEED" : "TAP TO CONNECT TO HOST")), 
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2)
            ),
            if (_isMirroring || _isAwaitingApproval) ...[
               const SizedBox(height: 40),
               if (_isAwaitingApproval)
                 Padding(
                   padding: const EdgeInsets.only(bottom: 40), // More space from bottom
                   child: GestureDetector(
                    onTap: () {
                       setState(() {
                          _isAwaitingApproval = false;
                          _isMirroring = false;
                          _lastFrame = null;
                       });
                       widget.socket?.add(ProtocolHandler.encodePacket({'type': 'stop_mirror'}));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 8),
                          Text("CANCEL REQUEST", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                 ),
               SizedBox(width: 80, height: 2, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: _isAwaitingApproval ? Colors.amberAccent.withOpacity(0.3) : Colors.white24)),
            ] else ...[
               const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopStatus() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20, right: 20,
      child: FadeTransition(
        opacity: _fadeController,
        child: Row(
          children: [
            _buildGlassCard(
              child: Row(
                children: [
                  _lastFrame != null 
                    ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle))
                    : const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white24)),
                  const SizedBox(width: 12),
                  Container(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppLocalizations.of(context)!.systemMirror.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                        Text(_isMirroring ? AppLocalizations.of(context)!.liveFeedActive.toUpperCase() : AppLocalizations.of(context)!.standbyMode.toUpperCase(), style: TextStyle(color: _isMirroring ? Colors.greenAccent : Colors.white38, fontSize: 7, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _buildGlassCard(
              child: Row(
                children: [
                  _buildStatusValue("${_currentFps}FPS", AppLocalizations.of(context)!.stream.toUpperCase()),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 20, color: Colors.white10),
                  const SizedBox(width: 16),
                  _buildStatusValue("${_latency.toInt()}MS", AppLocalizations.of(context)!.ping.toUpperCase()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }


  Widget _buildActionPanel(BoxConstraints constraints) {
    final double padding = 20.0;
    const double bottomBarHeight = 130.0; // Increased for better safe area
    const double fabSize = 54.0;
    final double topSafeArea = MediaQuery.of(context).padding.top;
    
    return Positioned(
      top: _fabTop, 
      right: _fabRight,
      child: GestureDetector(
        onPanStart: (_) {
          _magnetController.stop();
        },
        onPanUpdate: (details) {
          setState(() {
            _fabTop += details.delta.dy;
            _fabRight -= details.delta.dx;
            
            // Vertical Clamping
            _fabTop = _fabTop.clamp(
              topSafeArea + padding, 
              constraints.maxHeight - bottomBarHeight - fabSize - padding
            );
            
            // Horizontal Clamping
            _fabRight = _fabRight.clamp(
              padding, 
              constraints.maxWidth - fabSize - padding
            );
          });
        },
        onPanEnd: (details) {
          double leftEdge = constraints.maxWidth - fabSize - padding;
          double rightEdge = padding;
          
          double targetRight = (_fabRight - rightEdge).abs() < (_fabRight - leftEdge).abs() ? rightEdge : leftEdge;
          
          _fabRightAnimation = Tween<double>(begin: _fabRight, end: targetRight).animate(
            CurvedAnimation(parent: _magnetController, curve: Curves.easeOutBack)
          )..addListener(() {
            setState(() {
              _fabRight = _fabRightAnimation.value;
            });
          });
          
          _magnetController.forward(from: 0);
        },
        child: Container(
          color: Colors.transparent, // Hit test for dragging
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: _isMenuOpen || !_showControls ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionIcon(
                      _isMirroring ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, 
                      () {
                        HapticFeedback.mediumImpact();
                        if (_isMirroring) {
                           _stopMirroring();
                        } else {
                           _startMirroring();
                        }
                        setState(() => _isMenuOpen = false);
                      },
                      color: _isMirroring ? Colors.redAccent : Colors.greenAccent
                    ),
                    const SizedBox(height: 16),
                    _buildMonitorSelector(),
                    const SizedBox(height: 16),
                    _buildActionIcon(Icons.apps_rounded, () {
                       _sheetController.animateTo(0.6, duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuart);
                       setState(() => _isMenuOpen = false);
                    }),
                    const SizedBox(height: 16),
                    _buildActionIcon(Icons.settings_input_svideo_rounded, () {
                      _showStreamSettings();
                      setState(() => _isMenuOpen = false);
                    }),
                    const SizedBox(height: 16),
                  ],
                ) : const SizedBox(width: 54), // Maintain width for alignment
              ),
              _buildActionIcon(
                _isMenuOpen ? Icons.close_rounded : Icons.menu_open_rounded, 
                () {
                  HapticFeedback.selectionClick();
                  setState(() => _isMenuOpen = !_isMenuOpen);
                },
                color: Colors.white
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonitorSelector() {
    return _buildActionIcon(Icons.open_with_rounded, () {
      HapticFeedback.selectionClick();
      _showMonitorDialog();
    }, color: Colors.blueAccent);
  }

  void _showMonitorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), 
          side: BorderSide(color: Colors.white10),
        ),
        title: Text(AppLocalizations.of(context)!.selectMonitor.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        content: SizedBox(
          width: double.maxFinite,
          child: _monitors.isEmpty 
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text("NO MONITORS DETECTED", style: TextStyle(color: Colors.white24, fontSize: 10)),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _monitors.length,
                itemBuilder: (context, index) {
                  final m = _monitors[index];
                  final String name = m['name'] ?? "Monitor $index";
                  final int id = m['id'] ?? index;
                  final bool active = id == _selectedMonitorIndex;
                  return ListTile(
                    leading: Icon(Icons.monitor_rounded, color: active ? Colors.blueAccent : Colors.white24),
                    title: Text(name.toUpperCase(), style: TextStyle(color: active ? Colors.blueAccent : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    trailing: active ? const Icon(Icons.check_circle_rounded, color: Colors.blueAccent, size: 20) : null,
                    onTap: () {
                      _sendSetMonitor(id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
        ),
      ),
    );
  }

  PopupMenuItem<int> _buildMonitorMenuItem(int val, String label, {bool active = false}) {
     return PopupMenuItem<int>(
        value: val,
        child: Row(
          children: [
            Icon(Icons.monitor_rounded, color: active ? Colors.blueAccent : Colors.white24, size: 16),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: active ? Colors.blueAccent : Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
            if (active) Icon(Icons.check_circle_rounded, color: Colors.blueAccent, size: 12),
          ],
        ),
     );
  }

  Widget _buildActionIcon(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: _buildActionIconContent(icon, color: color),
    );
  }

  Widget _buildActionIconContent(IconData icon, {Color? color}) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color ?? Colors.white70, size: 22),
          ),
        ),
      );
  }

  Widget _buildStatusValue(String val, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 6, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildBottomInstructions() {
    return Positioned(
      bottom: 220, left: 0, right: 0, // Raised significantly to clear stop button and nav
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mouse_outlined, color: Colors.white24, size: 10),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  AppLocalizations.of(context)!.screenShareInstructions.toUpperCase(), 
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white12, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppsSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.15, // Increased from 0.12 to clear bottom bar
      minChildSize: 0.15,
      maxChildSize: 0.9,
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40, offset: const Offset(0, -10))],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F).withOpacity(0.8),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          width: 40, height: 4,
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(30, 10, 30, 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AppLocalizations.of(context)!.application.toUpperCase(), style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 4, fontSize: 9)),
                                Text(AppLocalizations.of(context)!.launcher.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -1)),
                              ],
                            ),
                            const Spacer(),
                            IconButton(onPressed: _fetchApps, icon: const Icon(Icons.refresh_rounded, color: Colors.white24)),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)!.searchApplications.toUpperCase(),
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2),
                              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white24, size: 18),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isLoadingApps)
                      const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2)))
                    else if (_filteredApps.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.apps_outlined, color: Colors.white10, size: 40),
                              const SizedBox(height: 16),
                              Text(AppLocalizations.of(context)!.noAppsFound.toUpperCase(), style: const TextStyle(color: Colors.white10, fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final app = _filteredApps[index];
                            return _AppTile(
                                name: app['name'], 
                                iconBase64: app['icon_base64'], 
                                onTap: () => _launchApp(app['exec'])
                            );
                          },
                          childCount: _filteredApps.length,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  void _showStreamSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.2, // Pembatas bawah adalah bottom bar (area aman)
          maxChildSize: 0.7,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(AppLocalizations.of(context)!.streamQuality.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 24),
                
                Text(AppLocalizations.of(context)!.resolution.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 12),
                StatefulBuilder(builder: (context, setModalState) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildResOption(854, 480, "480p", setModalState),
                    _buildResOption(1280, 720, "720p", setModalState),
                    _buildResOption(1920, 1080, "1080p", setModalState),
                  ],
                )),
                
                const SizedBox(height: 24),
                Text(AppLocalizations.of(context)!.framerate.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 12),
                StatefulBuilder(builder: (context, setModalState) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildFpsOption(15, setModalState),
                    _buildFpsOption(30, setModalState),
                    _buildFpsOption(60, setModalState),
                  ],
                )),
                const SizedBox(height: 32),
                
                SizedBox(
                   width: double.infinity,
                   child: ElevatedButton(
                      onPressed: () {
                         Navigator.pop(context);
                         HapticFeedback.heavyImpact();
                         if (_isMirroring) _startMirroring(); // Restart stream with new settings
                      },
                      style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.blueAccent,
                         padding: const EdgeInsets.symmetric(vertical: 16),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(AppLocalizations.of(context)!.saveSettings.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
                   ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResOption(int w, int h, String label, StateSetter setModalState) {
    bool isSelected = _streamWidth == w && _streamHeight == h;
    return Expanded(
      child: GestureDetector(
        onTap: () {
           setState(() { _streamWidth = w; _streamHeight = h; });
           setModalState(() {});
        },
        child: Container(
           margin: const EdgeInsets.symmetric(horizontal: 4),
           padding: const EdgeInsets.symmetric(vertical: 12),
           decoration: BoxDecoration(
             color: isSelected ? Colors.white : Colors.white.withOpacity(0.05),
             borderRadius: BorderRadius.circular(12),
             border: Border.all(color: isSelected ? Colors.white : Colors.white10),
           ),
           alignment: Alignment.center,
           child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildFpsOption(int fps, StateSetter setModalState) {
    bool isSelected = _streamFps == fps;
    return Expanded(
      child: GestureDetector(
        onTap: () {
           setState(() => _streamFps = fps);
           setModalState(() {});
        },
        child: Container(
           margin: const EdgeInsets.symmetric(horizontal: 4),
           padding: const EdgeInsets.symmetric(vertical: 12),
           decoration: BoxDecoration(
             color: isSelected ? Colors.white : Colors.white.withOpacity(0.05),
             borderRadius: BorderRadius.circular(12),
             border: Border.all(color: isSelected ? Colors.white : Colors.white10),
           ),
           alignment: Alignment.center,
           child: Text("${fps}FPS", style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _AppTile extends StatefulWidget {
  final String name;
  final String? iconBase64;
  final VoidCallback onTap;
  const _AppTile({required this.name, this.iconBase64, required this.onTap});

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  bool _isPressed = false;
  Uint8List? _cachedIcon;

  @override
  void initState() {
    super.initState();
    if (widget.iconBase64 != null && widget.iconBase64!.isNotEmpty) {
      try {
        _cachedIcon = base64Decode(widget.iconBase64!);
      } catch (e) {
        debugPrint("Error decoding icon for ${widget.name}: $e");
      }
    }
  }

  @override
  void didUpdateWidget(_AppTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconBase64 != widget.iconBase64) {
      if (widget.iconBase64 != null && widget.iconBase64!.isNotEmpty) {
        try {
          _cachedIcon = base64Decode(widget.iconBase64!);
        } catch (e) {
          _cachedIcon = null;
        }
      } else {
        _cachedIcon = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_isPressed ? 0.08 : 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(_isPressed ? 0.2 : 0.05)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48, height: 48,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(14)),
                child: _cachedIcon != null
                  ? Image.memory(_cachedIcon!, fit: BoxFit.contain, gaplessPlayback: true)
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : "?",
                        style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, 
                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MonitorPainter extends CustomPainter {
  final Color color;
  MonitorPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    for (double i = 0; i <= size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i <= size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// _MirrorScanOverlay and _ScanPainter removed to clean up code
