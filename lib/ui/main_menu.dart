import 'dart:math';

import 'package:flutter/material.dart';

/// Title screen with underground-themed design, ember particles, and glowing title.
class MainMenu extends StatefulWidget {
  final VoidCallback onNewGame;
  final VoidCallback onLoadGame;

  const MainMenu({
    super.key,
    required this.onNewGame,
    required this.onLoadGame,
  });

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> with TickerProviderStateMixin {
  late final AnimationController _particleController;
  late final AnimationController _titleGlowController;
  late final AnimationController _subtitleController;
  late final AnimationController _buttonsController;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _titleGlowController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    _subtitleController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..forward();

    _buttonsController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    // Stagger buttons entrance after subtitle finishes
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _buttonsController.forward();
    });
  }

  @override
  void dispose() {
    _particleController.dispose();
    _titleGlowController.dispose();
    _subtitleController.dispose();
    _buttonsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background: rich underground gradient
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _titleGlowController,
              builder: (context, _) {
                final glow = _titleGlowController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF000000),
                        Color.lerp(
                          const Color(0xFF0A0503),
                          const Color(0xFF120800),
                          glow * 0.3,
                        )!,
                        Color.lerp(
                          const Color(0xFF1A0D05),
                          const Color(0xFF2A1200),
                          glow * 0.3,
                        )!,
                        const Color(0xFF0D0604),
                        const Color(0xFF050202),
                      ],
                      stops: const [0.0, 0.2, 0.45, 0.7, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Geological strata lines
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _GeologicalLinesPainter(
                    phase: _particleController.value,
                  ),
                );
              },
            ),
          ),

          // Animated particle overlay (embers rising)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _MenuParticleOverlay(
                    phase: _particleController.value,
                  ),
                );
              },
            ),
          ),

          // Dark vignette overlay for depth
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.3, 0.7, 1.0],
                ),
              ),
            ),
          ),

          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // Title with animated glow + heat shimmer
                AnimatedBuilder(
                  animation: Listenable.merge(
                      [_titleGlowController, _particleController]),
                  builder: (context, _) {
                    final glow = _titleGlowController.value;
                    final shimmer =
                        sin(_particleController.value * 2 * pi * 3) * 0.5;
                    return Transform.translate(
                      offset: Offset(0, shimmer),
                      child: Column(
                        children: [
                          Text(
                            'MOTHERLODE',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              shadows: [
                                Shadow(
                                  color: Colors.red
                                      .withValues(alpha: 0.5 + 0.3 * glow),
                                  blurRadius: 20 + 15 * glow,
                                ),
                                Shadow(
                                  color: Colors.amber
                                      .withValues(alpha: 0.3 + 0.2 * glow),
                                  blurRadius: 50 + 20 * glow,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Animated accent line
                          Container(
                            width: 180 + 40 * glow,
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.amber
                                      .withValues(alpha: 0.4 + 0.3 * glow),
                                  Colors.amber
                                      .withValues(alpha: 0.4 + 0.3 * glow),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber
                                      .withValues(alpha: 0.3 * glow),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Subtitle with fade-in
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _subtitleController,
                    curve: Curves.easeOut,
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _subtitleController,
                      curve: Curves.easeOut,
                    )),
                    child: Text(
                      'D I G   D E E P E R',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Menu buttons with staggered fade-in
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _buttonsController,
                    curve: Curves.easeOut,
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _buttonsController,
                      curve: Curves.easeOut,
                    )),
                    child: Column(
                      children: [
                        _MenuButton(
                          label: 'NEW GAME',
                          color: Colors.amber,
                          icon: Icons.play_arrow,
                          onTap: widget.onNewGame,
                          isPrimary: true,
                        ),
                        const SizedBox(height: 14),
                        _MenuButton(
                          label: 'LOAD GAME',
                          color: Colors.cyan,
                          icon: Icons.folder_open,
                          onTap: widget.onLoadGame,
                        ),
                        const SizedBox(height: 14),
                        _MenuButton(
                          label: 'LEADERBOARD',
                          color: Colors.green,
                          icon: Icons.leaderboard,
                          onTap: () => _showLeaderboard(context),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Separator line above version info
                Container(
                  width: 120,
                  height: 1,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // Version info
                Text(
                  'v1.0.0',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Inspired by Motherload (XGen Studios, 2004)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.15),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaderboard(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LEADERBOARD',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                      color: Colors.amber.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 80,
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.amber.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Icon(
                Icons.emoji_events_outlined,
                size: 44,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              const SizedBox(height: 12),
              Text(
                'No records yet.\nStart mining!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    'CLOSE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
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

class _MenuButton extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _MenuButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  bool _pressing = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    if (widget.isPrimary) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonWidth = widget.isPrimary ? 280.0 : 260.0;
    final verticalPad = widget.isPrimary ? 16.0 : 14.0;
    final fontSize = widget.isPrimary ? 15.0 : 14.0;
    final iconSize = widget.isPrimary ? 24.0 : 22.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = widget.isPrimary ? _pulseController.value : 0.0;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressing = true),
            onTapUp: (_) {
              setState(() => _pressing = false);
              widget.onTap();
            },
            onTapCancel: () => setState(() => _pressing = false),
            child: AnimatedScale(
              scale: _pressing ? 0.97 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: buttonWidth,
                padding: EdgeInsets.symmetric(
                    vertical: verticalPad, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.color.withValues(
                          alpha: (_hovering ? 0.18 : 0.06) + pulse * 0.05),
                      widget.color.withValues(
                          alpha: (_hovering ? 0.08 : 0.02) + pulse * 0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.color.withValues(
                        alpha: (_hovering ? 0.7 : 0.25) + pulse * 0.15),
                    width: widget.isPrimary ? 1.8 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(
                          alpha: (_hovering ? 0.15 : 0.03) + pulse * 0.08),
                      blurRadius: 16 + pulse * 8,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      color:
                          widget.color.withValues(alpha: 0.6 + pulse * 0.3),
                      size: iconSize,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.color
                            .withValues(alpha: 0.7 + pulse * 0.3),
                        fontSize: fontSize,
                        fontWeight:
                            widget.isPrimary ? FontWeight.w700 : FontWeight.w600,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floating ember particles overlay for the menu background.
class _MenuParticleOverlay extends CustomPainter {
  final double phase;

  _MenuParticleOverlay({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 40; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.3 + random.nextDouble() * 1.2;
      final pSize = 0.8 + random.nextDouble() * 2.2;

      final x = baseX + sin(phase * 2 * pi * speed + i) * 20;
      final y = (baseY - phase * size.height * speed * 0.12) % size.height;

      final alpha =
          (0.15 + 0.5 * sin(phase * 2 * pi + i * 0.5)).clamp(0.0, 1.0);
      paint.color = Color.from(
        alpha: alpha,
        red: 1.0,
        green: 0.3 + random.nextDouble() * 0.35,
        blue: 0.0,
      );

      canvas.drawCircle(Offset(x, y), pSize, paint);

      // Glow around particles — slightly larger radius for vividness
      if (pSize > 1.2) {
        paint.color = Color.from(
          alpha: alpha * 0.12,
          red: 1.0,
          green: 0.45,
          blue: 0.05,
        );
        canvas.drawCircle(Offset(x, y), pSize * 5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MenuParticleOverlay oldDelegate) =>
      oldDelegate.phase != phase;
}

/// Layered horizontal geological lines with depth-appropriate colors.
class _GeologicalLinesPainter extends CustomPainter {
  final double phase;

  _GeologicalLinesPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Layer colors: top = sandy tan, middle = grey-brown, bottom = dark red
    const layerColors = [
      Color(0xFF8B6B3D), // sandy tan
      Color(0xFF8B6B3D),
      Color(0xFF6A5A40),
      Color(0xFF5C4A38), // grey-brown
      Color(0xFF5C4A38),
      Color(0xFF4A3028),
      Color(0xFF3A1515), // dark red-brown
      Color(0xFF3A1515),
    ];

    for (int i = 0; i < 8; i++) {
      final y = size.height * (0.15 + i * 0.1);
      final yOffset = sin(phase * pi * 2 + i * 1.3) * 10;
      final alpha =
          (0.04 + 0.03 * sin(phase * pi * 2 + i * 0.8)).clamp(0.0, 0.08);

      paint.color = layerColors[i].withValues(alpha: alpha);

      final path = Path();
      path.moveTo(0, y + yOffset);
      for (double x = 0; x <= size.width; x += 15) {
        final localY =
            y + yOffset + sin(x * 0.004 + phase * pi * 2 + i * 0.5) * 6;
        path.lineTo(x, localY);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GeologicalLinesPainter old) => true;
}
