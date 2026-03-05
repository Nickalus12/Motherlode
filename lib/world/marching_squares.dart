import 'dart:ui';

import 'package:hellbore/utils/color_utils.dart';
import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/world/terrain_cell.dart';

/// Result of marching squares mesh generation for a chunk
class MarchingSquaresResult {
  /// Visual paths to draw (filled polygons)
  final List<MarchingSquaresPoly> polygons;

  /// Collision edge segments for Forge2D
  final List<List<Offset>> collisionSegments;

  const MarchingSquaresResult({
    required this.polygons,
    required this.collisionSegments,
  });
}

/// A polygon from marching squares with fill and stroke colors
class MarchingSquaresPoly {
  final Path path;
  final Color fillColor;
  final Color strokeColor;

  const MarchingSquaresPoly({
    required this.path,
    required this.fillColor,
    required this.strokeColor,
  });
}

/// Marching Squares implementation for smooth organic terrain rendering
///
/// For each 2x2 cell group, computes a 4-bit index (0–15) based on which
/// corners are solid. Maps each index to a polygon configuration, interpolates
/// edge crossings using actual density values for smooth curves.
class MarchingSquares {
  MarchingSquares._();

  /// Generate the mesh for an entire chunk
  static MarchingSquaresResult generateMesh({
    required List<List<TerrainCell>> cells,
    required int chunkX,
    required int chunkY,
  }) {
    final polygons = <MarchingSquaresPoly>[];
    final collisionSegments = <List<Offset>>[];
    final size = cells.length;

    // Process each 2x2 cell group
    for (int y = 0; y < size - 1; y++) {
      for (int x = 0; x < size - 1; x++) {
        final result = _processSquare(
          cells: cells,
          x: x,
          y: y,
          chunkX: chunkX,
          chunkY: chunkY,
        );

        if (result != null) {
          polygons.add(result.polygon);
          if (result.edgeSegment.isNotEmpty) {
            collisionSegments.add(result.edgeSegment);
          }
        }
      }
    }

    return MarchingSquaresResult(
      polygons: polygons,
      collisionSegments: collisionSegments,
    );
  }

  /// Process a single 2x2 square
  static _SquareResult? _processSquare({
    required List<List<TerrainCell>> cells,
    required int x,
    required int y,
    required int chunkX,
    required int chunkY,
  }) {
    // Get the four corners (top-left, top-right, bottom-right, bottom-left)
    final tl = cells[y][x];
    final tr = cells[y][x + 1];
    final br = cells[y + 1][x + 1];
    final bl = cells[y + 1][x];

    // Compute 4-bit index
    int index = 0;
    if (tl.isSolid) index |= 8; // bit 3
    if (tr.isSolid) index |= 4; // bit 2
    if (br.isSolid) index |= 2; // bit 1
    if (bl.isSolid) index |= 1; // bit 0

    // Case 0 (all empty) and case 15 (all solid with no visible edge)
    if (index == 0) return null;

    // Calculate world pixel position of this cell
    final worldTileX = chunkX * GameConstants.chunkSize + x;
    final worldTileY = chunkY * GameConstants.chunkSize + y;
    final px = x.toDouble();
    final py = y.toDouble();

    // Edge midpoints (interpolated by density)
    final topMid = _interpolateEdge(px, py, px + 1, py, tl.density, tr.density);
    final rightMid =
        _interpolateEdge(px + 1, py, px + 1, py + 1, tr.density, br.density);
    final bottomMid =
        _interpolateEdge(px, py + 1, px + 1, py + 1, bl.density, br.density);
    final leftMid =
        _interpolateEdge(px, py, px, py + 1, tl.density, bl.density);

    // Corner positions
    final tlPos = Offset(px, py);
    final trPos = Offset(px + 1, py);
    final brPos = Offset(px + 1, py + 1);
    final blPos = Offset(px, py + 1);

    // Build polygon vertices and edge segments based on case index
    List<Offset> polyVerts;
    List<Offset> edgeVerts;

    switch (index) {
      case 1: // Only bottom-left solid
        polyVerts = [leftMid, blPos, bottomMid];
        edgeVerts = [leftMid, bottomMid];
        break;
      case 2: // Only bottom-right solid
        polyVerts = [bottomMid, brPos, rightMid];
        edgeVerts = [bottomMid, rightMid];
        break;
      case 3: // Bottom row solid
        polyVerts = [leftMid, blPos, brPos, rightMid];
        edgeVerts = [leftMid, rightMid];
        break;
      case 4: // Only top-right solid
        polyVerts = [topMid, trPos, rightMid];
        edgeVerts = [topMid, rightMid];
        break;
      case 5: // Top-right and bottom-left (saddle point)
        polyVerts = [topMid, trPos, rightMid, bottomMid, blPos, leftMid];
        edgeVerts = [topMid, rightMid, bottomMid, leftMid];
        break;
      case 6: // Right column solid
        polyVerts = [topMid, trPos, brPos, bottomMid];
        edgeVerts = [topMid, bottomMid];
        break;
      case 7: // All except top-left
        polyVerts = [topMid, trPos, brPos, blPos, leftMid];
        edgeVerts = [topMid, leftMid];
        break;
      case 8: // Only top-left solid
        polyVerts = [tlPos, topMid, leftMid];
        edgeVerts = [topMid, leftMid];
        break;
      case 9: // Left column solid
        polyVerts = [tlPos, topMid, bottomMid, blPos];
        edgeVerts = [topMid, bottomMid];
        break;
      case 10: // Top-left and bottom-right (saddle point)
        polyVerts = [tlPos, topMid, rightMid, brPos, bottomMid, leftMid];
        edgeVerts = [topMid, rightMid, bottomMid, leftMid];
        break;
      case 11: // All except top-right
        polyVerts = [tlPos, topMid, rightMid, brPos, blPos];
        edgeVerts = [topMid, rightMid];
        break;
      case 12: // Top row solid
        polyVerts = [tlPos, trPos, rightMid, leftMid];
        edgeVerts = [rightMid, leftMid];
        break;
      case 13: // All except bottom-right
        polyVerts = [tlPos, trPos, rightMid, bottomMid, blPos];
        edgeVerts = [rightMid, bottomMid];
        break;
      case 14: // All except bottom-left
        polyVerts = [tlPos, trPos, brPos, bottomMid, leftMid];
        edgeVerts = [bottomMid, leftMid];
        break;
      case 15: // All solid - full square
        polyVerts = [tlPos, trPos, brPos, blPos];
        edgeVerts = [];
        break;
      default:
        return null;
    }

    // Get depth-based color
    final depthFeet = worldTileY * GameConstants.feetPerTile;

    // Use the predominant solid cell's color, or depth-based terrain color
    final solidCells = [tl, tr, br, bl].where((c) => c.isSolid).toList();
    Color fillColor;
    if (solidCells.any((c) => c.type == CellType.ore)) {
      // Show ore color
      final oreCell = solidCells.firstWhere(
        (c) => c.type == CellType.ore,
        orElse: () => solidCells.first,
      );
      fillColor = oreCell.baseColor;
    } else if (solidCells.any((c) => c.type == CellType.lava)) {
      fillColor = const Color(0xFFFF4500);
    } else {
      fillColor = ColorUtils.getTerrainColor(depthFeet);

      // Add slight brightness variation based on density
      final avgDensity = solidCells.fold<double>(
              0.0, (sum, c) => sum + c.density) /
          solidCells.length.clamp(1, 4);
      fillColor = Color.lerp(
        ColorUtils.darken(fillColor, 0.1),
        ColorUtils.brighten(fillColor, 0.05),
        avgDensity,
      )!;
    }

    final strokeColor = ColorUtils.darken(fillColor, 0.2);

    // Build visual path
    final path = Path();
    if (polyVerts.isNotEmpty) {
      path.moveTo(polyVerts[0].dx, polyVerts[0].dy);
      for (int i = 1; i < polyVerts.length; i++) {
        path.lineTo(polyVerts[i].dx, polyVerts[i].dy);
      }
      path.close();
    }

    return _SquareResult(
      polygon: MarchingSquaresPoly(
        path: path,
        fillColor: fillColor,
        strokeColor: strokeColor,
      ),
      edgeSegment: edgeVerts,
    );
  }

  /// Interpolate edge crossing position based on density values
  /// Instead of always using the midpoint, use actual density for smooth curves
  static Offset _interpolateEdge(
    double x1,
    double y1,
    double x2,
    double y2,
    double density1,
    double density2,
  ) {
    // Threshold for solid/empty classification
    const threshold = 0.52;

    // Calculate interpolation factor based on densities
    double t;
    final diff = density2 - density1;
    if (diff.abs() < 0.001) {
      t = 0.5;
    } else {
      t = ((threshold - density1) / diff).clamp(0.0, 1.0);
    }

    return Offset(
      x1 + (x2 - x1) * t,
      y1 + (y2 - y1) * t,
    );
  }
}

class _SquareResult {
  final MarchingSquaresPoly polygon;
  final List<Offset> edgeSegment;

  const _SquareResult({
    required this.polygon,
    required this.edgeSegment,
  });
}
