import 'dart:math';

import 'package:flutter/material.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/data/special_items.dart';
import 'package:hellbore/entities/pod/pod.dart';

/// HUD overlay drawn as Flutter widgets on top of Flame canvas
///
/// LEFT SIDE: Fuel gauge, Hull gauge (animated liquid fill bars)
/// RIGHT SIDE: Cargo weight gauge, Cash display
/// TOP CENTER: Depth meter with biome label
/// BOTTOM: Active consumable hotkeys with quantity badges
class HudOverlay extends StatefulWidget {
  final HellboreGame game;

  const HudOverlay({super.key, required this.game});

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  String? _biomeToastText;
  double _biomeToastOpacity = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    // Listen for biome changes
    widget.game.depthSystem.onBiomeChange = (newBiome) {
      setState(() {
        _biomeToastText =
            'ENTERING ${widget.game.depthSystem.currentBiomeName.toUpperCase()}';
        _biomeToastOpacity = 1.0;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _biomeToastOpacity = 0);
        }
      });
    };
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
        return Stack(
          children: [
            // Screen effects
            _buildScreenEffects(),

            // Left side - Fuel & Hull gauges
            Positioned(
              left: 12,
              top: 80,
              child: Column(
                children: [
                  _buildVerticalGauge(
                    label: 'FUEL',
                    ratio: widget.game.fuelSystem.fuelRatio,
                    color: _fuelColor,
                    width: 28,
                    height: 140,
                  ),
                  const SizedBox(height: 12),
                  _buildVerticalGauge(
                    label: 'HULL',
                    ratio: widget.game.hullSystem.hullRatio,
                    color: _hullColor,
                    width: 28,
                    height: 140,
                    segmented: true,
                  ),
                ],
              ),
            ),

            // Right side - Cargo & Cash
            Positioned(
              right: 12,
              top: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildCargoGauge(),
                  const SizedBox(height: 12),
                  _buildCashDisplay(),
                ],
              ),
            ),

            // Top center - Depth meter
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: _buildDepthMeter(),
            ),

            // Biome transition toast
            if (_biomeToastText != null)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _biomeToastOpacity,
                  duration: const Duration(milliseconds: 500),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        _biomeToastText!,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom - Consumable hotkeys
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: _buildConsumableBar(),
            ),

            // Depth record notification
            if (widget.game.depthSystem.isNewDepthRecord &&
                widget.game.currentDepthFeet > 100)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '▼ NEW DEPTH RECORD ▼',
                    style: TextStyle(
                      color: Colors.amber.withValues(
                          alpha: 0.5 + 0.5 * _pulseController.value),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScreenEffects() {
    return Stack(
      children: [
        // Hull damage flash
        if (widget.game.hullSystem.recentDamage)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.red.withValues(alpha: 0.3 * _pulseController.value),
              ),
            ),
          ),

        // Low fuel warning vignette
        if (widget.game.fuelSystem.isLowFuel)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      Colors.orange.withValues(
                          alpha: 0.2 + 0.1 * _pulseController.value),
                    ],
                    radius: 0.8,
                  ),
                ),
              ),
            ),
          ),

        // Low hull vignette
        if (widget.game.hullSystem.isLowHull)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      Colors.red.withValues(
                          alpha: (1.0 - widget.game.hullSystem.hullRatio) * 0.6),
                    ],
                    radius: 0.7,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVerticalGauge({
    required String label,
    required double ratio,
    required Color color,
    required double width,
    required double height,
    bool segmented = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Fill
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: width,
                height: height * ratio,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Segments overlay
              if (segmented)
                ...List.generate(
                  5,
                  (i) => Positioned(
                    bottom: height * (i + 1) / 6,
                    child: Container(
                      width: width,
                      height: 1,
                      color: Colors.black38,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(ratio * 100).toInt()}%',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCargoGauge() {
    final fillRatio = widget.game.pod.cargoSystem.fillRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'CARGO',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          height: 60,
          child: CustomPaint(
            painter: _CargoGaugePainter(
              fillRatio: fillRatio,
              color: fillRatio > 0.9 ? Colors.red : Colors.cyan,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${widget.game.pod.cargoSystem.currentWeight.toInt()}/'
          '${widget.game.pod.cargoSystem.maxCapacity.toInt()} kg',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildCashDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Text(
        '\$${_formatCash(widget.game.playerCash)}',
        style: const TextStyle(
          color: Colors.amber,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDepthMeter() {
    final depth = widget.game.currentDepthFeet;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Text(
              '▼ ${depth.toStringAsFixed(0)} ft',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.game.depthSystem.currentBiomeName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumableBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildConsumableSlot('X', '💣', widget.game.dynamiteCount),
        _buildConsumableSlot('C', '💥', widget.game.plasticExplosiveCount),
        _buildConsumableSlot('F', '⛽', widget.game.reserveFuelCount),
        _buildConsumableSlot('R', '🔧', widget.game.nanobotCount),
        _buildConsumableSlot('Q', '⚡', widget.game.teleporterCount),
        _buildConsumableSlot('M', '🌟', widget.game.transmitterCount),
      ],
    );
  }

  Widget _buildConsumableSlot(String hotkey, String icon, int count) {
    final hasItem = count > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hasItem ? Colors.black54 : Colors.black26,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasItem ? Colors.white30 : Colors.white10,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  icon,
                  style: TextStyle(
                    fontSize: 18,
                    color: hasItem ? null : Colors.white24,
                  ),
                ),
                Text(
                  hotkey,
                  style: TextStyle(
                    color: hasItem ? Colors.white54 : Colors.white12,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color get _fuelColor {
    final ratio = widget.game.fuelSystem.fuelRatio;
    if (ratio > 0.5) return Colors.green;
    if (ratio > 0.25) return Colors.yellow;
    return Colors.red;
  }

  Color get _hullColor {
    final ratio = widget.game.hullSystem.hullRatio;
    if (ratio > 0.5) return Colors.cyan;
    if (ratio > 0.25) return Colors.orange;
    return Colors.red;
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}

/// Custom painter for circular cargo gauge
class _CargoGaugePainter extends CustomPainter {
  final double fillRatio;
  final Color color;

  _CargoGaugePainter({required this.fillRatio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Background circle
    final bgPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    // Fill arc
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * fillRatio;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // Start from top
      sweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_CargoGaugePainter oldDelegate) {
    return oldDelegate.fillRatio != fillRatio || oldDelegate.color != color;
  }
}
