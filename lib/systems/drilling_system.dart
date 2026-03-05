import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';

/// Global drilling system that manages block removal, ore collection,
/// and resistance calculations across the world
///
/// Works in conjunction with the pod's DrillSystem component for
/// per-cell drilling, but handles world-level effects like:
/// - Mass terrain removal (explosions)
/// - Cascade effects
/// - Ore value tracking
class DrillingSystem extends Component with HasGameReference<MotherlodeGame> {
  /// Total ore value collected this run
  double totalOreValueCollected = 0;

  /// Total cells drilled this run
  int totalCellsDrilled = 0;

  /// Remove a rectangular area of cells (for explosions)
  void removeArea(int centerX, int centerY, int radius) {
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final gridX = centerX + dx;
        final gridY = centerY + dy;

        // Circular check
        if (dx * dx + dy * dy > radius * radius) continue;

        final cell = game.chunkManager.getTerrainCell(gridX, gridY);
        if (cell == null) continue;

        if (cell.isDrillable) {
          // Collect ore if present
          if (cell.type.index == 7 && cell.oreType != null) {
            // CellType.ore
            if (cell.oreType!.isSpecialCollectible) {
              game.addCash(cell.oreType!.value.toDouble());
            } else if (game.pod.cargoSystem.canAdd(
                cell.oreType!.weight.toDouble())) {
              game.pod.cargoSystem.addOre(cell.oreType!);
            }
            totalOreValueCollected += cell.oreType!.value;
          }

          game.removeTerrainCell(gridX, gridY);
          totalCellsDrilled++;
        }
      }
    }

    // Trigger collapse checks around the perimeter
    game.earthquakeSystem.checkCollapseArea(centerX, centerY, radius + 2);
  }

  /// Get the current value of all cargo
  double get currentCargoValue {
    return game.pod.cargoSystem.totalValue;
  }

  /// Serialize
  Map<String, dynamic> toMap() {
    return {
      'totalOreValue': totalOreValueCollected,
      'totalDrilled': totalCellsDrilled,
    };
  }
}
