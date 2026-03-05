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
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Animated background
          AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _MenuBackgroundPainter(
                  phase: _animController.value,
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

                // Title
                const Text(
                  'MOTHERLODE',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    shadows: [
                      Shadow(
                        color: Colors.red,
                        blurRadius: 20,
                      ),
                      Shadow(
                        color: Colors.orange,
                        blurRadius: 40,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'D I G   D E E P E R',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                    letterSpacing: 6,
                  ),
                ),

                const Spacer(flex: 1),

                // Menu buttons
                _MenuButton(
                  label: 'NEW GAME',
                  color: Colors.amber,
                  onTap: widget.onNewGame,
                ),
                const SizedBox(height: 16),
                _MenuButton(
                  label: 'LOAD GAME',
                  color: Colors.cyan,
                  onTap: widget.onLoadGame,
                ),
                const SizedBox(height: 16),
                _MenuButton(
                  label: 'LEADERBOARD',
                  color: Colors.green,
                  onTap: () {
                    // Show leaderboard dialog
                    _showLeaderboard(context);
                  },
                ),

                const Spacer(flex: 2),

                // Version info
                Text(
                  'v1.0.0 — Inspired by Motherload (XGen Studios, 2004)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
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
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'LEADERBOARD',
          style: TextStyle(color: Colors.amber, letterSpacing: 3),
        ),
        content: SizedBox(
          width: 300,
          height: 300,
          child: Center(
            child: Text(
              'No records yet.\nStart mining!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _hovering
                ? widget.color.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.color.withValues(alpha: _hovering ? 0.8 : 0.4),
              width: 1.5,
            ),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated background painter with floating particles and terrain silhouette
class _MenuBackgroundPainter extends CustomPainter {
  final double phase;

  _MenuBackgroundPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark gradient background
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF0A0000),
        const Color(0xFF1A0000),
        const Color(0xFF2A0500),
      ],
    );
    canvas.drawRect(bgRect, Paint()..shader = bgGradient.createShader(bgRect));

    // Floating ember particles
    final random = Random(42);
    final particlePaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 40; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.5 + random.nextDouble() * 1.5;
      final particleSize = 1 + random.nextDouble() * 2;

      final x = baseX + sin(phase * 2 * pi * speed + i) * 20;
      final y = (baseY - phase * size.height * speed * 0.1) %
          size.height;

      final alpha = (0.3 + 0.7 * sin(phase * 2 * pi + i * 0.5)).clamp(0.0, 1.0);
      particlePaint.color = Color.from(
        alpha: alpha,
        red: 1.0,
        green: 0.3 + random.nextDouble() * 0.3,
        blue: 0.0,
      );

      canvas.drawCircle(Offset(x, y), particleSize, particlePaint);
    }

    // Bottom terrain silhouette
    final terrainPath = Path();
    terrainPath.moveTo(0, size.height);

    for (double x = 0; x <= size.width; x += 10) {
      final noise = sin(x * 0.01 + phase * 2 * pi * 0.3) * 30 +
          sin(x * 0.025) * 15 +
          sin(x * 0.005 + 2) * 50;
      terrainPath.lineTo(x, size.height * 0.85 + noise);
    }
    terrainPath.lineTo(size.width, size.height);
    terrainPath.close();

    canvas.drawPath(
      terrainPath,
      Paint()..color = const Color(0xFF0D0000),
    );
  }

  @override
  bool shouldRepaint(_MenuBackgroundPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}
