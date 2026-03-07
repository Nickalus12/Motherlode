import 'dart:math' as math;
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
    const step = 1.0 / _subdiv;

    // Cell accessor that handles border lookups including diagonal corners.
    // For corner cells (e.g., x=-1,y=-1), average the two adjacent border
    // cells to produce a smooth SDF transition instead of returning null.
    TerrainCell? cellAt(int x, int y) {
      if (x >= 0 && x < size && y >= 0 && y < size) return cells[y][x];
      if (borders == null) return null;
      if (y == -1 && x >= 0 && x < size) return borders.topRow?[x];
      if (y == size && x >= 0 && x < size) return borders.bottomRow?[x];
      if (x == -1 && y >= 0 && y < size) return borders.leftCol?[y];
      if (x == size && y >= 0 && y < size) return borders.rightCol?[y];
      // Diagonal corners: interpolate from the two adjacent border edges
      if (x == -1 && y == -1) {
        final left = borders.leftCol;
        final top = borders.topRow;
        if (left != null && top != null) {
          final avgSdf = (left[0].sdf + top[0].sdf) / 2.0;
          return TerrainCell(
              type: avgSdf < 0 ? left[0].type : CellType.empty, sdf: avgSdf);
        }
        return left?[0] ?? top?[0];
      }
      if (x == size && y == -1) {
        final right = borders.rightCol;
        final top = borders.topRow;
        if (right != null && top != null) {
          final avgSdf = (right[0].sdf + top[size - 1].sdf) / 2.0;
          return TerrainCell(
              type: avgSdf < 0 ? right[0].type : CellType.empty, sdf: avgSdf);
        }
        return right?[0] ?? top?[size - 1];
      }
      if (x == -1 && y == size) {
        final left = borders.leftCol;
        final bottom = borders.bottomRow;
        if (left != null && bottom != null) {
          final avgSdf = (left[size - 1].sdf + bottom[0].sdf) / 2.0;
          return TerrainCell(
              type: avgSdf < 0 ? left[size - 1].type : CellType.empty,
              sdf: avgSdf);
        }
        return left?[size - 1] ?? bottom?[0];
      }
      if (x == size && y == size) {
        final right = borders.rightCol;
        final bottom = borders.bottomRow;
        if (right != null && bottom != null) {
          final avgSdf = (right[size - 1].sdf + bottom[size - 1].sdf) / 2.0;
          return TerrainCell(
              type: avgSdf < 0 ? right[size - 1].type : CellType.empty,
              sdf: avgSdf);
        }
        return right?[size - 1] ?? bottom?[size - 1];
      }
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

    // Extended range with border handling.
    // When border data is available, extend the range so marching squares
    // can interpolate across chunk boundaries without cliff edges.
    final startX = (borders?.leftCol != null) ? -1 : 0;
    final startY = (borders?.topRow != null) ? -1 : 0;
    final endX = (borders?.rightCol != null) ? size - 1 : size - 2;
    final endY = (borders?.bottomRow != null) ? size - 1 : size - 2;

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

        // Optimization: skip fully interior sub-cells deep inside solid terrain.
        // If all 4 corners are solid and all SDF values are well below zero,
        // use a simplified path to avoid expensive color lookups.
        if (index == 15) {
          final minSdf =
              math.min(math.min(sdfTL, sdfTR), math.min(sdfBR, sdfBL));
          if (minSdf < -2.0) {
            // Deep interior: use a quick color lookup for the center cell only
            final centerX = (px0 + px1) / 2;
            final centerY = (py0 + py1) / 2;
            final worldTileX = chunkX * GameConstants.chunkSize + centerX;
            final worldTileY = chunkY * GameConstants.chunkSize + centerY;
            final depthFeet = worldTileY * GameConstants.feetPerTile;

            final cell = nearestCell(centerX, centerY);
            Color fillColor;
            bool cellIsOre = false;
            bool cellIsLava = false;

            if (cell != null &&
                cell.type == CellType.ore &&
                cell.oreType != null) {
              fillColor = cell.oreType!.color;
              cellIsOre = true;
            } else if (cell != null && cell.type == CellType.lava) {
              fillColor = const Color(0xFFFF4500);
              cellIsLava = true;
            } else {
              fillColor = ColorUtils.getStratumTerrainColor(
                worldTileX,
                depthFeet,
                stratigraphy,
                hasAirAbove: false,
              );
              // Micro-detail noise: subtle brightness variation for visual richness
              final noiseVal = _microNoise(worldTileX, worldTileY);
              fillColor =
                  ColorUtils.brighten(fillColor, noiseVal * 0.04 - 0.02);
            }

            final path = Path();
            path.addRect(Rect.fromLTRB(px0, py0, px1, py1));
            polygons.add(MarchingSquaresPoly(
              path: path,
              fillColor: fillColor,
              strokeColor: ColorUtils.darken(fillColor, 0.15),
              isInterior: true,
              isOre: cellIsOre,
              isLava: cellIsLava,
            ));
            continue;
          }
        }

        // Edge midpoints for visual rendering (smoothstep for nice contours)
        final topMid = _interpolateEdge(px0, py0, px1, py0, sdfTL, sdfTR);
        final rightMid = _interpolateEdge(px1, py0, px1, py1, sdfTR, sdfBR);
        final bottomMid = _interpolateEdge(px0, py1, px1, py1, sdfBL, sdfBR);
        final leftMid = _interpolateEdge(px0, py0, px0, py1, sdfTL, sdfBL);

        // Edge midpoints for collision (exact linear interpolation — no
        // smoothstep distortion so collision sits precisely on the SDF
        // zero-isosurface and the pod cannot slip through gaps)
        final cTopMid = _interpolateEdgeCollision(px0, py0, px1, py0, sdfTL, sdfTR);
        final cRightMid = _interpolateEdgeCollision(px1, py0, px1, py1, sdfTR, sdfBR);
        final cBottomMid = _interpolateEdgeCollision(px0, py1, px1, py1, sdfBL, sdfBR);
        final cLeftMid = _interpolateEdgeCollision(px0, py0, px0, py1, sdfTL, sdfBL);

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
            edgeVerts = [cLeftMid, cBottomMid];
            break;
          case 2:
            polyVerts = [bottomMid, brPos, rightMid];
            edgeVerts = [cBottomMid, cRightMid];
            break;
          case 3:
            polyVerts = [leftMid, blPos, brPos, rightMid];
            edgeVerts = [cLeftMid, cRightMid];
            break;
          case 4:
            polyVerts = [topMid, trPos, rightMid];
            edgeVerts = [cTopMid, cRightMid];
            break;
          case 5:
            polyVerts = [topMid, trPos, rightMid, bottomMid, blPos, leftMid];
            edgeVerts = [cTopMid, cRightMid, cBottomMid, cLeftMid];
            break;
          case 6:
            polyVerts = [topMid, trPos, brPos, bottomMid];
            edgeVerts = [cTopMid, cBottomMid];
            break;
          case 7:
            polyVerts = [topMid, trPos, brPos, blPos, leftMid];
            edgeVerts = [cTopMid, cLeftMid];
            break;
          case 8:
            polyVerts = [tlPos, topMid, leftMid];
            edgeVerts = [cTopMid, cLeftMid];
            break;
          case 9:
            polyVerts = [tlPos, topMid, bottomMid, blPos];
            edgeVerts = [cTopMid, cBottomMid];
            break;
          case 10:
            polyVerts = [tlPos, topMid, rightMid, brPos, bottomMid, leftMid];
            edgeVerts = [cTopMid, cRightMid, cBottomMid, cLeftMid];
            break;
          case 11:
            polyVerts = [tlPos, topMid, rightMid, brPos, blPos];
            edgeVerts = [cTopMid, cRightMid];
            break;
          case 12:
            polyVerts = [tlPos, trPos, rightMid, leftMid];
            edgeVerts = [cRightMid, cLeftMid];
            break;
          case 13:
            polyVerts = [tlPos, trPos, rightMid, bottomMid, blPos];
            edgeVerts = [cRightMid, cBottomMid];
            break;
          case 14:
            polyVerts = [tlPos, trPos, brPos, bottomMid, leftMid];
            edgeVerts = [cBottomMid, cLeftMid];
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

        // Gather solid corners with SDF weights for color blending
        final cornerData = <(double, double, double)>[];
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
            cornerData.add((corner.$3, corner.$1, corner.$2));
            final cell = nearestCell(corner.$1, corner.$2);
            if (cell != null) {
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
          // Enhanced grass detection: check multiple cells above for more
          // reliable surface detection. Scanning 2 steps above catches grass
          // even when a single sub-cell above happens to be on a boundary.
          final above1Sdf = sdfAt(centerX, centerY - step);
          final above2Sdf = sdfAt(centerX, centerY - step * 2);
          final hasSolidBelow = sdfBL < 0 || sdfBR < 0;
          final hasAirAbove =
              (above1Sdf >= 0 || above2Sdf >= 0) && hasSolidBelow;

          fillColor = ColorUtils.getStratumTerrainColor(
            worldTileX,
            depthFeet,
            stratigraphy,
            hasAirAbove: hasAirAbove,
          );

          // SDF-weighted brightness variation: cells deeper into solid are
          // slightly darker, cells near the surface catch more "light"
          if (cornerData.isNotEmpty) {
            // Weighted average SDF based on abs(sdf) — deeper corners
            // contribute more to the perceived depth
            double totalWeight = 0;
            double weightedSdf = 0;
            for (final c in cornerData) {
              final w = (-c.$1).clamp(0.01, 10.0);
              totalWeight += w;
              weightedSdf += c.$1 * w;
            }
            final avgSdf = weightedSdf / totalWeight;
            final t = ((-avgSdf) / 2.0).clamp(0.0, 1.0);
            fillColor = Color.lerp(
              ColorUtils.brighten(fillColor, 0.04),
              ColorUtils.darken(fillColor, 0.06),
              t,
            )!;
          }

          // Micro-detail noise: subtle per-sub-cell brightness variation
          // for visual richness without visible repetition
          final noiseVal = _microNoise(worldTileX, worldTileY);
          fillColor = ColorUtils.brighten(fillColor, noiseVal * 0.04 - 0.02);
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
  /// Uses Hermite smoothstep on the linear parameter for smoother visual
  /// contours while preserving the correct zero-isosurface position for
  /// collision geometry.
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

    // Apply Hermite smoothstep for smoother terrain contours.
    // This biases the interpolation toward the midpoint, reducing
    // sharp angular transitions at shallow SDF crossings.
    t = t * t * (3.0 - 2.0 * t);

    return Offset(
      x1 + (x2 - x1) * t,
      y1 + (y2 - y1) * t,
    );
  }

  /// Interpolate edge crossing for collision geometry using exact linear
  /// interpolation (no smoothstep). This ensures collision edges sit
  /// precisely on the SDF zero-isosurface so the pod cannot slip through
  /// gaps between visual and collision contours.
  static Offset _interpolateEdgeCollision(
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

    // No smoothstep — exact zero-crossing for precise collision
    return Offset(
      x1 + (x2 - x1) * t,
      y1 + (y2 - y1) * t,
    );
  }

  /// Generate collision segments only, without visual polygons.
  /// Uses base grid resolution (no subdivision) for much faster generation.
  /// Called during drilling when only collision needs updating immediately.
  static List<List<Offset>> generateCollisionOnly({
    required List<List<TerrainCell>> cells,
    ChunkBorderData? borders,
  }) {
    final collisionSegments = <List<Offset>>[];
    final size = cells.length;

    TerrainCell? cellAt(int x, int y) {
      if (x >= 0 && x < size && y >= 0 && y < size) return cells[y][x];
      if (borders == null) return null;
      if (y == -1 && x >= 0 && x < size) return borders.topRow?[x];
      if (y == size && x >= 0 && x < size) return borders.bottomRow?[x];
      if (x == -1 && y >= 0 && y < size) return borders.leftCol?[y];
      if (x == size && y >= 0 && y < size) return borders.rightCol?[y];
      return null;
    }

    final startX = (borders?.leftCol != null) ? -1 : 0;
    final startY = (borders?.topRow != null) ? -1 : 0;
    final endX = (borders?.rightCol != null) ? size - 1 : size - 2;
    final endY = (borders?.bottomRow != null) ? size - 1 : size - 2;

    for (int y = startY; y <= endY; y++) {
      for (int x = startX; x <= endX; x++) {
        final sdfTL = cellAt(x, y)?.sdf ?? 1.0;
        final sdfTR = cellAt(x + 1, y)?.sdf ?? 1.0;
        final sdfBR = cellAt(x + 1, y + 1)?.sdf ?? 1.0;
        final sdfBL = cellAt(x, y + 1)?.sdf ?? 1.0;

        int index = 0;
        if (sdfTL < 0) index |= 8;
        if (sdfTR < 0) index |= 4;
        if (sdfBR < 0) index |= 2;
        if (sdfBL < 0) index |= 1;

        if (index == 0 || index == 15) continue;

        final px0 = x.toDouble();
        final py0 = y.toDouble();
        final px1 = x + 1.0;
        final py1 = y + 1.0;

        final topMid = _interpolateEdgeCollision(px0, py0, px1, py0, sdfTL, sdfTR);
        final rightMid = _interpolateEdgeCollision(px1, py0, px1, py1, sdfTR, sdfBR);
        final bottomMid = _interpolateEdgeCollision(px0, py1, px1, py1, sdfBL, sdfBR);
        final leftMid = _interpolateEdgeCollision(px0, py0, px0, py1, sdfTL, sdfBL);

        List<Offset> edgeVerts;
        switch (index) {
          case 1: edgeVerts = [leftMid, bottomMid]; break;
          case 2: edgeVerts = [bottomMid, rightMid]; break;
          case 3: edgeVerts = [leftMid, rightMid]; break;
          case 4: edgeVerts = [topMid, rightMid]; break;
          case 5: edgeVerts = [topMid, rightMid, bottomMid, leftMid]; break;
          case 6: edgeVerts = [topMid, bottomMid]; break;
          case 7: edgeVerts = [topMid, leftMid]; break;
          case 8: edgeVerts = [topMid, leftMid]; break;
          case 9: edgeVerts = [topMid, bottomMid]; break;
          case 10: edgeVerts = [topMid, rightMid, bottomMid, leftMid]; break;
          case 11: edgeVerts = [topMid, rightMid]; break;
          case 12: edgeVerts = [rightMid, leftMid]; break;
          case 13: edgeVerts = [rightMid, bottomMid]; break;
          case 14: edgeVerts = [bottomMid, leftMid]; break;
          default: continue;
        }

        collisionSegments.add(edgeVerts);
      }
    }

    return collisionSegments;
  }

  /// Micro-detail noise: returns a value in [0, 1] for subtle brightness
  /// variation at sub-cell resolution. Uses two overlapping hash frequencies
  /// to avoid visible grid patterns.
  static double _microNoise(double wx, double wy) {
    final h1 = ((wx * 127.1 + wy * 311.7).abs() % 100) / 100.0;
    final h2 = ((wx * 269.5 + wy * 183.3).abs() % 73) / 73.0;
    return h1 * 0.6 + h2 * 0.4;
  }
}
