import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import '../utils/protocol.dart';

class AppLauncherScreen extends StatefulWidget {
  final Socket? socket;
  final Stream<Uint8List>? socketStream;
  
  const AppLauncherScreen({super.key, required this.socket, this.socketStream});

  @override
  State<AppLauncherScreen> createState() => _AppLauncherScreenState();
}

class _AppLauncherScreenState extends State<AppLauncherScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _apps = [];
  bool _isLoading = false;
  StreamSubscription? _socketSub;
  TextEditingController _searchController = TextEditingController();
  List<dynamic> _filteredApps = [];
  final ProtocolHandler _protocolHandler = ProtocolHandler();
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _setupListener();
    _fetchApps();
    _searchController.addListener(_filterApps);
    
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _searchController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  void _setupListener() {
    if (widget.socketStream != null) {
      _socketSub = widget.socketStream!.listen((data) {
          if (!mounted) return;
          try {
            final packets = _protocolHandler.process(data);
            for (final packet in packets) {
              if (packet is! Map) continue;
              final json = packet;
              if (json['type'] == 'apps_list') {
                setState(() {
                  _apps = json['data']?['apps'] ?? [];
                  _filteredApps = _apps;
                  _isLoading = false;
                });
              }
            }
          } catch (_) {}
      });
      _socketSub?.onError((e) {
        if (!mounted) return;
        setState(() {
          _apps = [];
          _filteredApps = [];
          _isLoading = false;
        });
      });
      _socketSub?.onDone(() {
        if (!mounted) return;
        setState(() {
          _apps = [];
          _filteredApps = [];
          _isLoading = false;
        });
      });
    }
  }

  void _fetchApps() {
    if (widget.socket != null) {
      setState(() => _isLoading = true);
      widget.socket!.add(ProtocolHandler.encodePacket({'type': 'get_apps'}));
    }
  }

  void _launchApp(String cmd) {
    if (widget.socket != null) {
      HapticFeedback.heavyImpact();
      widget.socket!.add(ProtocolHandler.encodePacket({
        'type': 'launch_app',
        'data': {'command': cmd}
      }));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🚀 LAUNCHING: $cmd", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2)),
          backgroundColor: Colors.black.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5)),
          margin: const EdgeInsets.only(bottom: 100, left: 40, right: 40),
          duration: const Duration(seconds: 1),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      body: Stack(
        children: [
          // 1. DYNAMIC BACKGROUND
          _buildAnimatedBackground(),

          // 2. MAIN CONTENT
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchBar(),
                _buildAppGrid(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: AppGridPainter(color: Colors.white.withOpacity(0.015)),
          ),
          // Soft Glows
          _buildOrbitalGlow(Alignment.topLeft, Colors.white),
          _buildOrbitalGlow(Alignment.bottomRight, Colors.white10),
        ],
      ),
    );
  }

  Widget _buildOrbitalGlow(Alignment align, Color color) {
    return Align(
      alignment: align,
      child: Container(
        width: 400, height: 400,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.03), Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("REMOTE", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 4, fontSize: 10)),
              const Text("APPS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 42, letterSpacing: -2)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: _fetchApps,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white30),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: "SEARCH APPLICATIONS...",
                hintStyle: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white24, size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppGrid() {
    return Expanded(
      child: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : _filteredApps.isEmpty 
          ? _buildEmptyState()
          : GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.82, 
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _filteredApps.length,
              itemBuilder: (context, index) => _buildAppItem(_filteredApps[index]),
            ),
    );
  }

  Widget _buildAppItem(dynamic app) {
    return _AppLauncherCard(
      name: app['name'] ?? "Unknown",
      iconBase64: app['icon_base64'],
      onTap: () => _launchApp(app['exec']),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.apps_outlined, size: 48, color: Colors.white10),
          const SizedBox(height: 16),
          const Text("NO APPLICATIONS FOUND", style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _AppLauncherCard extends StatefulWidget {
  final String name;
  final String? iconBase64;
  final VoidCallback onTap;

  const _AppLauncherCard({required this.name, this.iconBase64, required this.onTap, super.key});

  @override
  State<_AppLauncherCard> createState() => _AppLauncherCardState();
}

class _AppLauncherCardState extends State<_AppLauncherCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
         setState(() => _isPressed = false);
         widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_isPressed ? 0.12 : 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isPressed ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.08),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Container(
                 width: 50, height: 50,
                 margin: const EdgeInsets.only(bottom: 10),
                 decoration: BoxDecoration(
                   color: Colors.white.withOpacity(0.08),
                   borderRadius: BorderRadius.circular(16),
                 ),
                 child: widget.iconBase64 != null && widget.iconBase64!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          base64Decode(widget.iconBase64!),
                          fit: BoxFit.cover,
                          cacheWidth: 100,
                          cacheHeight: 100,
                          errorBuilder: (_, __, ___) => const Icon(Icons.rocket_launch_rounded, color: Colors.white70, size: 24),
                        ),
                      )
                    : const Icon(Icons.rocket_launch_rounded, color: Colors.white70, size: 24),
               ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isPressed ? Colors.white : Colors.white70, 
                    fontSize: 10, 
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppGridPainter extends CustomPainter {
  final Color color;
  AppGridPainter({required this.color});
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

