import 'package:flutter/material.dart';

import 'package:motherlode/entities/pod/cargo_system.dart';
import 'package:motherlode/motherlode_game.dart';

/// Ore inventory listing with sell all functionality
class InventoryPanel extends StatefulWidget {
  final MotherlodeGame game;
  final VoidCallback? onSold;

  const InventoryPanel({super.key, required this.game, this.onSold});

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends State<InventoryPanel> {
  bool _justSold = false;
  double _lastSaleValue = 0;

  static const _cardColor = Color(0xFF1C1C28);
  static const _borderColor = Color(0xFF2A2A3A);

  @override
  Widget build(BuildContext context) {
    final cargo = widget.game.pod.cargoSystem;
    final items = cargo.getCargoBreakdown();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header with mineral processor image
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.amber.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                radius: 0.8,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/buildings/mineral_processor.png',
                height: 90,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MINERAL PROCESSOR 3000',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
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
          const SizedBox(height: 3),
          Text(
            'Load your minerals for instant processing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),

          // Cargo summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryItem(
                  'Weight',
                  '${cargo.currentWeight.toStringAsFixed(0)} kg',
                  Colors.white60,
                  Icons.scale,
                ),
                Container(width: 1, height: 30, color: _borderColor),
                _buildSummaryItem(
                  'Items',
                  '${items.length} types',
                  Colors.white60,
                  Icons.layers,
                ),
                Container(width: 1, height: 30, color: _borderColor),
                _buildSummaryItem(
                  'Market Value',
                  '\$${_formatCash(_marketTotalValue())}',
                  Colors.amber,
                  Icons.monetization_on,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Ore list
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _justSold
                              ? Icons.check_circle_outline
                              : Icons.inventory_2_outlined,
                          size: 48,
                          color: _justSold
                              ? Colors.green.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _justSold
                              ? 'Sold \$${_formatCash(_lastSaleValue)}!'
                              : 'Cargo bay empty',
                          style: TextStyle(
                            color: _justSold
                                ? Colors.green
                                : Colors.white.withValues(alpha: 0.3),
                            fontSize: 15,
                            fontWeight:
                                _justSold ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (_justSold)
                          Text(
                            'Minerals processed successfully',
                            style: TextStyle(
                              color: Colors.green.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildOreRow(item, context);
                    },
                  ),
          ),

          // Sell all button
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => _confirmSellAll(context, cargo),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade800,
                        Colors.orange.shade700,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.sell,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, Color valueColor, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: valueColor.withValues(alpha: 0.5), size: 14),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Calculate total market-adjusted value of all cargo.
  double _marketTotalValue() {
    final market = widget.game.marketSystem;
    final items = widget.game.pod.cargoSystem.getCargoBreakdown();
    double total = 0;
    for (final item in items) {
      total += market.calculateSaleValue(item.ore, item.count);
    }
    return total;
  }

  Future<void> _confirmSellAll(BuildContext context, CargoSystem cargo) async {
    final totalValue = _marketTotalValue();
    final itemCount = cargo.getCargoBreakdown().length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C28),
        title: const Text('Sell All Minerals?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Process $itemCount ore types for \$${_formatCash(totalValue)}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SELL ALL',
                style: TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _lastSaleValue = totalValue;
        final market = widget.game.marketSystem;
        // Calculate market-adjusted value per ore and record sales
        double saleValue = 0;
        for (final item in cargo.getCargoBreakdown()) {
          saleValue += market.calculateSaleValue(item.ore, item.count);
          market.recordSale(item.ore.name, item.count);
        }
        cargo.sellAll(); // Clear cargo
        widget.game.addCash(saleValue);
        widget.game.pod.updateMass();
        widget.game.audioManager.playSell();
        _justSold = true;
      });
      widget.onSold?.call();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _justSold = false);
      });
    }
  }

  void _sellSingleOre(BuildContext context, CargoItem item) async {
    final market = widget.game.marketSystem;
    final marketValue = market.calculateSaleValue(item.ore, item.count);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C28),
        title: Text('Sell ${item.ore.name}?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'Sell ${item.count}x ${item.ore.name} for \$${_formatCash(marketValue)}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SELL',
                style: TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        widget.game.pod.cargoSystem.sellOre(item.ore.name);
        market.recordSale(item.ore.name, item.count);
        widget.game.addCash(marketValue);
        widget.game.pod.updateMass();
        widget.game.audioManager.playSell();
      });
      widget.onSold?.call();
    }
  }

  Widget _buildOreRow(CargoItem item, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          // Ore sprite thumbnail (or color swatch fallback)
          if (item.ore.spritePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: item.ore.color.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: item.ore.glowColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    alignment: Alignment.topLeft,
                    clipBehavior: Clip.hardEdge,
                    child: Align(
                      alignment: Alignment.topLeft,
                      widthFactor: 0.25,
                      heightFactor: 0.25,
                      child:
                          Image.asset('assets/images/${item.ore.spritePath}'),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: item.ore.color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: item.ore.color.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: item.ore.glowColor.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),

          // Name and count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.ore.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${item.count}x  ${item.totalWeight.toInt()} kg',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Value with market multiplier
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${_formatCash(widget.game.marketSystem.calculateSaleValue(item.ore, item.count))}',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.amber.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              _buildMultiplierLabel(item),
            ],
          ),
          const SizedBox(width: 8),

          // Per-ore sell button
          GestureDetector(
            onTap: () => _sellSingleOre(context, item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.shade800.withValues(alpha: 0.8),
                    Colors.orange.shade700.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(Icons.sell, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiplierLabel(CargoItem item) {
    final market = widget.game.marketSystem;
    final mult = market.getMultiplier(item.ore.name);
    final isBoom = market.isBoomActive(item.ore.name);
    final hasCombo = market.hasComboBonus(item.count);

    final Color color;
    if (isBoom) {
      color = Colors.orangeAccent;
    } else if (mult > 1.0) {
      color = Colors.greenAccent;
    } else if (mult < 1.0) {
      color = Colors.redAccent;
    } else {
      color = Colors.white.withValues(alpha: 0.3);
    }

    final label = StringBuffer('${mult.toStringAsFixed(2)}x');
    if (isBoom) label.write(' BOOM');
    if (hasCombo) label.write(' +15%');

    return Text(
      label.toString(),
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: isBoom ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}
