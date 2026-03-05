import 'package:flutter/material.dart';

import 'package:motherlode/data/special_items.dart';
import 'package:motherlode/data/upgrade_definitions.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/ui/inventory_panel.dart';
import 'package:motherlode/ui/upgrade_tree.dart';

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
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            // Header with cash and close button
            _buildHeader(),

            // Tab bar
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'FUEL', icon: Icon(Icons.local_gas_station, size: 18)),
                Tab(text: 'SELL', icon: Icon(Icons.attach_money, size: 18)),
                Tab(text: 'UPGRADE', icon: Icon(Icons.arrow_upward, size: 18)),
                Tab(text: 'ITEMS', icon: Icon(Icons.inventory_2, size: 18)),
              ],
            ),

            // Tab content
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '\$${_formatCash(widget.game.playerCash)}',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// Fuel station - fill tank
  Widget _buildFuelStation() {
    final fuelSystem = widget.game.fuelSystem;
    final needed = fuelSystem.maxFuel - fuelSystem.currentFuel;
    final cost = needed * 10; // $10 per liter

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_gas_station, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            'FUEL STATION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Current: ${fuelSystem.currentFuel.toStringAsFixed(1)}L / '
            '${fuelSystem.maxFuel.toStringAsFixed(1)}L',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Need: ${needed.toStringAsFixed(1)}L',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Fill tank button
          if (needed > 0.1)
            ElevatedButton(
              onPressed: () {
                if (widget.game.spendCash(cost)) {
                  setState(() {
                    fuelSystem.addFuel(needed);
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade800,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: Text(
                'FILL TANK — \$${cost.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            )
          else
            const Text(
              'TANK FULL',
              style: TextStyle(
                color: Colors.green,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

          const SizedBox(height: 8),
          Text(
            '\$10 per liter',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Mineral processor - sell all ore
  Widget _buildMineralProcessor() {
    return InventoryPanel(game: widget.game);
  }

  /// Consumables shop
  Widget _buildConsumablesShop() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'SUPPLIES',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        _buildConsumableItem(
          SpecialItems.reserveFuelTank,
          widget.game.reserveFuelCount,
          () {
            if (widget.game.spendCash(SpecialItems.reserveFuelTank.cost.toDouble())) {
              setState(() => widget.game.reserveFuelCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.hullRepairNanobots,
          widget.game.nanobotCount,
          () {
            if (widget.game.spendCash(SpecialItems.hullRepairNanobots.cost.toDouble())) {
              setState(() => widget.game.nanobotCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.dynamite,
          widget.game.dynamiteCount,
          () {
            if (widget.game.spendCash(SpecialItems.dynamite.cost.toDouble())) {
              setState(() => widget.game.dynamiteCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.plasticExplosive,
          widget.game.plasticExplosiveCount,
          () {
            if (widget.game.spendCash(SpecialItems.plasticExplosive.cost.toDouble())) {
              setState(() => widget.game.plasticExplosiveCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.quantumTeleporter,
          widget.game.teleporterCount,
          () {
            if (widget.game.spendCash(SpecialItems.quantumTeleporter.cost.toDouble())) {
              setState(() => widget.game.teleporterCount++);
            }
          },
        ),
        _buildConsumableItem(
          SpecialItems.matterTransmitter,
          widget.game.transmitterCount,
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
    VoidCallback onBuy,
  ) {
    final canAfford = widget.game.playerCash >= item.cost;
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(item.icon, style: const TextStyle(fontSize: 28)),
        title: Text(
          item.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${item.description}\nOwned: $currentCount  |  Hotkey: [${item.hotkey}]',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
        ),
        trailing: ElevatedButton(
          onPressed: canAfford ? onBuy : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canAfford ? Colors.green.shade800 : Colors.grey.shade800,
          ),
          child: Text(
            '\$${item.cost}',
            style: const TextStyle(color: Colors.white),
          ),
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
