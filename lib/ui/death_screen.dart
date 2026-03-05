import 'package:flutter/material.dart';

import 'package:motherlode/motherlode_game.dart';

/// Game over screen showing depth reached, ore value, and stats
class DeathScreen extends StatelessWidget {
  final MotherlodeGame game;
  final VoidCallback onRetry;
  final VoidCallback onMainMenu;

  const DeathScreen({
    super.key,
    required this.game,
    required this.onRetry,
    required this.onMainMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Skull icon (text-based)
            const Text(
              '☠',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),

            const Text(
              'DRILL DESTROYED',
              style: TextStyle(
                color: Colors.red,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'Your pod was lost at ${game.depthSystem.maxDepthReached.toStringAsFixed(0)} ft',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 32),

            // Stats container
            Container(
              width: 280,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  _buildStatRow(
                    'Max Depth',
                    '${game.depthSystem.maxDepthReached.toStringAsFixed(0)} ft',
                    Colors.cyan,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    'Cash Earned',
                    '\$${_formatCash(game.playerCash)}',
                    Colors.amber,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    'Cargo Lost',
                    '\$${_formatCash(game.pod.cargoSystem.totalValue)}',
                    Colors.red,
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow(
                    'Biome Reached',
                    game.depthSystem.currentBiomeName,
                    Colors.green,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Retry button
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text(
                'TRY AGAIN',
                style: TextStyle(
                  fontSize: 18,
                  letterSpacing: 3,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 16),

            TextButton(
              onPressed: onMainMenu,
              child: Text(
                'MAIN MENU',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatCash(double cash) {
    if (cash >= 1000000) return '${(cash / 1000000).toStringAsFixed(1)}M';
    if (cash >= 1000) return '${(cash / 1000).toStringAsFixed(1)}K';
    return cash.toStringAsFixed(0);
  }
}
