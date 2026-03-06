import 'dart:ui';

import 'package:motherlode/data/ore_types.dart';
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
  final bool isInterior;

  /// True if this polygon contains ore (for animated shimmer effect)
  final bool isOre;

  /// True if this polygon contains lava (for animated glow effect)
  final bool isLava;

  const MarchingSquaresPoly({
    required this.path,
    required this.fillColor,
    required this.strokeColor,
    this.isInterior = false,
    this.isOre = false,
    this.isLava = false,
  });
}

/// Marching Squares with 2x subdivision for smooth organic terrain.
///
/// Bilinearly interpolates SDF values at half-cell positions to produce
/// a mesh with 4x the polygon count but much smoother contours. The
/// zero-isosurface is traced with sub-cell precision.
class MarchingSquares {
  MarchingSquares._();

  /// Subdivision factor: 2 = half-cell resolution (4x polygons)
  static const int _subdiv = 2;

  /// Generate the mesh for an entire chunk with 2x subdivided resolution
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
    final step = 1.0 / _subdiv;

    // Cell accessor that handles border lookups
    TerrainCell? cellAt(int x, int y) {
      if (x >= 0 && x < size && y >= 0 && y < size) return cells[y][x];
      if (borders == null) return null;
      if (y == -1 && x >= 0 && x < size) return borders.topRow?[x];
      if (y == size && x >= 0 && x < size) return borders.bottomRow?[x];
      if (x == -1 && y >= 0 && y < size) return borders.leftCol?[y];
      if (x == size && y >= 0 && y < size) return borders.rightCol?[y];
      return null;
    }

    // Bilinearly interpolate SDF at a fractional cell position
    double sdfAt(double wx, double wy) {
      final cx = wx.floor();
      final cy = wy.floor();
      final fx = wx - cx;
      final fy = wy - cy;

      final c00 = cellAt(cx, cy)?.sdf ?? 1.0;
      final c10 = cellAt(cx + 1, cy)?.sdf ?? 1.0;
      final c01 = cellAt(cx, cy + 1)?.sdf ?? 1.0;
      final c11 = cellAt(cx + 1, cy + 1)?.sdf ?? 1.0;

      return c00 * (1 - fx) * (1 - fy) +
          c10 * fx * (1 - fy) +
          c01 * (1 - fx) * fy +
          c11 * fx * fy;
    }

    // Get the nearest real cell for type/color info
    TerrainCell? nearestCell(double wx, double wy) {
      final cx = (wx + 0.5).floor().clamp(0, size - 1);
      final cy = (wy + 0.5).floor().clamp(0, size - 1);
      return cellAt(cx, cy);
    }

    // Extended range with border handling
    final startX = (borders?.leftCol != null) ? -1 : 0;
    final startY = (borders?.topRow != null) ? -1 : 0;
    final endX = size - 2;
    final endY = size - 2;

    // Virtual grid range in sub-cell steps
    final vStartX = startX * _subdiv;
    final vStartY = startY * _subdiv;
    final vEndX = endX * _subdiv + (_subdiv - 1);
    final vEndY = endY * _subdiv + (_subdiv - 1);

    for (int vy = vStartY; vy <= vEndY; vy++) {
      for (int vx = vStartX; vx <= vEndX; vx++) {
        // World-local positions of this virtual quad's four corners
        final px0 = vx * step;
        final py0 = vy * step;
        final px1 = (vx + 1) * step;
        final py1 = (vy + 1) * step;

        // SDF at each corner (bilinearly interpolated)
        final sdfTL = sdfAt(px0, py0);
        final sdfTR = sdfAt(px1, py0);
        final sdfBR = sdfAt(px1, py1);
        final sdfBL = sdfAt(px0, py1);

        // 4-bit marching squares index
        int index = 0;
        if (sdfTL < 0) index |= 8;
        if (sdfTR < 0) index |= 4;
        if (sdfBR < 0) index |= 2;
        if (sdfBL < 0) index |= 1;

        if (index == 0) continue; // All empty

        // Edge midpoints (SDF-interpolated for precise zero-isosurface)
        final topMid = _interpolateEdge(px0, py0, px1, py0, sdfTL, sdfTR);
        final rightMid = _interpolateEdge(px1, py0, px1, py1, sdfTR, sdfBR);
        final bottomMid = _interpolateEdge(px0, py1, px1, py1, sdfBL, sdfBR);
        final leftMid = _interpolateEdge(px0, py0, px0, py1, sdfTL, sdfBL);

        // Corner positions
        final tlPos = Offset(px0, py0);
        final trPos = Offset(px1, py0);
        final brPos = Offset(px1, py1);
        final blPos = Offset(px0, py1);

        // Build polygon vertices and collision edges
        List<Offset> polyVerts;
        List<Offset> edgeVerts;
        bool isInterior = false;

        switch (index) {
          case 1:
            polyVerts = [leftMid, blPos, bottomMid];
            edgeVerts = [leftMid, bottomMid];
            break;
          case 2:
            polyVerts = [bottomMid, brPos, rightMid];
            edgeVerts = [bottomMid, rightMid];
            break;
          case 3:
            polyVerts = [leftMid, blPos, brPos, rightMid];
            edgeVerts = [leftMid, rightMid];
            break;
          case 4:
            polyVerts = [topMid, trPos, rightMid];
            edgeVerts = [topMid, rightMid];
            break;
          case 5:
            polyVerts = [topMid, trPos, rightMid, bottomMid, blPos, leftMid];
            edgeVerts = [topMid, rightMid, bottomMid, leftMid];
            break;
          case 6:
            polyVerts = [topMid, trPos, brPos, bottomMid];
            edgeVerts = [topMid, bottomMid];
            break;
          case 7:
            polyVerts = [topMid, trPos, brPos, blPos, leftMid];
            edgeVerts = [topMid, leftMid];
            break;
          case 8:
            polyVerts = [tlPos, topMid, leftMid];
            edgeVerts = [topMid, leftMid];
            break;
          case 9:
            polyVerts = [tlPos, topMid, bottomMid, blPos];
            edgeVerts = [topMid, bottomMid];
            break;
          case 10:
            polyVerts = [tlPos, topMid, rightMid, brPos, bottomMid, leftMid];
            edgeVerts = [topMid, rightMid, bottomMid, leftMid];
            break;
          case 11:
            polyVerts = [tlPos, topMid, rightMid, brPos, blPos];
            edgeVerts = [topMid, rightMid];
            break;
          case 12:
            polyVerts = [tlPos, trPos, rightMid, leftMid];
            edgeVerts = [rightMid, leftMid];
            break;
          case 13:
            polyVerts = [tlPos, trPos, rightMid, bottomMid, blPos];
            edgeVerts = [rightMid, bottomMid];
            break;
          case 14:
            polyVerts = [tlPos, trPos, brPos, bottomMid, leftMid];
            edgeVerts = [bottomMid, leftMid];
            break;
          case 15:
            polyVerts = [tlPos, trPos, brPos, blPos];
            edgeVerts = [];
            isInterior = true;
            break;
          default:
            continue;
        }

        // Color: use the center of this virtual quad to look up the real cell
        final centerX = (px0 + px1) / 2;
        final centerY = (py0 + py1) / 2;
        final worldTileX = chunkX * GameConstants.chunkSize + centerX;
        final worldTileY = chunkY * GameConstants.chunkSize + centerY;
        final depthFeet = worldTileY * GameConstants.feetPerTile;

        // Gather solid corners for color determination
        final solidSdfs = <double>[];
        final solidTypes = <CellType>[];
        OreType? foundOreType;
        bool cellIsOre = false;
        bool cellIsLava = false;

        for (final corner in [
          (px0, py0, sdfTL),
          (px1, py0, sdfTR),
          (px1, py1, sdfBR),
          (px0, py1, sdfBL),
        ]) {
          if (corner.$3 < 0) {
            solidSdfs.add(corner.$3);
            final cell = nearestCell(corner.$1, corner.$2);
            if (cell != null) {
              solidTypes.add(cell.type);
              if (cell.type == CellType.ore) {
                cellIsOre = true;
                foundOreType ??= cell.oreType;
              } else if (cell.type == CellType.lava) {
                cellIsLava = true;
              }
            }
          }
        }

        Color fillColor;
        if (cellIsOre && foundOreType != null) {
          fillColor = foundOreType.color;
        } else if (cellIsLava) {
          fillColor = const Color(0xFFFF4500);
        } else {
          // Detect air above for grass rendering
          final aboveSdf = sdfAt(centerX, centerY - step);
          final hasAirAbove = aboveSdf >= 0 && (sdfBL < 0 || sdfBR < 0);

          fillColor = ColorUtils.getStratumTerrainColor(
            worldTileX,
            depthFeet,
            stratigraphy,
            hasAirAbove: hasAirAbove,
          );

          // Brightness variation from average SDF depth
          if (solidSdfs.isNotEmpty) {
            final avgSdf = solidSdfs.fold<double>(0, (s, v) => s + v) /
                solidSdfs.length;
            // Deeper into solid = slightly darker, near surface = lighter
            final t = ((-avgSdf) / 2.0).clamp(0.0, 1.0);
            fillColor = Color.lerp(
              ColorUtils.brighten(fillColor, 0.04),
              ColorUtils.darken(fillColor, 0.06),
              t,
            )!;
          }
        }

        final strokeColor = ColorUtils.darken(fillColor, 0.15);

        // Build path
        final path = Path();
        path.moveTo(polyVerts[0].dx, polyVerts[0].dy);
        for (int i = 1; i < polyVerts.length; i++) {
          path.lineTo(polyVerts[i].dx, polyVerts[i].dy);
        }
        path.close();

        polygons.add(MarchingSquaresPoly(
          path: path,
          fillColor: fillColor,
          strokeColor: strokeColor,
          isInterior: isInterior,
          isOre: cellIsOre,
          isLava: cellIsLava,
        ));

        if (edgeVerts.isNotEmpty) {
          collisionSegments.add(edgeVerts);
        }
      }
    }

    return MarchingSquaresResult(
      polygons: polygons,
      collisionSegments: collisionSegments,
    );
  }

  /// Interpolate edge crossing position based on SDF values.
  static Offset _interpolateEdge(
    double x1,
    double y1,
    double x2,
    double y2,
    double sdf1,
    double sdf2,
  ) {
    double t;
    final diff = sdf2 - sdf1;
    if (diff.abs() < 0.001) {
      t = 0.5;
    } else {
      t = (-sdf1 / diff).clamp(0.0, 1.0);
    }

    return Offset(
      x1 + (x2 - x1) * t,
      y1 + (y2 - y1) * t,
    );
  }
}
