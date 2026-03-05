import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Drilling logic: cell removal, speed calculation, material resistance
///
/// Pod must be grounded to drill down. Drill direction is DOWN only
/// (faithful to original Motherload). Each drill tick removes one cell
/// from terrain, triggers collapse check, and may collect ore.
class DrillSystem extends Component {
  final Pod pod;
  final MotherlodeGame game;

  double _drillTimer = 0;
  double _currentCellProgress = 0;
  int? _targetGridX;
  int? _targetGridY;

  DrillSystem({required this.pod, required this.game});

  /// Process one drill tick
  void drill(double dt) {
    if (!pod.podBody.isGrounded) return;

    // Find the cell directly below the pod
    final podX = pod.position.x;
    final podY = pod.position.y;

    // Convert pod position to grid coordinates
    final gridX = podX.round();
    final gridY = (podY + 1.2).round(); // Below the pod

    // Check if target cell exists and is drillable
    final cell = game.chunkManager.getTerrainCell(gridX, gridY);
    if (cell == null || !cell.isDrillable) return;

    // Track target for progress
    if (_targetGridX != gridX || _targetGridY != gridY) {
      _targetGridX = gridX;
      _targetGridY = gridY;
      _currentCellProgress = 0;
    }

    // Calculate drill speed based on drill level and material hardness
    final drillRate = pod.drillSpeed / cell.hardness;
    _currentCellProgress += drillRate * dt;

    // Check if cell is fully drilled
    if (_currentCellProgress >= 100.0) {
      _removeCell(gridX, gridY, cell);
      _currentCellProgress = 0;
      _targetGridX = null;
      _targetGridY = null;
    }

    // Emit drill particles
    game.particleSystem.emitDrillParticles(
      Vector2(podX, podY + 1.2),
      cell.baseColor,
    );

    // Consume extra fuel while drilling
    game.fuelSystem.consumeFuel(GameConstants.fuelConsumptionDrill * dt);
  }

  /// Remove a drilled cell and collect any ore
  void _removeCell(int gridX, int gridY, TerrainCell cell) {
    // Collect ore if present
    if (cell.type == CellType.ore && cell.oreType != null) {
      final ore = cell.oreType!;

      if (ore.isSpecialCollectible) {
        // Special collectibles give immediate cash, no cargo space needed
        game.addCash(ore.value.toDouble());
        game.particleSystem.emitOreSparkle(
          Vector2(gridX.toDouble(), gridY.toDouble()),
          ore.color,
        );
      } else {
        // Standard ore: add to cargo if space available
        if (pod.cargoSystem.canAdd(ore.weight.toDouble())) {
          pod.cargoSystem.addOre(ore);
          game.particleSystem.emitOreSparkle(
            Vector2(gridX.toDouble(), gridY.toDouble()),
            ore.color,
          );
          // Update pod mass (heavier with cargo)
          pod.podBody.updateMass();
        }
        // If no space, ore is left in ground (cell not removed)
        else {
          return; // Don't remove the cell
        }
      }
    }

    // Remove the terrain cell
    game.removeTerrainCell(gridX, gridY);

    // Trigger collapse check in surrounding area
    game.earthquakeSystem.checkCollapse(gridX, gridY);
  }

  /// Get drill progress as 0.0 to 1.0
  double get drillProgress => _currentCellProgress / 100.0;

  /// Whether actively drilling a cell
  bool get isDrilling => _targetGridX != null;
}
