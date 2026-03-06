import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Drilling logic using SDF sphere subtraction for smooth terrain removal.
///
/// Pod must be grounded to drill down. Drill direction is DOWN only
/// (faithful to original Motherload). When a cell is fully drilled,
/// an SDF sphere subtraction is applied to carve a smooth round hole.
class DrillSystem extends Component {
  final Pod pod;
  final MotherlodeGame game;

  double _currentCellProgress = 0;
  int? _targetGridX;
  int? _targetGridY;

  /// Base radius of the drill carve in grid units (level 0).
  static const double _baseRadius = 1.0;

  /// Additional radius per drill upgrade level.
  static const double _radiusPerLevel = 0.15;

  /// Smoothing factor for SDF subtraction (larger = rounder edges)
  static const double _drillSmoothing = 0.3;

  /// Current drill radius, scaling with the game's drill upgrade level.
  double get _drillRadius => _baseRadius + game.drillLevel * _radiusPerLevel;

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

  /// Remove a drilled cell using SDF sphere subtraction and collect any ore.
  ///
  /// Delegates terrain carving to [ChunkManager.drillAtWorld] which handles
  /// cross-chunk SDF subtraction and dirty marking. Ore collection is
  /// checked on the target cell before carving, and on any newly-exposed
  /// ore cells after carving.
  void _removeCell(int gridX, int gridY, TerrainCell cell) {
    // Collect ore from the target cell before carving
    if (cell.type == CellType.ore && cell.oreType != null) {
      if (!_collectOre(gridX, gridY, cell)) return; // Cargo full
    }

    // Carve smooth round hole via centralized SDF drill on ChunkManager
    final modified = game.chunkManager.drillAtWorld(
      gridX.toDouble(),
      gridY.toDouble(),
      _drillRadius,
      smoothK: _drillSmoothing,
    );

    // Collect ore from any cells that were newly cleared by the carve
    for (final (gx, gy, modifiedCell) in modified) {
      if (gx == gridX && gy == gridY) continue; // Already collected above
      if (modifiedCell.type == CellType.empty &&
          modifiedCell.oreType != null) {
        // Cell was ore but got carved to empty — ore is lost (destroyed)
        modifiedCell.oreType = null;
      }
    }

    // Trigger collapse check in surrounding area
    game.earthquakeSystem.checkCollapse(gridX, gridY);
  }

  /// Try to collect ore from a cell. Returns false if cargo is full.
  bool _collectOre(int gridX, int gridY, TerrainCell cell) {
    final ore = cell.oreType!;

    if (ore.isSpecialCollectible) {
      game.addCash(ore.value.toDouble());
      final pos = Vector2(gridX.toDouble(), gridY.toDouble());
      game.particleSystem.emitOreSparkle(pos, ore.color);
      game.particleSystem.emitOrePickup(pos, ore.color, ore.spritePath);
      return true;
    }

    if (pod.cargoSystem.canAdd(ore.weight.toDouble())) {
      pod.cargoSystem.addOre(ore);
      final pos = Vector2(gridX.toDouble(), gridY.toDouble());
      game.particleSystem.emitOreSparkle(pos, ore.color);
      game.particleSystem.emitOrePickup(pos, ore.color, ore.spritePath);
      pod.updateMass();
      return true;
    }

    return false; // Cargo full
  }

  /// Get drill progress as 0.0 to 1.0
  double get drillProgress => _currentCellProgress / 100.0;

  /// Whether actively drilling a cell
  bool get isDrilling => _targetGridX != null;
}
