import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;
import 'package:flutter/material.dart';

import 'package:motherlode/data/special_items.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/persistence/save_manager.dart';
import 'package:motherlode/systems/depth_system.dart';
import 'package:motherlode/ui/shop_overlay.dart';
import 'package:motherlode/utils/constants.dart';

/// HUD overlay drawn as Flutter widgets on top of Flame canvas
///
/// LEFT SIDE: Fuel gauge, Hull gauge (animated gradient fill bars with glow)
/// RIGHT SIDE: Cargo weight gauge, Cash display
/// TOP CENTER: Depth meter with biome label
/// BOTTOM: Active consumable hotkeys with quantity badges
class HudOverlay extends StatefulWidget {
  final MotherlodeGame game;
  final VoidCallback? onReturnToMenu;

  const HudOverlay({super.key, required this.game, this.onReturnToMenu});

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final AnimationController _glowController;
  String? _biomeToastText;
  double _biomeToastOpacity = 0;
  String? _milestoneTitle;
  String? _milestoneBonus;
  double _milestoneOpacity = 0;
  bool _shopOpen = false;
  bool _pauseOpen = false;
  bool _saving = false;
  bool _surfaceStationOpen = false;
  bool _wasAtSurface = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Auto-save and pause when app goes to background
      if (!widget.game.isGameOver && widget.game.isLoaded) {
        widget.game.paused = true;
        SaveManager.autoSave(widget.game);
        if (mounted && !_pauseOpen) {
          setState(() => _pauseOpen = true);
        }
      }
    }
  }

  void _setupBiomeListener() {
    if (widget.game.isLoaded) {
      widget.game.depthSystem.onBiomeChange = _onBiomeChange;
      widget.game.depthSystem.onMilestoneReached = _onMilestoneReached;
    } else {
      widget.game.loaded.then((_) {
        if (mounted) {
          widget.game.depthSystem.onBiomeChange = _onBiomeChange;
          widget.game.depthSystem.onMilestoneReached = _onMilestoneReached;
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

  void _onMilestoneReached(DepthMilestone milestone) {
    // Award cash bonus
    widget.game.addCash(milestone.cashBonus);

    // Emit celebration particles around the pod
    widget.game.particleSystem.emitOreSparkle(
      widget.game.pod.position,
      Colors.amber,
    );

    // Camera shake for celebration feel
    widget.game.earthquakeSystem.startShake(0.3, 0.4);

    // Show milestone toast
    setState(() {
      _milestoneTitle = '${milestone.depth.toInt()} FT — ${milestone.name}';
      _milestoneBonus = '+\$${milestone.cashBonus.toInt()}';
      _milestoneOpacity = 1.0;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _milestoneOpacity = 0);
      }
    });
  }

  void _togglePause() {
    setState(() {
      _pauseOpen = !_pauseOpen;
      widget.game.paused = _pauseOpen;
    });
  }

  void _resumeGame() {
    setState(() {
      _pauseOpen = false;
      widget.game.paused = false;
    });
  }

  Future<void> _saveAndQuit() async {
    setState(() => _saving = true);
    try {
      await SaveManager.saveGame(widget.game);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    widget.game.paused = false;
    widget.onReturnToMenu?.call();
  }

  Future<void> _confirmQuit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Text(
          'SAVE & QUIT?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        content: const Text(
          'Your progress will be saved. You can resume from the main menu.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCEL',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                letterSpacing: 1,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'SAVE & QUIT',
              style: TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _saveAndQuit();
    }
  }

  Widget _buildPauseMenu() {
    return DefaultTextStyle(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                'PAUSED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  shadows: [
                    Shadow(
                      color: Colors.cyan.withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 120,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.cyan.withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Resume button
              _buildPauseMenuButton(
                label: 'RESUME',
                icon: Icons.play_arrow,
                color: Colors.cyan,
                onTap: _resumeGame,
              ),
              const SizedBox(height: 14),

              // Save & Quit button
              _buildPauseMenuButton(
                label: _saving ? 'SAVING...' : 'SAVE & QUIT',
                icon: _saving ? Icons.hourglass_top : Icons.save,
                color: Colors.amber,
                onTap: _saving ? null : _confirmQuit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPauseMenuButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Detect when the pod transitions from underground to surface and
  /// has cargo to sell, fuel to refill, or hull to repair.
  void _checkSurfaceLanding() {
    final atSurface = widget.game.isAtSurface;
    if (atSurface && !_wasAtSurface && !_surfaceStationOpen && !_shopOpen) {
      final hasCargo = widget.game.pod.cargoSystem.currentWeight > 0;
      final needsFuel = widget.game.fuelSystem.fuelRatio < 0.99;
      final needsRepair = widget.game.hullSystem.hullRatio < 0.99;
      if (hasCargo || needsFuel || needsRepair) {
        // Schedule for next frame to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _surfaceStationOpen = true);
        });
      }
    }
    _wasAtSurface = atSurface;
  }

  void _closeSurfaceStation() {
    setState(() => _surfaceStationOpen = false);
  }

  /// Perform refuel + repair + sell in one tap.
  void _serviceAll() {
    final game = widget.game;
    final fuelSystem = game.fuelSystem;
    final hullSystem = game.hullSystem;
    final cargo = game.pod.cargoSystem;

    // Sell all cargo first to get cash
    final cargoValue = cargo.sellAll();
    game.addCash(cargoValue);

    // Calculate costs
    final fuelNeeded = fuelSystem.maxFuel - fuelSystem.currentFuel;
    final fuelCost = fuelNeeded * GameConstants.fuelCostPerLiter;
    final hullNeeded = hullSystem.maxHull - hullSystem.currentHull;
    final hullCost = hullNeeded * 20.0; // $20 per HP

    // Pay for fuel (partial fill if can't afford full)
    final totalCost = fuelCost + hullCost;
    if (game.playerCash >= totalCost) {
      game.spendCash(totalCost);
      fuelSystem.addFuel(fuelNeeded);
      hullSystem.repair(hullNeeded);
    } else {
      // Prioritize fuel, then hull with remaining cash
      if (game.playerCash >= fuelCost) {
        game.spendCash(fuelCost);
        fuelSystem.addFuel(fuelNeeded);
        final remaining = game.playerCash;
        final affordableHull = remaining / 20.0;
        if (affordableHull > 0) {
          game.spendCash(affordableHull.clamp(0, hullNeeded) * 20.0);
          hullSystem.repair(affordableHull.clamp(0, hullNeeded));
        }
      } else {
        // Can't even afford full fuel — buy what we can
        final affordableFuel = game.playerCash / GameConstants.fuelCostPerLiter;
        if (affordableFuel > 0) {
          game.spendCash(affordableFuel * GameConstants.fuelCostPerLiter);
          fuelSystem.addFuel(affordableFuel);
        }
      }
    }

    setState(() => _surfaceStationOpen = false);
  }

  Widget _buildSurfaceStation() {
    final game = widget.game;
    final cargo = game.pod.cargoSystem;
    final fuelSystem = game.fuelSystem;
    final hullSystem = game.hullSystem;

    final cargoValue = cargo.totalValue;
    final fuelNeeded = fuelSystem.maxFuel - fuelSystem.currentFuel;
    final fuelCost = fuelNeeded * GameConstants.fuelCostPerLiter;
    final hullNeeded = hullSystem.maxHull - hullSystem.currentHull;
    final hullCost = hullNeeded * 20.0;
    final totalServiceCost = fuelCost + hullCost;
    final netGain = cargoValue - totalServiceCost;

    return DefaultTextStyle(
      style: const TextStyle(decoration: TextDecoration.none),
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.black.withValues(alpha: 0.9),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    'SURFACE STATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      shadows: [
                        Shadow(
                          color: Colors.cyan.withValues(alpha: 0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 140,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.cyan.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Cargo value
                  if (cargoValue > 0) ...[
                    _buildStationRow(
                      icon: Icons.inventory_2,
                      label: 'Cargo Value',
                      value: '+\$${_formatCash(cargoValue)}',
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Fuel cost
                  if (fuelNeeded > 0.1) ...[
                    _buildStationRow(
                      icon: Icons.local_gas_station,
                      label: 'Refuel (${fuelNeeded.toStringAsFixed(0)}L)',
                      value: '-\$${fuelCost.toStringAsFixed(0)}',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Hull repair cost
                  if (hullNeeded > 0.1) ...[
                    _buildStationRow(
                      icon: Icons.shield,
                      label: 'Repair (${hullNeeded.toStringAsFixed(1)} HP)',
                      value: '-\$${hullCost.toStringAsFixed(0)}',
                      color: Colors.cyan,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Divider
                  Container(
                    width: double.infinity,
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),

                  // Net gain/cost
                  _buildStationRow(
                    icon: Icons.monetization_on,
                    label: 'Net',
                    value:
                        '${netGain >= 0 ? "+" : ""}\$${_formatCash(netGain.abs())}',
                    color: netGain >= 0 ? Colors.amber : Colors.red,
                    bold: true,
                  ),

                  const SizedBox(height: 28),

                  // Service All button
                  GestureDetector(
                    onTap: _serviceAll,
                    child: Container(
                      width: 260,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.cyan.withValues(alpha: 0.7),
                            Colors.blue.withValues(alpha: 0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.cyan.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyan.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_fix_high,
                              color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'SERVICE ALL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Skip / Open Shop buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _closeSurfaceStation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            'SKIP',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _surfaceStationOpen = false;
                            _shopOpen = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.storefront,
                                color: Colors.amber,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'SHOP',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStationRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: bold ? 18 : 15,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

    if (_pauseOpen) {
      return _buildPauseMenu();
    }

    // Auto-detect surface landing and show station overlay
    _checkSurfaceLanding();

    if (_surfaceStationOpen) {
      return _buildSurfaceStation();
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
                      Vector2(
                          details.localPosition.dx, details.localPosition.dy),
                    );
                  },
                  onPanUpdate: (details) {
                    if (!widget.game.pod.isMounted) return;
                    widget.game.podController.handleTouchMove(
                      0,
                      Vector2(
                          details.localPosition.dx, details.localPosition.dy),
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
              // Virtual joystick overlay (non-interactive visual)
              IgnorePointer(child: _buildJoystickOverlay()),

              // Screen effects (non-interactive)
              IgnorePointer(child: _buildScreenEffects()),

              // GPU fallback warning with expandable error detail
              if (widget.game.usingCpuFallback)
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GPU SHADERS: CPU FALLBACK ACTIVE',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Background: ${widget.game.shaderBackground.shaderReady ? "OK (${widget.game.shaderBackground.compilationTimeMs}ms)" : widget.game.shaderBackground.shaderError ?? "unknown error"}',
                            style: TextStyle(
                              color: widget.game.shaderBackground.shaderReady
                                  ? Colors.green
                                  : Colors.red,
                              fontSize: 8,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Terrain: ${widget.game.shaderTerrainRenderer.shaderReady ? "OK (${widget.game.shaderTerrainRenderer.compilationTimeMs}ms)" : widget.game.shaderTerrainRenderer.shaderError ?? "unknown error"}',
                            style: TextStyle(
                              color:
                                  widget.game.shaderTerrainRenderer.shaderReady
                                      ? Colors.green
                                      : Colors.red,
                              fontSize: 8,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Top HUD strip (non-interactive)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(child: _buildTopStrip()),
              ),

              // Pause button (top-left, below safe area)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: GestureDetector(
                  onTap: _togglePause,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.pause,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 18,
                    ),
                  ),
                ),
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
                            gradient: const LinearGradient(
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

              // Depth milestone celebration toast
              if (_milestoneTitle != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 90,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _milestoneOpacity,
                      duration: const Duration(milliseconds: 600),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.9),
                                Colors.black.withValues(alpha: 0.9),
                                Colors.transparent,
                              ],
                            ),
                            border: Border(
                              top: BorderSide(
                                  color: Colors.yellowAccent
                                      .withValues(alpha: 0.8)),
                              bottom: BorderSide(
                                  color: Colors.yellowAccent
                                      .withValues(alpha: 0.8)),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'DEPTH RECORD',
                                style: TextStyle(
                                  color: Colors.yellowAccent
                                      .withValues(alpha: 0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 6,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _milestoneTitle!,
                                style: TextStyle(
                                  color: Colors.yellowAccent,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                  shadows: [
                                    Shadow(
                                      color: Colors.yellowAccent
                                          .withValues(alpha: 0.8),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _milestoneBonus!,
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  shadows: [
                                    Shadow(
                                      color: Colors.greenAccent
                                          .withValues(alpha: 0.6),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Bottom - Consumable buttons (tappable on mobile)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: _buildConsumableBar(),
              ),

              // Mini-map radar (bottom-left, only underground)
              if (widget.game.currentDepthFeet > 50)
                Positioned(
                  bottom: 56,
                  left: 10,
                  child: IgnorePointer(
                    child: _MiniMapWidget(game: widget.game),
                  ),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.amber.withValues(
                                  alpha: 0.15 + 0.1 * _pulseController.value),
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
                                color: Colors.amber.withValues(
                                    alpha: 0.5 * _pulseController.value),
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
      padding:
          EdgeInsets.only(top: safeTop + 4, bottom: 6, left: 16, right: 16),
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

  Widget _buildJoystickOverlay() {
    final controller = widget.game.podController;
    final origin = controller.joystickOrigin;
    final current = controller.joystickCurrent;
    if (origin == null || current == null) return const SizedBox.shrink();

    final mag = controller.joystickMagnitude;
    final opacity = (mag * 0.6 + 0.2).clamp(0.0, 0.8);

    return Stack(
      children: [
        // Outer ring (joystick base)
        Positioned(
          left: origin.x - 50,
          top: origin.y - 50,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: opacity * 0.3),
                width: 2,
              ),
            ),
          ),
        ),
        // Inner knob (current position, clamped to max radius)
        Positioned(
          left: current.x - 18,
          top: current.y - 18,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: opacity * 0.25),
              border: Border.all(
                color: Colors.white.withValues(alpha: opacity * 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: opacity * 0.2),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
        // Direction indicator (arrow or drill icon)
        if (mag > 0.1)
          Positioned(
            left: origin.x - 6,
            top: origin.y - 6,
            child: Icon(
              widget.game.pod.drillDown ? Icons.hardware : Icons.navigation,
              color: widget.game.pod.drillDown
                  ? Colors.orange.withValues(alpha: opacity)
                  : Colors.cyanAccent.withValues(alpha: opacity),
              size: 12,
            ),
          ),
      ],
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
    final glowIntensity =
        isLow ? _pulseController.value : _glowController.value * 0.3;

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
            const Icon(Icons.inventory_2, color: Colors.white54, size: 12),
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
          const Icon(
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
              Colors.orange
                  .withValues(alpha: 0.15 + 0.1 * _glowController.value),
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
        child: const Icon(Icons.storefront, color: Colors.amber, size: 20),
      ),
    );
  }

  Widget _buildConsumableBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildConsumableSlot(0, 'X', Icons.flash_on, widget.game.dynamiteCount,
            Colors.orange, SpecialItems.dynamite.spritePath),
        _buildConsumableSlot(
            1,
            'C',
            Icons.local_fire_department,
            widget.game.plasticExplosiveCount,
            Colors.red,
            SpecialItems.plasticExplosive.spritePath),
        _buildConsumableSlot(
            2,
            'F',
            Icons.local_gas_station,
            widget.game.reserveFuelCount,
            Colors.green,
            SpecialItems.reserveFuelTank.spritePath),
        _buildConsumableSlot(3, 'R', Icons.build, widget.game.nanobotCount,
            Colors.cyan, SpecialItems.hullRepairNanobots.spritePath),
        _buildConsumableSlot(4, 'Q', Icons.bolt, widget.game.teleporterCount,
            Colors.purple, SpecialItems.quantumTeleporter.spritePath),
        _buildConsumableSlot(5, 'M', Icons.star, widget.game.transmitterCount,
            Colors.amber, SpecialItems.matterTransmitter.spritePath),
      ],
    );
  }

  Widget _buildConsumableSlot(int index, String hotkey, IconData icon,
      int count, Color accentColor, String? spritePath) {
    final hasItem = count > 0;
    return GestureDetector(
      onTap:
          hasItem ? () => widget.game.podController.useConsumable(index) : null,
      child: Padding(
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
      ),
    );
  }

  List<Color> get _fuelGradientColors {
    final ratio = widget.game.fuelSystem.fuelRatio;
    if (ratio > 0.5) {
      return [Colors.green.shade900, Colors.green, Colors.greenAccent];
    }
    if (ratio > 0.25) {
      return [Colors.orange.shade900, Colors.yellow, Colors.yellowAccent];
    }
    return [Colors.red.shade900, Colors.red, Colors.redAccent];
  }

  List<Color> get _hullGradientColors {
    final ratio = widget.game.hullSystem.hullRatio;
    if (ratio > 0.5) {
      return [Colors.blue.shade900, Colors.cyan, Colors.cyanAccent];
    }
    if (ratio > 0.25) {
      return [Colors.orange.shade900, Colors.orange, Colors.orangeAccent];
    }
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
          color: fillRatio > 0.9
              ? Colors.red
              : Colors.white.withValues(alpha: 0.7),
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

// ---------------------------------------------------------------------------
// Mini-map radar widget
// ---------------------------------------------------------------------------

class _MiniMapWidget extends StatelessWidget {
  final MotherlodeGame game;
  static const double mapSize = 80;
  static const int sampleRadius = 40; // tiles around pod
  static const int sampleStep = 2; // sample every N tiles

  const _MiniMapWidget({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: mapSize,
      height: mapSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        color: Colors.black.withValues(alpha: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(
          size: const Size(mapSize, mapSize),
          painter: _MiniMapPainter(game: game),
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final MotherlodeGame game;

  _MiniMapPainter({required this.game});

  @override
  void paint(Canvas canvas, Size size) {
    if (!game.pod.isMounted) return;

    final podX = game.pod.position.x.round();
    final podY = game.pod.position.y.round();
    const radius = _MiniMapWidget.sampleRadius;
    const step = _MiniMapWidget.sampleStep;
    final pixPerTile = size.width / (radius * 2 / step);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int dy = -radius; dy < radius; dy += step) {
      for (int dx = -radius; dx < radius; dx += step) {
        final cellType = game.getCellType(podX + dx, podY + dy);

        Color color;
        switch (cellType) {
          case 0: // empty
            continue;
          case 1: // dirt
            color = const Color(0xFF443322);
          case 2: // rock
            color = const Color(0xFF555555);
          case 3: // sand
            color = const Color(0xFF776644);
          case 4: // obsidian
            color = const Color(0xFF2D1B3D);
          case 5: // lava
            color = const Color(0xFFFF4400);
          case 6: // gas
            color = const Color(0xFF224422);
          case 7: // ore
            color = const Color(0xFFFFD700);
          case 8: // bedrock
            color = const Color(0xFF222222);
          default:
            color = const Color(0xFF333333);
        }

        final px = (dx + radius) / step * pixPerTile;
        final py = (dy + radius) / step * pixPerTile;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(px, py, pixPerTile, pixPerTile),
          paint,
        );
      }
    }

    // Pod dot (center)
    final cx = size.width / 2;
    final cy = size.height / 2;
    paint.color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(cx, cy), 2.5, paint);

    // Surface direction arrow (if underground)
    if (podY > 2) {
      final arrowPaint = Paint()
        ..color = const Color(0xB300CCFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final arrowPath = Path()
        ..moveTo(cx - 4, 4)
        ..lineTo(cx, 1)
        ..lineTo(cx + 4, 4);
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) => true;
}
