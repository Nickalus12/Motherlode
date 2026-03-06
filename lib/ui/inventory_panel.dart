import 'package:flutter/material.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/entities/pod/cargo_system.dart';

/// Ore inventory listing with sell all functionality
class InventoryPanel extends StatefulWidget {
  final MotherlodeGame game;

  const InventoryPanel({super.key, required this.game});

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
                  'Total Value',
                  '\$${_formatCash(cargo.totalValue)}',
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
                      return _buildOreRow(item);
                    },
                  ),
          ),

          // Sell all button
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _lastSaleValue = cargo.totalValue;
                    final saleValue = cargo.sellAll();
                    widget.game.addCash(saleValue);
                    widget.game.pod.updateMass();
                    _justSold = true;
                  });
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) setState(() => _justSold = false);
                  });
                },
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
            fontSize: 9,
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

  Widget _buildOreRow(CargoItem item) {
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
                      child: Image.asset(
                          'assets/images/${item.ore.spritePath}'),
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

          // Value
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${_formatCash(item.totalValue)}',
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
              Text(
                '\$${item.ore.value}/ea',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}
