import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;
import 'package:flutter/material.dart';

import 'package:motherlode/data/special_items.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/ui/shop_overlay.dart';

/// HUD overlay drawn as Flutter widgets on top of Flame canvas
///
/// LEFT SIDE: Fuel gauge, Hull gauge (animated gradient fill bars with glow)
/// RIGHT SIDE: Cargo weight gauge, Cash display
/// TOP CENTER: Depth meter with biome label
/// BOTTOM: Active consumable hotkeys with quantity badges
class HudOverlay extends StatefulWidget {
  final MotherlodeGame game;

  const HudOverlay({super.key, required this.game});

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _glowController;
  String? _biomeToastText;
  double _biomeToastOpacity = 0;
  bool _shopOpen = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _setupBiomeListener();
  }

  void _setupBiomeListener() {
    if (widget.game.isLoaded) {
      widget.game.depthSystem.onBiomeChange = _onBiomeChange;
    } else {
      widget.game.loaded.then((_) {
        if (mounted) {
          widget.game.depthSystem.onBiomeChange = _onBiomeChange;
        }
      });
    }
  }

  void _onBiomeChange(dynamic newBiome) {
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.game.isLoaded) {
      return IgnorePointer(
        child: Center(
          child: Text(
            'LOADING...',
            style: TextStyle(
              color: Colors.amber.withValues(alpha: 0.6),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
        ),
      );
    }

    if (_shopOpen) {
      return ShopOverlay(
        game: widget.game,
        onClose: () => setState(() => _shopOpen = false),
      );
    }

    return DefaultTextStyle(
      style: const TextStyle(decoration: TextDecoration.none),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _glowController]),
        builder: (context, _) {
          return Stack(
            children: [
              // Full-screen touch layer that forwards events to the game
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) {
                    if (!widget.game.pod.isMounted) return;
                    widget.game.podController.handleTouchDown(
                      0,
                      Vector2(details.localPosition.dx, details.localPosition.dy),
                    );
                  },
                  onPanUpdate: (details) {
                    if (!widget.game.pod.isMounted) return;
                    widget.game.podController.handleTouchMove(
                      0,
                      Vector2(details.localPosition.dx, details.localPosition.dy),
                    );
                  },
                  onPanEnd: (_) {
                    if (!widget.game.pod.isMounted) return;
                    widget.game.podController.handleTouchUp(0);
                  },
                  onPanCancel: () {
                    if (!widget.game.pod.isMounted) return;
                    widget.game.podController.handleTouchUp(0);
                  },
                ),
              ),
            // Screen effects (non-interactive)
            IgnorePointer(child: _buildScreenEffects()),

            // Top HUD strip (non-interactive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(child: _buildTopStrip()),
            ),

            // Left side - Fuel & Hull gauges (non-interactive)
            Positioned(
              left: 10,
              top: MediaQuery.of(context).padding.top + 56,
              child: IgnorePointer(
                child: Column(
                  children: [
                    _buildGaugeBar(
                      label: 'FUEL',
                      ratio: widget.game.fuelSystem.fuelRatio,
                      colors: _fuelGradientColors,
                      icon: Icons.local_gas_station,
                      width: 32,
                      height: 130,
                    ),
                    const SizedBox(height: 10),
                    _buildGaugeBar(
                      label: 'HULL',
                      ratio: widget.game.hullSystem.hullRatio,
                      colors: _hullGradientColors,
                      icon: Icons.shield,
                      width: 32,
                      height: 130,
                      segmented: true,
                    ),
                  ],
                ),
              ),
            ),

            // Right side - Cargo & Cash
            Positioned(
              right: 10,
              top: MediaQuery.of(context).padding.top + 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IgnorePointer(child: _buildCargoGauge()),
                  const SizedBox(height: 10),
                  IgnorePointer(child: _buildCashDisplay()),
                  if (widget.game.isAtSurface) ...[
                    const SizedBox(height: 10),
                    _buildShopButton(),
                  ],
                ],
              ),
            ),

            // Biome transition toast
            if (_biomeToastText != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 48,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _biomeToastOpacity,
                    duration: const Duration(milliseconds: 500),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black87,
                              Colors.black87,
                              Colors.transparent,
                            ],
                          ),
                          border: Border(
                            top: BorderSide(
                                color: Colors.amber.withValues(alpha: 0.6)),
                            bottom: BorderSide(
                                color: Colors.amber.withValues(alpha: 0.6)),
                          ),
                        ),
                        child: Text(
                          _biomeToastText!,
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            shadows: [
                              Shadow(
                                color: Colors.amber.withValues(alpha: 0.6),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom - Consumable hotkeys (non-interactive for now)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: IgnorePointer(child: _buildConsumableBar()),
            ),

            // Depth record notification
            if (widget.game.depthSystem.isNewDepthRecord &&
                widget.game.currentDepthFeet > 100)
              Positioned(
                bottom: 72,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.amber
                                .withValues(alpha: 0.15 + 0.1 * _pulseController.value),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Text(
                        'NEW DEPTH RECORD',
                        style: TextStyle(
                          color: Colors.amber.withValues(
                              alpha: 0.6 + 0.4 * _pulseController.value),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          shadows: [
                            Shadow(
                              color: Colors.amber
                                  .withValues(alpha: 0.5 * _pulseController.value),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopStrip() {
    final depth = widget.game.currentDepthFeet;
    final safeTop = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(top: safeTop + 4, bottom: 6, left: 16, right: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Depth display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _depthBorderColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _depthBorderColor.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward,
                  color: _depthBorderColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${depth.toStringAsFixed(0)} ft',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: _depthBorderColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _depthBorderColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.game.depthSystem.currentBiomeName.toUpperCase(),
                    style: TextStyle(
                      color: _depthBorderColor.withValues(alpha: 0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get _depthBorderColor {
    final depth = widget.game.currentDepthFeet;
    if (depth < 200) return Colors.lightGreenAccent;
    if (depth < 1000) return Colors.amber;
    if (depth < 3000) return Colors.orange;
    if (depth < 5000) return Colors.deepOrange;
    return Colors.redAccent;
  }

  Widget _buildScreenEffects() {
    return Stack(
      children: [
        // Hull damage flash
        if (widget.game.hullSystem.recentDamage)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color:
                    Colors.red.withValues(alpha: 0.3 * _pulseController.value),
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
                          alpha:
                              (1.0 - widget.game.hullSystem.hullRatio) * 0.6),
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

  Widget _buildGaugeBar({
    required String label,
    required double ratio,
    required List<Color> colors,
    required IconData icon,
    required double width,
    required double height,
    bool segmented = false,
  }) {
    final isLow = ratio < 0.25;
    final glowIntensity = isLow ? _pulseController.value : _glowController.value * 0.3;

    return Column(
      children: [
        // Icon with label
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.last.withValues(alpha: 0.8), size: 12),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // Gauge body
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(width / 2),
            border: Border.all(
              color: isLow
                  ? colors.last
                      .withValues(alpha: 0.5 + 0.5 * _pulseController.value)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
            boxShadow: [
              if (isLow)
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.4 * glowIntensity),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(width / 2),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Gradient fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: width,
                  height: height * ratio.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: colors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.last
                            .withValues(alpha: 0.3 + 0.2 * glowIntensity),
                        blurRadius: 6,
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                ),
                // Inner highlight (glass effect)
                Positioned(
                  left: 2,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Segment lines
                if (segmented)
                  ...List.generate(
                    4,
                    (i) => Positioned(
                      bottom: height * (i + 1) / 5,
                      child: Container(
                        width: width,
                        height: 1,
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        // Percentage text
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${(ratio * 100).toInt()}%',
            style: TextStyle(
              color: isLow ? colors.last : Colors.white.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCargoGauge() {
    final fillRatio = widget.game.pod.cargoSystem.fillRatio;
    final isFull = fillRatio > 0.9;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2, color: Colors.white54, size: 12),
            const SizedBox(width: 3),
            Text(
              'CARGO',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              if (isFull)
                BoxShadow(
                  color: Colors.red
                      .withValues(alpha: 0.3 + 0.2 * _pulseController.value),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _CargoGaugePainter(
                fillRatio: fillRatio,
                color: isFull ? Colors.red : Colors.cyan,
                glowIntensity: _glowController.value,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${widget.game.pod.cargoSystem.currentWeight.toInt()}/'
            '${widget.game.pod.cargoSystem.maxCapacity.toInt()} kg',
            style: TextStyle(
              color: isFull ? Colors.red : Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCashDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withValues(alpha: 0.12),
            Colors.amber.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on,
            color: Colors.amber,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '\$${_formatCash(widget.game.playerCash)}',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.amber.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopButton() {
    return GestureDetector(
      onTap: () => setState(() => _shopOpen = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.amber.withValues(alpha: 0.2 + 0.1 * _glowController.value),
              Colors.orange.withValues(alpha: 0.15 + 0.1 * _glowController.value),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.amber
                  .withValues(alpha: 0.15 + 0.1 * _glowController.value),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Icon(Icons.storefront, color: Colors.amber, size: 20),
      ),
    );
  }

  Widget _buildConsumableBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildConsumableSlot('X', Icons.flash_on, widget.game.dynamiteCount,
            Colors.orange, SpecialItems.dynamite.spritePath),
        _buildConsumableSlot('C', Icons.local_fire_department,
            widget.game.plasticExplosiveCount, Colors.red, SpecialItems.plasticExplosive.spritePath),
        _buildConsumableSlot('F', Icons.local_gas_station,
            widget.game.reserveFuelCount, Colors.green, SpecialItems.reserveFuelTank.spritePath),
        _buildConsumableSlot(
            'R', Icons.build, widget.game.nanobotCount, Colors.cyan, SpecialItems.hullRepairNanobots.spritePath),
        _buildConsumableSlot('Q', Icons.bolt, widget.game.teleporterCount,
            Colors.purple, SpecialItems.quantumTeleporter.spritePath),
        _buildConsumableSlot('M', Icons.star, widget.game.transmitterCount,
            Colors.amber, SpecialItems.matterTransmitter.spritePath),
      ],
    );
  }

  Widget _buildConsumableSlot(
      String hotkey, IconData icon, int count, Color accentColor, String? spritePath) {
    final hasItem = count > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: hasItem
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accentColor.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    )
                  : null,
              color: hasItem ? null : Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasItem
                    ? accentColor.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
                width: 1.5,
              ),
              boxShadow: hasItem
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.15),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: hasItem && spritePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/$spritePath',
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 20,
                      color: hasItem
                          ? accentColor
                          : Colors.white.withValues(alpha: 0.15),
                    ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor, accentColor.withValues(alpha: 0.8)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ],
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

  List<Color> get _fuelGradientColors {
    final ratio = widget.game.fuelSystem.fuelRatio;
    if (ratio > 0.5) return [Colors.green.shade900, Colors.green, Colors.greenAccent];
    if (ratio > 0.25) return [Colors.orange.shade900, Colors.yellow, Colors.yellowAccent];
    return [Colors.red.shade900, Colors.red, Colors.redAccent];
  }

  List<Color> get _hullGradientColors {
    final ratio = widget.game.hullSystem.hullRatio;
    if (ratio > 0.5) return [Colors.blue.shade900, Colors.cyan, Colors.cyanAccent];
    if (ratio > 0.25) return [Colors.orange.shade900, Colors.orange, Colors.orangeAccent];
    return [Colors.red.shade900, Colors.red, Colors.redAccent];
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}

/// Custom painter for circular cargo gauge with glow effect
class _CargoGaugePainter extends CustomPainter {
  final double fillRatio;
  final Color color;
  final double glowIntensity;

  _CargoGaugePainter({
    required this.fillRatio,
    required this.color,
    this.glowIntensity = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Dark background circle
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius + 2, bgPaint);

    // Background track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(center, radius, trackPaint);

    // Fill arc with gradient
    final sweepAngle = 2 * pi * fillRatio;
    if (fillRatio > 0.01) {
      // Glow
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.15 + 0.1 * glowIntensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        sweepAngle,
        false,
        glowPaint,
      );

      // Main arc
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.sweep(
          center,
          [
            color.withValues(alpha: 0.6),
            color,
          ],
          [0.0, 1.0],
          TileMode.clamp,
          -pi / 2,
          -pi / 2 + sweepAngle,
        );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        sweepAngle,
        false,
        fillPaint,
      );
    }

    // Center percentage text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${(fillRatio * 100).toInt()}%',
        style: TextStyle(
          color: fillRatio > 0.9 ? Colors.red : Colors.white.withValues(alpha: 0.7),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_CargoGaugePainter oldDelegate) {
    return oldDelegate.fillRatio != fillRatio ||
        oldDelegate.color != color ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}
