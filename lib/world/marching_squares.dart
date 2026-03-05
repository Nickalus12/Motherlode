import 'dart:ui';

import 'package:motherlode/utils/color_utils.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/stratigraphy.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Border data from neighboring chunks for seamless marching squares
class ChunkBorderData {
  /// Bottom row of chunk above (index by x)
  final List<TerrainCell>? topRow;

  /// Top row of chunk below (index by x)
  final List<TerrainCell>? bottomRow;

  /// Right column of chunk to the left (index by y)
  final List<TerrainCell>? leftCol;

  /// Left column of chunk to the right (index by y)
  final List<TerrainCell>? rightCol;

  const ChunkBorderData({
    this.topRow,
    this.bottomRow,
    this.leftCol,
    this.rightCol,
  });

  static const empty = ChunkBorderData();
}

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

  /// True if this polygon is fully interior (all 4 corners solid, case 15)
  /// Used by renderer to skip strokes on interior polygons
  final bool isInterior;

  const MarchingSquaresPoly({
    required this.path,
    required this.fillColor,
    required this.strokeColor,
    this.isInterior = false,
  });
}

/// Marching Squares implementation for smooth organic terrain rendering
///
/// For each 2x2 cell group, computes a 4-bit index (0-15) based on which
/// corners are solid (SDF < 0). Maps each index to a polygon configuration,
/// interpolates edge crossings using SDF values to find the zero-isosurface.
///
/// Supports border data from neighboring chunks for seamless edges at
/// chunk boundaries. Each chunk processes its own interior plus the
/// top and left boundary quads (to avoid double-processing).
class MarchingSquares {
  MarchingSquares._();

  /// Generate the mesh for an entire chunk with optional neighbor border data
  static MarchingSquaresResult generateMesh({
    required List<List<TerrainCell>> cells,
    required int chunkX,
    required int chunkY,
    ChunkBorderData? borders,
    Stratigraphy? stratigraphy,
  }) {
    final polygons = <MarchingSquaresPoly>[];
    final collisionSegments = <List<Offset>>[];
    final size = cells.length;

    // Cell accessor that handles border lookups
    TerrainCell? cellAt(int x, int y) {
      // Interior cells
      if (x >= 0 && x < size && y >= 0 && y < size) return cells[y][x];
      if (borders == null) return null;
      // Border cells from neighbors
      if (y == -1 && x >= 0 && x < size) return borders.topRow?[x];
      if (y == size && x >= 0 && x < size) return borders.bottomRow?[x];
      if (x == -1 && y >= 0 && y < size) return borders.leftCol?[y];
      if (x == size && y >= 0 && y < size) return borders.rightCol?[y];
      return null;
    }

    // Extended range: process top/left boundary quads when border data available
    // Each chunk processes its top and left boundaries to avoid double-processing
    final startX = (borders?.leftCol != null) ? -1 : 0;
    final startY = (borders?.topRow != null) ? -1 : 0;
    // Standard end range for interior; bottom/right boundaries are the
    // neighbor chunk's responsibility
    final endX = size - 2;
    final endY = size - 2;

    for (int y = startY; y <= endY; y++) {
      for (int x = startX; x <= endX; x++) {
        final tl = cellAt(x, y);
        final tr = cellAt(x + 1, y);
        final br = cellAt(x + 1, y + 1);
        final bl = cellAt(x, y + 1);

        // Skip if any cell is missing (no border data available)
        if (tl == null || tr == null || br == null || bl == null) continue;

        final result = _processSquareFromCells(
          tl: tl,
          tr: tr,
          br: br,
          bl: bl,
          x: x,
          y: y,
          chunkX: chunkX,
          chunkY: chunkY,
          stratigraphy: stratigraphy,
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

  /// Process a single 2x2 square from pre-fetched cells
  static _SquareResult? _processSquareFromCells({
    required TerrainCell tl,
    required TerrainCell tr,
    required TerrainCell br,
    required TerrainCell bl,
    required int x,
    required int y,
    required int chunkX,
    required int chunkY,
    Stratigraphy? stratigraphy,
  }) {
    // Compute 4-bit index
    int index = 0;
    if (tl.isSolid) index |= 8; // bit 3
    if (tr.isSolid) index |= 4; // bit 2
    if (br.isSolid) index |= 2; // bit 1
    if (bl.isSolid) index |= 1; // bit 0

    // Case 0 (all empty) - nothing to draw
    if (index == 0) return null;

    // Calculate world tile position
    final worldTileX = chunkX * GameConstants.chunkSize + x;
    final worldTileY = chunkY * GameConstants.chunkSize + y;
    final px = x.toDouble();
    final py = y.toDouble();

    // Edge midpoints (interpolated by SDF values)
    final topMid =
        _interpolateEdge(px, py, px + 1, py, tl.sdf, tr.sdf);
    final rightMid = _interpolateEdge(
        px + 1, py, px + 1, py + 1, tr.sdf, br.sdf);
    final bottomMid = _interpolateEdge(
        px, py + 1, px + 1, py + 1, bl.sdf, br.sdf);
    final leftMid =
        _interpolateEdge(px, py, px, py + 1, tl.sdf, bl.sdf);

    // Corner positions
    final tlPos = Offset(px, py);
    final trPos = Offset(px + 1, py);
    final brPos = Offset(px + 1, py + 1);
    final blPos = Offset(px, py + 1);

    // Build polygon vertices and edge segments based on case index
    List<Offset> polyVerts;
    List<Offset> edgeVerts;
    bool isInterior = false;

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
      case 15: // All solid - full square, no visible edge
        polyVerts = [tlPos, trPos, brPos, blPos];
        edgeVerts = [];
        isInterior = true;
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
      final oreCell = solidCells.firstWhere(
        (c) => c.type == CellType.ore,
        orElse: () => solidCells.first,
      );
      fillColor = oreCell.baseColor;
    } else if (solidCells.any((c) => c.type == CellType.lava)) {
      fillColor = const Color(0xFFFF4500);
    } else {
      // Use stratigraphy-aware coloring when available, otherwise
      // fall back to simple depth-based colors.
      fillColor = ColorUtils.getStratumTerrainColor(
        worldTileX.toDouble(),
        depthFeet,
        stratigraphy,
      );

      // Add subtle brightness variation based on SDF depth into solid
      final avgDensity =
          solidCells.fold<double>(0.0, (sum, c) => sum + c.density) /
              solidCells.length.clamp(1, 4);
      fillColor = Color.lerp(
        ColorUtils.darken(fillColor, 0.15),
        ColorUtils.brighten(fillColor, 0.08),
        avgDensity,
      )!;
    }

    final strokeColor = ColorUtils.darken(fillColor, 0.25);

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
        isInterior: isInterior,
      ),
      edgeSegment: edgeVerts,
    );
  }

  /// Interpolate edge crossing position based on SDF values.
  /// The surface crossing is at SDF = 0 (the zero-isosurface).
  static Offset _interpolateEdge(
    double x1,
    double y1,
    double x2,
    double y2,
    double sdf1,
    double sdf2,
  ) {
    const threshold = 0.0; // SDF zero-crossing

    double t;
    final diff = sdf2 - sdf1;
    if (diff.abs() < 0.001) {
      t = 0.5;
    } else {
      t = ((threshold - sdf1) / diff).clamp(0.0, 1.0);
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
