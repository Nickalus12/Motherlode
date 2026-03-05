import 'dart:math';

import 'package:flutter/material.dart';

/// Title screen with new game, load, and leaderboard options
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

class _MainMenuState extends State<MainMenu>
    with TickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 2000),
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
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/backgrounds/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0A0A1A),
                      const Color(0xFF1A0D05),
                      const Color(0xFF2A1200),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Dark overlay gradient for readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
          ),

          // Animated particle overlay
          AnimatedBuilder(
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

          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

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
                                color: Colors.red.withValues(alpha: 0.6 + 0.4 * glow),
                                blurRadius: 20 + 15 * glow,
                              ),
                              Shadow(
                                color: Colors.orange.withValues(alpha: 0.5 + 0.3 * glow),
                                blurRadius: 40 + 20 * glow,
                              ),
                              Shadow(
                                color: Colors.amber.withValues(alpha: 0.3 * glow),
                                blurRadius: 60,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Decorative line under title
                        Container(
                          width: 180 + 40 * glow,
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.amber.withValues(alpha: 0.5 + 0.3 * glow),
                                Colors.amber.withValues(alpha: 0.5 + 0.3 * glow),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.3 * glow),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 10),

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
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Menu buttons
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
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Inspired by Motherload (XGen Studios, 2004)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
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
        backgroundColor: const Color(0xFF16161E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LEADERBOARD',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  shadows: [
                    Shadow(
                      color: Colors.amber.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 100,
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.amber.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                Icons.emoji_events_outlined,
                size: 48,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 12),
              Text(
                'No records yet.\nStart mining!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    'CLOSE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
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
              width: 240,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.color.withValues(
                        alpha: (_hovering ? 0.2 : 0.08) + pulse * 0.06),
                    widget.color.withValues(
                        alpha: (_hovering ? 0.1 : 0.03) + pulse * 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.color.withValues(
                      alpha: (_hovering ? 0.8 : 0.35) + pulse * 0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(
                        alpha: (_hovering ? 0.2 : 0.05) + pulse * 0.1),
                    blurRadius: 16 + pulse * 8,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    color: widget.color.withValues(alpha: 0.7 + pulse * 0.3),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          color: widget.color
                              .withValues(alpha: 0.3 + pulse * 0.3),
                          blurRadius: 6,
                        ),
                      ],
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

/// Floating ember particles overlay
class _MenuParticleOverlay extends CustomPainter {
  final double phase;

  _MenuParticleOverlay({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final particlePaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 50; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.5 + random.nextDouble() * 1.5;
      final particleSize = 0.8 + random.nextDouble() * 2.5;

      final x = baseX + sin(phase * 2 * pi * speed + i) * 25;
      final y = (baseY - phase * size.height * speed * 0.1) % size.height;

      final alpha =
          (0.2 + 0.6 * sin(phase * 2 * pi + i * 0.5)).clamp(0.0, 1.0);
      particlePaint.color = Color.from(
        alpha: alpha,
        red: 1.0,
        green: 0.3 + random.nextDouble() * 0.4,
        blue: 0.0,
      );

      canvas.drawCircle(Offset(x, y), particleSize, particlePaint);

      // Add subtle glow around larger particles
      if (particleSize > 2.0) {
        particlePaint.color = Color.from(
          alpha: alpha * 0.15,
          red: 1.0,
          green: 0.5,
          blue: 0.1,
        );
        canvas.drawCircle(Offset(x, y), particleSize * 3, particlePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_MenuParticleOverlay oldDelegate) {
    return oldDelegate.phase != phase;
  }
}
