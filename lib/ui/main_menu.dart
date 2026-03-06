import 'dart:math';

import 'package:flutter/material.dart';

/// Title screen with new game, load, and leaderboard options.
///
/// Deep underground-themed design with animated ember particles,
/// geological gradient background, and glowing title.
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
  }

  @override
  void dispose() {
    _particleController.dispose();
    _titleGlowController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background: deep underground gradient (no image dependency)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _titleGlowController,
              builder: (context, _) {
                final glow = _titleGlowController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.3),
                      radius: 1.5,
                      colors: [
                        Color.lerp(
                          const Color(0xFF1A0D05),
                          const Color(0xFF2A1200),
                          glow * 0.3,
                        )!,
                        const Color(0xFF0D0808),
                        const Color(0xFF050303),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.35, 0.65, 1.0],
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

                // Title with animated glow
                AnimatedBuilder(
                  animation: _titleGlowController,
                  builder: (context, _) {
                    final glow = _titleGlowController.value;
                    return Column(
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
                                color: Colors.orange
                                    .withValues(alpha: 0.4 + 0.2 * glow),
                                blurRadius: 40 + 20 * glow,
                              ),
                              Shadow(
                                color:
                                    Colors.amber.withValues(alpha: 0.2 * glow),
                                blurRadius: 60,
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

                // Menu buttons with labels
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
                  icon: Icons.save,
                  onTap: widget.onLoadGame,
                ),
                const SizedBox(height: 14),
                _MenuButton(
                  label: 'LEADERBOARD',
                  color: Colors.green,
                  icon: Icons.leaderboard,
                  onTap: () => _showLeaderboard(context),
                ),

                const Spacer(flex: 2),

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
                const SizedBox(height: 16),
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
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
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
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = widget.isPrimary ? _pulseController.value : 0.0;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 260,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
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
                  width: 1.5,
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
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.color
                          .withValues(alpha: 0.7 + pulse * 0.3),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                    ),
                  ),
                ],
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

    for (int i = 0; i < 60; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.3 + random.nextDouble() * 1.2;
      final pSize = 0.6 + random.nextDouble() * 2.0;

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

      // Glow around larger particles
      if (pSize > 1.5) {
        paint.color = Color.from(
          alpha: alpha * 0.1,
          red: 1.0,
          green: 0.45,
          blue: 0.05,
        );
        canvas.drawCircle(Offset(x, y), pSize * 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MenuParticleOverlay oldDelegate) =>
      oldDelegate.phase != phase;
}

/// Subtle horizontal geological lines for atmosphere.
class _GeologicalLinesPainter extends CustomPainter {
  final double phase;

  _GeologicalLinesPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 0; i < 8; i++) {
      final y = size.height * (0.15 + i * 0.1);
      final yOffset = sin(phase * pi * 2 + i * 1.3) * 10;
      final alpha = (0.02 + 0.02 * sin(phase * pi * 2 + i * 0.8))
          .clamp(0.0, 0.05);

      paint.color = Colors.amber.withValues(alpha: alpha);

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
