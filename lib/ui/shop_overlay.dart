import 'package:flutter/material.dart';

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
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _bgColor = Color(0xFF0D0D12);
  static const _surfaceColor = Color(0xFF16161E);
  static const _cardColor = Color(0xFF1C1C28);
  static const _accentAmber = Color(0xFFF5A623);
  static const _borderColor = Color(0xFF2A2A3A);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        border: Border(
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
                Icon(Icons.monetization_on, color: _accentAmber, size: 18),
                const SizedBox(width: 6),
                Text(
                  '\$${_formatCash(widget.game.playerCash)}',
                  style: TextStyle(
                    color: _accentAmber,
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
    final fuelPercent = (fuelSystem.currentFuel / fuelSystem.maxFuel * 100).toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Animated fuel gauge visual
          FuelTankVisual(
            level: widget.game.fuelTankLevel,
            maxLevel: UpgradeDefinitions.fuelTanks.maxLevel,
            fillPercent: (fuelSystem.currentFuel / fuelSystem.maxFuel)
                .clamp(0.0, 1.0),
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
                          color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
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
                onPressed: () {
                  if (widget.game.spendCash(cost)) {
                    setState(() {
                      fuelSystem.addFuel(needed);
                    });
                  }
                },
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
    return InventoryPanel(game: widget.game);
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
          () {
            if (widget.game.spendCash(SpecialItems.reserveFuelTank.cost.toDouble())) {
              setState(() => widget.game.reserveFuelCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.hullRepairNanobots,
          widget.game.nanobotCount,
          Icons.build,
          Colors.cyan,
          () {
            if (widget.game.spendCash(SpecialItems.hullRepairNanobots.cost.toDouble())) {
              setState(() => widget.game.nanobotCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.dynamite,
          widget.game.dynamiteCount,
          Icons.flash_on,
          Colors.orange,
          () {
            if (widget.game.spendCash(SpecialItems.dynamite.cost.toDouble())) {
              setState(() => widget.game.dynamiteCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.plasticExplosive,
          widget.game.plasticExplosiveCount,
          Icons.local_fire_department,
          Colors.red,
          () {
            if (widget.game.spendCash(SpecialItems.plasticExplosive.cost.toDouble())) {
              setState(() => widget.game.plasticExplosiveCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.quantumTeleporter,
          widget.game.teleporterCount,
          Icons.bolt,
          Colors.purple,
          () {
            if (widget.game.spendCash(SpecialItems.quantumTeleporter.cost.toDouble())) {
              setState(() => widget.game.teleporterCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.matterTransmitter,
          widget.game.transmitterCount,
          Icons.star,
          Colors.amber,
          () {
            if (widget.game.spendCash(SpecialItems.matterTransmitter.cost.toDouble())) {
              setState(() => widget.game.transmitterCount++);
            }
          },
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canAfford
              ? accentColor.withValues(alpha: 0.2)
              : _borderColor,
        ),
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
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
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
        child: Icon(
          Icons.local_gas_station,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}
