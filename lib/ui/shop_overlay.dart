import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:motherlode/data/special_items.dart';
import 'package:motherlode/data/upgrade_definitions.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/ui/inventory_panel.dart';
import 'package:motherlode/ui/upgrade_tree.dart';
import 'package:motherlode/ui/upgrade_visuals.dart';

/// Surface shop overlay with fuel station, mineral processor,
/// upgrade shop, and consumables store
class ShopOverlay extends StatefulWidget {
  final MotherlodeGame game;
  final VoidCallback onClose;

  const ShopOverlay({
    super.key,
    required this.game,
    required this.onClose,
  });

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  static const _bgColor = Color(0xFF0D0D12);
  static const _surfaceColor = Color(0xFF16161E);
  static const _cardColor = Color(0xFF1C1C28);
  static const _accentAmber = Color(0xFFF5A623);
  static const _borderColor = Color(0xFF2A2A3A);

  // Cash rolling animation
  double _displayCash = 0;
  double _targetCash = 0;
  late final AnimationController _cashAnimController;

  // Purchase flash animation
  String? _flashItemKey;
  late final AnimationController _flashController;

  // "SOLD!" pop animation
  late final AnimationController _soldPopController;
  bool _showSoldPop = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _displayCash = widget.game.playerCash;
    _targetCash = widget.game.playerCash;

    _cashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        setState(() {
          _displayCash = _displayCash +
              (_targetCash - _displayCash) * _cashAnimController.value;
        });
      });

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _soldPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _showSoldPop = false);
        }
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cashAnimController.dispose();
    _flashController.dispose();
    _soldPopController.dispose();
    super.dispose();
  }

  void _animateCashChange() {
    _targetCash = widget.game.playerCash;
    _cashAnimController.forward(from: 0);
  }

  void _triggerPurchaseFlash(String itemKey) {
    _flashItemKey = itemKey;
    _flashController.forward(from: 0);
    HapticFeedback.lightImpact();
  }

  void _triggerSoldPop() {
    _showSoldPop = true;
    _soldPopController.forward(from: 0);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bgColor,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFuelStation(),
                  _buildMineralProcessor(),
                  UpgradeTreePanel(game: widget.game),
                  _buildConsumablesShop(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: const Border(
          bottom: BorderSide(color: _borderColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Cash display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accentAmber.withValues(alpha: 0.15),
                  _accentAmber.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accentAmber.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on,
                    color: _accentAmber, size: 18),
                const SizedBox(width: 6),
                Text(
                  '\$${_formatCash(_displayCash)}',
                  style: TextStyle(
                    color: _displayCash != _targetCash
                        ? Colors.white
                        : _accentAmber,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: _accentAmber.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Close button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _surfaceColor,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _accentAmber,
        indicatorWeight: 3,
        labelColor: _accentAmber,
        unselectedLabelColor: Colors.white38,
        dividerColor: _borderColor,
        labelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.local_gas_station, size: 24)),
          Tab(icon: Icon(Icons.attach_money, size: 24)),
          Tab(icon: Icon(Icons.arrow_upward, size: 24)),
          Tab(icon: Icon(Icons.inventory_2, size: 24)),
        ],
      ),
    );
  }

  Widget _buildFuelStation() {
    final fuelSystem = widget.game.fuelSystem;
    final needed = fuelSystem.maxFuel - fuelSystem.currentFuel;
    final cost = needed * 10;
    final fuelPercent =
        (fuelSystem.currentFuel / fuelSystem.maxFuel * 100).toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Animated fuel gauge visual
          FuelTankVisual(
            level: widget.game.fuelTankLevel,
            maxLevel: UpgradeDefinitions.fuelTanks.maxLevel,
            fillPercent:
                (fuelSystem.currentFuel / fuelSystem.maxFuel).clamp(0.0, 1.0),
          ),
          const SizedBox(height: 12),

          Text(
            'FUEL STATION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              shadows: [
                Shadow(
                  color: Colors.green.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Fuel level bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Fuel Level',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13),
                    ),
                    Text(
                      '$fuelPercent%',
                      style: TextStyle(
                        color: fuelPercent > 50 ? Colors.green : Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 12,
                    child: LinearProgressIndicator(
                      value: fuelSystem.currentFuel / fuelSystem.maxFuel,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        fuelPercent > 50 ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${fuelSystem.currentFuel.toStringAsFixed(1)}L / '
                  '${fuelSystem.maxFuel.toStringAsFixed(1)}L',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Fill button
          if (needed > 0.1)
            SizedBox(
              width: double.infinity,
              child: _buildActionButton(
                label: 'FILL TANK',
                cost: '\$${cost.toStringAsFixed(0)}',
                color: Colors.green,
                onPressed: () => _confirmPurchase(
                  context,
                  'Fill Fuel Tank',
                  'Fill tank for \$${cost.toStringAsFixed(0)}?',
                  cost,
                  () {
                    setState(() {
                      fuelSystem.addFuel(needed);
                    });
                  },
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Text(
                'TANK FULL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(
                      color: Colors.green.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),
          Text(
            '\$10 per liter',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMineralProcessor() {
    final boom = widget.game.marketSystem.activeBoom;
    return Column(
      children: [
        if (boom != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withValues(alpha: 0.2),
                  Colors.amber.withValues(alpha: 0.1),
                  Colors.orange.withValues(alpha: 0.2),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.trending_up,
                    color: Colors.orangeAccent, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${boom.oreName} BOOM  ${boom.multiplier}x  '
                  '${boom.remainingSeconds.toInt()}s',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              InventoryPanel(
                game: widget.game,
                onSold: () {
                  _triggerSoldPop();
                  _animateCashChange();
                },
              ),
              // "SOLD!" pop overlay
              if (_showSoldPop)
                Center(
                  child: AnimatedBuilder(
                    animation: _soldPopController,
                    builder: (context, _) {
                      final t = _soldPopController.value;
                      final scale = 0.5 + t * 1.5;
                      final opacity = t < 0.5 ? 1.0 : (1.0 - (t - 0.5) * 2.0);
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Text(
                            'SOLD!',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: Colors.green.withValues(alpha: 0.6),
                                  blurRadius: 12,
                                ),
                                const Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConsumablesShop() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'SUPPLIES',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              shadows: [
                Shadow(
                  color: _accentAmber.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        _buildConsumableItem(
          SpecialItems.reserveFuelTank,
          widget.game.reserveFuelCount,
          Icons.local_gas_station,
          Colors.green,
          () => _buyConsumable(context, SpecialItems.reserveFuelTank,
              () => widget.game.reserveFuelCount++),
        ),
        _buildConsumableItem(
          SpecialItems.hullRepairNanobots,
          widget.game.nanobotCount,
          Icons.build,
          Colors.cyan,
          () => _buyConsumable(context, SpecialItems.hullRepairNanobots,
              () => widget.game.nanobotCount++),
        ),
        _buildConsumableItem(
          SpecialItems.dynamite,
          widget.game.dynamiteCount,
          Icons.flash_on,
          Colors.orange,
          () => _buyConsumable(context, SpecialItems.dynamite,
              () => widget.game.dynamiteCount++),
        ),
        _buildConsumableItem(
          SpecialItems.plasticExplosive,
          widget.game.plasticExplosiveCount,
          Icons.local_fire_department,
          Colors.red,
          () => _buyConsumable(context, SpecialItems.plasticExplosive,
              () => widget.game.plasticExplosiveCount++),
        ),
        _buildConsumableItem(
          SpecialItems.quantumTeleporter,
          widget.game.teleporterCount,
          Icons.bolt,
          Colors.purple,
          () => _buyConsumable(context, SpecialItems.quantumTeleporter,
              () => widget.game.teleporterCount++),
        ),
        _buildConsumableItem(
          SpecialItems.matterTransmitter,
          widget.game.transmitterCount,
          Icons.star,
          Colors.amber,
          () => _buyConsumable(context, SpecialItems.matterTransmitter,
              () => widget.game.transmitterCount++),
        ),
        _buildConsumableItem(
          SpecialItems.supportBeam,
          widget.game.supportBeamCount,
          Icons.view_column,
          Colors.brown,
          () => _buyConsumable(context, SpecialItems.supportBeam,
              () => widget.game.supportBeamCount++),
        ),
        _buildConsumableItem(
          SpecialItems.flare,
          widget.game.flareCount,
          Icons.flare,
          Colors.yellow,
          () => _buyConsumable(
              context, SpecialItems.flare, () => widget.game.flareCount++),
        ),
      ],
    );
  }

  Widget _buildConsumableItem(
    ConsumableItem item,
    int currentCount,
    IconData icon,
    Color accentColor,
    VoidCallback onBuy,
  ) {
    final canAfford = widget.game.playerCash >= item.cost;
    final isFlashing = _flashItemKey == item.name;
    return AnimatedBuilder(
      animation: _flashController,
      builder: (context, child) {
        final flashValue = isFlashing ? (1.0 - _flashController.value) : 0.0;
        final scaleValue =
            isFlashing ? 1.0 + 0.05 * (1.0 - _flashController.value) : 1.0;
        return Transform.scale(
          scale: scaleValue,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.lerp(_cardColor, Colors.green, flashValue * 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: flashValue > 0
                    ? Colors.green.withValues(alpha: 0.5 + flashValue * 0.5)
                    : (canAfford
                        ? accentColor.withValues(alpha: 0.2)
                        : _borderColor),
              ),
              boxShadow: flashValue > 0
                  ? [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: flashValue * 0.3),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Icon or sprite
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor.withValues(alpha: 0.2),
                        accentColor.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: item.spritePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/images/${item.spritePath}',
                            width: 30,
                            height: 30,
                            fit: BoxFit.contain,
                          ),
                        )
                      : Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'Owned: $currentCount',
                            style: TextStyle(
                              color: accentColor.withValues(alpha: 0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Buy button
                _buildSmallBuyButton(
                  cost: '\$${item.cost}',
                  canAfford: canAfford,
                  onPressed: canAfford ? onBuy : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSmallBuyButton({
    required String cost,
    required bool canAfford,
    VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: canAfford
              ? LinearGradient(colors: [
                  Colors.green.shade800,
                  Colors.green.shade700,
                ])
              : null,
          color: canAfford ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: canAfford
                ? Colors.green.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: canAfford
              ? [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.2),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.add_shopping_cart,
          color: canAfford ? Colors.white : Colors.white38,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required String cost,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.8),
              color.withValues(alpha: 0.6),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.local_gas_station,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  /// Show confirmation dialog for purchases over $1000, or buy directly.
  Future<void> _confirmPurchase(
    BuildContext context,
    String title,
    String message,
    double cost,
    VoidCallback onConfirmed,
  ) async {
    if (cost >= 1000) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C28),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('BUY',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (widget.game.spendCash(cost)) {
      setState(onConfirmed);
      _animateCashChange();
      HapticFeedback.lightImpact();
    }
  }

  /// Buy a consumable item with confirmation for expensive ones.
  void _buyConsumable(
      BuildContext context, ConsumableItem item, VoidCallback applyPurchase) {
    _confirmPurchase(
      context,
      'Buy ${item.name}?',
      'Purchase ${item.name} for \$${item.cost}?',
      item.cost.toDouble(),
      () {
        applyPurchase();
        _triggerPurchaseFlash(item.name);
      },
    );
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}
