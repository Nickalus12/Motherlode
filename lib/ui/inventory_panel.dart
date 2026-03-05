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

  @override
  Widget build(BuildContext context) {
    final cargo = widget.game.pod.cargoSystem;
    final items = cargo.getCargoBreakdown();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          const Text(
            'MINERAL PROCESSOR 3000',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Load your minerals for instant processing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),

          // Cargo summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryItem(
                  'Weight',
                  '${cargo.currentWeight.toStringAsFixed(0)} kg',
                  Colors.white70,
                ),
                _buildSummaryItem(
                  'Items',
                  '${items.length} types',
                  Colors.white70,
                ),
                _buildSummaryItem(
                  'Total Value',
                  '\$${_formatCash(cargo.totalValue)}',
                  Colors.amber,
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
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _justSold
                              ? 'Sold \$${_formatCash(_lastSaleValue)}!'
                              : 'Cargo bay empty',
                          style: TextStyle(
                            color: _justSold
                                ? Colors.green
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 16,
                            fontWeight:
                                _justSold ? FontWeight.bold : FontWeight.normal,
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
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _lastSaleValue = cargo.totalValue;
                    final saleValue = cargo.sellAll();
                    widget.game.addCash(saleValue);
                    widget.game.pod.podBody.updateMass();
                    _justSold = true;
                  });
                  // Reset notification after delay
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) setState(() => _justSold = false);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  'SELL ALL — \$${_formatCash(cargo.totalValue)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildOreRow(CargoItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Color swatch
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: item.ore.color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: item.ore.glowColor,
                  blurRadius: 4,
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
                Text(
                  '${item.count}x  •  ${item.totalWeight.toInt()} kg',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
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
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '\$${item.ore.value}/ea',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
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
