import 'dart:math';
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
/// 5. Cascading: re-check neighbors of collapsed cells for chain reactions
class CollapseDetector {
  final MotherlodeGame game;

  /// Material mass values (kg) for debris bodies.
  static const Map<CellType, double> materialMass = {
    CellType.sand: 30.0,
    CellType.dirt: 50.0,
    CellType.rock: 80.0,
    CellType.obsidian: 120.0,
    CellType.ore: 70.0,
  };

  /// Debris half-size per material type (world meters).
  static const Map<CellType, double> debrisSize = {
    CellType.sand: 0.2,
    CellType.dirt: 0.3,
    CellType.rock: 0.4,
    CellType.obsidian: 0.4,
    CellType.ore: 0.35,
  };

  CollapseDetector({required this.game});

  /// Check for collapse around a removed cell, including cascade.
  /// Returns cells sorted by distance from center (nearest first)
  /// for staggered spawn.
  List<CollapseCell> checkCollapse(int centerX, int centerY) {
    return _checkWithCascade(
        centerX, centerY, GameConstants.collapseCheckRadius,
        circular: false);
  }

  /// Check for collapse in a larger area (after explosion), including cascade.
  List<CollapseCell> checkCollapseArea(int centerX, int centerY, int radius) {
    return _checkWithCascade(centerX, centerY, radius, circular: true);
  }

  /// Core collapse detection with cascading support.
  /// Performs iterative passes: each pass finds unsupported cells,
  /// marks them for collapse, then re-checks their neighbors.
  List<CollapseCell> _checkWithCascade(int centerX, int centerY, int radius,
      {required bool circular}) {
    final collapsed = <String, CollapseCell>{};
    // Pending set of cells to check — starts with the initial area,
    // then grows as cascade discovers new unsupported cells.
    var toCheck = <_GridPos>[];

    // Seed the initial check area
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (circular && dx * dx + dy * dy > radius * radius) continue;
        toCheck.add(_GridPos(centerX + dx, centerY + dy));
      }
    }

    // Iterative cascade — max 4 passes to avoid runaway chains
    for (int pass = 0; pass < 4; pass++) {
      final newCollapsed = <CollapseCell>[];

      for (final pos in toCheck) {
        final key = '${pos.x},${pos.y}';
        if (collapsed.containsKey(key)) continue;

        final cell = game.chunkManager.getTerrainCell(pos.x, pos.y);
        if (cell == null || !cell.isSolid) continue;

        bool shouldCollapse = false;

        if (cell.alwaysCollapses) {
          final below = game.chunkManager.getTerrainCell(pos.x, pos.y + 1);
          shouldCollapse = below == null || !below.isSolid;
        } else {
          shouldCollapse = !_isSupported(pos.x, pos.y, collapsed);
        }

        if (shouldCollapse) {
          final cc = CollapseCell(
            gridX: pos.x,
            gridY: pos.y,
            cellType: cell.type,
            mass: materialMass[cell.type] ?? 50.0,
            halfSize: debrisSize[cell.type] ?? 0.3,
            color: cell.baseColor,
            distanceFromCenter: _distance(pos.x, pos.y, centerX, centerY),
          );
          collapsed[key] = cc;
          newCollapsed.add(cc);
        }
      }

      if (newCollapsed.isEmpty) break;

      // Cascade: add orthogonal neighbors of newly collapsed cells
      toCheck = [];
      for (final cc in newCollapsed) {
        for (final offset in _orthogonal) {
          toCheck.add(_GridPos(cc.gridX + offset.x, cc.gridY + offset.y));
        }
      }
    }

    // Sort by distance for staggered spawn (nearest first)
    final result = collapsed.values.toList()
      ..sort((a, b) => a.distanceFromCenter.compareTo(b.distanceFromCenter));
    return result;
  }

  /// Check if a cell is structurally supported.
  /// [pendingCollapse] contains cells already marked to collapse in this pass,
  /// which should not count as support.
  bool _isSupported(int x, int y, Map<String, CollapseCell> pendingCollapse) {
    bool isSolid(int cx, int cy) {
      if (pendingCollapse.containsKey('$cx,$cy')) return false;
      final c = game.chunkManager.getTerrainCell(cx, cy);
      return c != null && c.isSolid;
    }

    // Check 1: solid cell directly below
    if (isSolid(x, y + 1)) return true;

    // Check 2: 3+ solid orthogonal neighbors
    int solidNeighbors = 0;
    if (isSolid(x - 1, y)) solidNeighbors++;
    if (isSolid(x + 1, y)) solidNeighbors++;
    if (isSolid(x, y - 1)) solidNeighbors++;
    // Below already checked (not solid), so max is 3
    return solidNeighbors >= GameConstants.collapseMinSupportNeighbors;
  }

  static double _distance(int x1, int y1, int x2, int y2) {
    final dx = (x1 - x2).toDouble();
    final dy = (y1 - y2).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  static const _orthogonal = [
    _GridPos(0, -1),
    _GridPos(0, 1),
    _GridPos(-1, 0),
    _GridPos(1, 0),
  ];
}

class _GridPos {
  final int x;
  final int y;
  const _GridPos(this.x, this.y);
}

/// Data about a cell that should collapse
class CollapseCell {
  final int gridX;
  final int gridY;
  final CellType cellType;
  final double mass;
  final double halfSize;
  final Color color;
  final double distanceFromCenter;

  const CollapseCell({
    required this.gridX,
    required this.gridY,
    required this.cellType,
    required this.mass,
    required this.halfSize,
    required this.color,
    required this.distanceFromCenter,
  });
}
