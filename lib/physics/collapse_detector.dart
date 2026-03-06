import 'dart:ui';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Checks structural integrity of terrain after mining operations
///
/// After any cell is removed:
/// 1. Check all cells in a 5-cell radius for structural support
/// 2. A cell is "supported" if it has a solid cell directly below
///    OR has 3+ solid orthogonal neighbors
/// 3. Unsupported cells become DebrisBody (dynamic Forge2D bodies)
/// 4. Sand/gravel layer (surface to 200ft) ALWAYS collapses
class CollapseDetector {
  final MotherlodeGame game;

  CollapseDetector({required this.game});

  /// Check for collapse around a removed cell
  /// Returns list of cells that should collapse
  List<CollapseCell> checkCollapse(int centerX, int centerY) {
    final collapseCells = <CollapseCell>[];
    const radius = GameConstants.collapseCheckRadius;

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = centerX + dx;
        final y = centerY + dy;

        final cell = game.chunkManager.getTerrainCell(x, y);
        if (cell == null || !cell.isSolid) continue;

        // Sand/gravel always collapses if unsupported below
        if (cell.alwaysCollapses) {
          final below = game.chunkManager.getTerrainCell(x, y + 1);
          if (below == null || !below.isSolid) {
            collapseCells.add(CollapseCell(
              gridX: x,
              gridY: y,
              cellType: cell.type,
              density: cell.density,
              color: cell.baseColor,
            ));
          }
          continue;
        }

        // Check structural support
        if (!_isSupported(x, y)) {
          collapseCells.add(CollapseCell(
            gridX: x,
            gridY: y,
            cellType: cell.type,
            density: cell.density,
            color: cell.baseColor,
          ));
        }
      }
    }

    return collapseCells;
  }

  /// Check for collapse in a larger area (after explosion)
  List<CollapseCell> checkCollapseArea(int centerX, int centerY, int radius) {
    final collapseCells = <CollapseCell>[];

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        // Circular check
        if (dx * dx + dy * dy > radius * radius) continue;

        final x = centerX + dx;
        final y = centerY + dy;

        final cell = game.chunkManager.getTerrainCell(x, y);
        if (cell == null || !cell.isSolid) continue;

        if (cell.alwaysCollapses) {
          final below = game.chunkManager.getTerrainCell(x, y + 1);
          if (below == null || !below.isSolid) {
            collapseCells.add(CollapseCell(
              gridX: x,
              gridY: y,
              cellType: cell.type,
              density: cell.density,
              color: cell.baseColor,
            ));
          }
          continue;
        }

        if (!_isSupported(x, y)) {
          collapseCells.add(CollapseCell(
            gridX: x,
            gridY: y,
            cellType: cell.type,
            density: cell.density,
            color: cell.baseColor,
          ));
        }
      }
    }

    return collapseCells;
  }

  /// Check if a cell is structurally supported
  bool _isSupported(int x, int y) {
    // Check 1: solid cell directly below
    final below = game.chunkManager.getTerrainCell(x, y + 1);
    if (below != null && below.isSolid) return true;

    // Check 2: 3+ solid orthogonal neighbors
    int solidNeighbors = 0;

    final left = game.chunkManager.getTerrainCell(x - 1, y);
    if (left != null && left.isSolid) solidNeighbors++;

    final right = game.chunkManager.getTerrainCell(x + 1, y);
    if (right != null && right.isSolid) solidNeighbors++;

    final above = game.chunkManager.getTerrainCell(x, y - 1);
    if (above != null && above.isSolid) solidNeighbors++;

    // Below already checked (not solid), so max is 3
    return solidNeighbors >= GameConstants.collapseMinSupportNeighbors;
  }
}

/// Data about a cell that should collapse
class CollapseCell {
  final int gridX;
  final int gridY;
  final CellType cellType;
  final double density;
  final Color color;

  const CollapseCell({
    required this.gridX,
    required this.gridY,
    required this.cellType,
    required this.density,
    required this.color,
  });
}
