import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/color_utils.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/chunk.dart';
import 'package:motherlode/world/terrain_cell.dart';


/// Renders marching squares mesh per chunk with depth-graded colors,
/// procedural textures (dirt speckles, rock grain, sediment layers),
/// ambient occlusion, ore glow, grass blades, and edge highlights.
class TerrainRenderer extends Component with HasGameReference<MotherlodeGame> {
  double _time = 0;

  // Cached grass blade data per chunk (to avoid re-generating each frame)
  final Map<String, List<_GrassBlade>> _grassCache = {};

  // Cached procedural detail data per chunk
  final Map<String, List<_TerrainDetail>> _detailCache = {};

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final visibleChunks = _getVisibleChunks();

    for (final chunk in visibleChunks) {
      if (chunk.isDirty || chunk.cachedPicture == null) {
        _renderChunkToCache(canvas, chunk);
      } else {
        canvas.save();
        canvas.translate(
          chunk.chunkX * GameConstants.chunkSize.toDouble(),
          chunk.chunkY * GameConstants.chunkSize.toDouble(),
        );
        canvas.drawPicture(chunk.cachedPicture!);
        canvas.restore();
      }
    }

    // Render animated effects on top (not cached)
    _renderAnimatedEffects(canvas, visibleChunks);
  }

  List<Chunk> _getVisibleChunks() {
    final viewport = game.camera.visibleWorldRect;
    final chunkTileSize = GameConstants.chunkSize.toDouble();

    final minChunkX = (viewport.left / chunkTileSize).floor() - 1;
    final maxChunkX = (viewport.right / chunkTileSize).ceil() + 1;
    final minChunkY = (viewport.top / chunkTileSize).floor() - 1;
    final maxChunkY = (viewport.bottom / chunkTileSize).ceil() + 1;

    final visible = <Chunk>[];
    for (int x = minChunkX; x <= maxChunkX; x++) {
      for (int y = minChunkY; y <= maxChunkY; y++) {
        final chunk = game.chunkManager.getLoadedChunk(x, y);
        if (chunk != null) visible.add(chunk);
      }
    }
    return visible;
  }

  /// Render a dirty chunk with AO, procedural textures, edge highlights, grass.
  void _renderChunkToCache(Canvas canvas, Chunk chunk) {
    final mesh = chunk.meshResult;

    final recorder = PictureRecorder();
    final recordCanvas = Canvas(recorder);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final chunkWorldX = chunk.chunkX * GameConstants.chunkSize;
    final chunkWorldY = chunk.chunkY * GameConstants.chunkSize;

    for (final poly in mesh.polygons) {
      // Fill the polygon
      fillPaint.color = poly.fillColor;
      recordCanvas.drawPath(poly.path, fillPaint);

      if (!poly.isInterior) {
        // Soft ambient occlusion — wider dark stroke for depth
        final aoColor = ColorUtils.darken(poly.fillColor, 0.3);
        edgePaint.color = aoColor.withValues(alpha: 0.3);
        edgePaint.strokeWidth = 0.08;
        recordCanvas.drawPath(poly.path, edgePaint);

        // Second softer AO layer for smooth falloff
        edgePaint.color = aoColor.withValues(alpha: 0.15);
        edgePaint.strokeWidth = 0.14;
        recordCanvas.drawPath(poly.path, edgePaint);

        // Warm highlight on surface-facing edges
        final highlight = ColorUtils.brighten(poly.fillColor, 0.1);
        edgePaint.color = highlight.withValues(alpha: 0.12);
        edgePaint.strokeWidth = 0.04;
        recordCanvas.drawPath(poly.path, edgePaint);
      }
    }

    // Procedural texture details (dirt speckles, rock grain, sediment lines)
    _renderTextureDetails(recordCanvas, chunk, chunkWorldX, chunkWorldY, fillPaint);

    // Draw grass blades on surface polygons
    _renderGrassOnChunk(recordCanvas, chunk, chunkWorldY, fillPaint);

    final picture = recorder.endRecording();
    chunk.markClean(picture);

    canvas.save();
    canvas.translate(
      chunk.chunkX * GameConstants.chunkSize.toDouble(),
      chunk.chunkY * GameConstants.chunkSize.toDouble(),
    );
    canvas.drawPicture(picture);
    canvas.restore();
  }

  /// Render procedural texture details: dirt speckles, rock grain, sediment layers.
  void _renderTextureDetails(
    Canvas canvas,
    Chunk chunk,
    int chunkWorldX,
    int chunkWorldY,
    Paint paint,
  ) {
    final chunkKey = '${chunk.chunkX},${chunk.chunkY}';
    const chunkSize = GameConstants.chunkSize;

    // Regenerate detail cache if chunk is dirty
    if (!_detailCache.containsKey(chunkKey) || chunk.isDirty) {
      final details = <_TerrainDetail>[];
      final rng = Random(chunk.chunkX * 7919 + chunk.chunkY * 6271);

      for (int y = 0; y < chunkSize; y++) {
        for (int x = 0; x < chunkSize; x++) {
          final cell = chunk.cells[y][x];
          if (!cell.isSolid) continue;

          final worldY = (chunkWorldY + y) * GameConstants.feetPerTile;

          // Different detail types based on cell type / depth
          switch (cell.type) {
            case CellType.sand:
              // Sandy speckles — many small dots
              final count = 3 + rng.nextInt(4);
              for (int i = 0; i < count; i++) {
                details.add(_TerrainDetail(
                  x: x + 0.1 + rng.nextDouble() * 0.8,
                  y: y + 0.1 + rng.nextDouble() * 0.8,
                  size: 0.02 + rng.nextDouble() * 0.04,
                  type: _DetailType.speckle,
                  brightness: (rng.nextDouble() - 0.5) * 0.15,
                ));
              }
              break;

            case CellType.dirt:
              // Dirt: mix of speckles and small pebbles
              final count = 2 + rng.nextInt(3);
              for (int i = 0; i < count; i++) {
                final isPebble = rng.nextDouble() > 0.6;
                details.add(_TerrainDetail(
                  x: x + 0.1 + rng.nextDouble() * 0.8,
                  y: y + 0.1 + rng.nextDouble() * 0.8,
                  size: isPebble
                      ? 0.04 + rng.nextDouble() * 0.06
                      : 0.02 + rng.nextDouble() * 0.03,
                  type: isPebble ? _DetailType.pebble : _DetailType.speckle,
                  brightness: (rng.nextDouble() - 0.5) * 0.12,
                ));
              }
              // Occasional root/worm line in shallow dirt
              if (worldY < 500 && rng.nextDouble() > 0.85) {
                details.add(_TerrainDetail(
                  x: x + 0.15 + rng.nextDouble() * 0.3,
                  y: y + 0.2 + rng.nextDouble() * 0.6,
                  size: 0.3 + rng.nextDouble() * 0.4,
                  type: _DetailType.rootLine,
                  brightness: -0.08 - rng.nextDouble() * 0.06,
                  angle: (rng.nextDouble() - 0.5) * 1.2,
                ));
              }
              break;

            case CellType.rock:
              // Rock: grain lines and crystal flecks
              if (rng.nextDouble() > 0.5) {
                details.add(_TerrainDetail(
                  x: x + 0.1 + rng.nextDouble() * 0.3,
                  y: y + 0.1 + rng.nextDouble() * 0.8,
                  size: 0.3 + rng.nextDouble() * 0.5,
                  type: _DetailType.grainLine,
                  brightness: (rng.nextDouble() - 0.5) * 0.08,
                  angle: (rng.nextDouble() - 0.5) * 0.6,
                ));
              }
              // Small mineral flecks
              final fleckCount = 1 + rng.nextInt(2);
              for (int i = 0; i < fleckCount; i++) {
                details.add(_TerrainDetail(
                  x: x + 0.1 + rng.nextDouble() * 0.8,
                  y: y + 0.1 + rng.nextDouble() * 0.8,
                  size: 0.015 + rng.nextDouble() * 0.025,
                  type: _DetailType.mineralFleck,
                  brightness: 0.1 + rng.nextDouble() * 0.15,
                ));
              }
              break;

            case CellType.obsidian:
              // Obsidian: sharp fracture lines and glass sheen
              if (rng.nextDouble() > 0.6) {
                details.add(_TerrainDetail(
                  x: x + rng.nextDouble() * 0.5,
                  y: y + rng.nextDouble() * 0.5,
                  size: 0.4 + rng.nextDouble() * 0.5,
                  type: _DetailType.fractureLine,
                  brightness: 0.06 + rng.nextDouble() * 0.08,
                  angle: rng.nextDouble() * 3.14,
                ));
              }
              break;

            default:
              break;
          }

          // Universal: sediment layer lines at stratum boundaries
          // Thin horizontal bands that suggest geological layering
          final depthHash = ((worldY * 0.07).floor() % 5);
          if (depthHash == 0 && rng.nextDouble() > 0.7) {
            details.add(_TerrainDetail(
              x: x.toDouble(),
              y: y + 0.3 + rng.nextDouble() * 0.4,
              size: 0.8 + rng.nextDouble() * 0.2,
              type: _DetailType.sedimentLine,
              brightness: (rng.nextDouble() - 0.5) * 0.06,
            ));
          }
        }
      }
      _detailCache[chunkKey] = details;
    }

    final details = _detailCache[chunkKey]!;
    if (details.isEmpty) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round;

    for (final d in details) {
      // Get the base color of the cell at this position
      final cellX = d.x.floor().clamp(0, chunkSize - 1);
      final cellY = d.y.floor().clamp(0, chunkSize - 1);
      final cell = chunk.cells[cellY][cellX];
      if (!cell.isSolid) continue;

      final baseColor = cell.baseColor;

      switch (d.type) {
        case _DetailType.speckle:
          paint.color = d.brightness > 0
              ? ColorUtils.brighten(baseColor, d.brightness)
                  .withValues(alpha: 0.5)
              : ColorUtils.darken(baseColor, -d.brightness)
                  .withValues(alpha: 0.5);
          canvas.drawCircle(Offset(d.x, d.y), d.size, paint);
          break;

        case _DetailType.pebble:
          paint.color = ColorUtils.darken(baseColor, 0.15 - d.brightness)
              .withValues(alpha: 0.45);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(d.x, d.y),
              width: d.size * 1.3,
              height: d.size * 0.9,
            ),
            paint,
          );
          // Tiny highlight on pebble
          paint.color = ColorUtils.brighten(baseColor, 0.2)
              .withValues(alpha: 0.2);
          canvas.drawCircle(
            Offset(d.x - d.size * 0.2, d.y - d.size * 0.2),
            d.size * 0.3,
            paint,
          );
          break;

        case _DetailType.rootLine:
          linePaint.color = ColorUtils.darken(baseColor, 0.2)
              .withValues(alpha: 0.3);
          linePaint.strokeWidth = 0.02;
          final path = Path();
          path.moveTo(d.x, d.y);
          final endX = d.x + cos(d.angle) * d.size;
          final endY = d.y + sin(d.angle) * d.size;
          final midX = (d.x + endX) / 2 + sin(d.angle) * 0.08;
          final midY = (d.y + endY) / 2 + cos(d.angle) * 0.08;
          path.quadraticBezierTo(midX, midY, endX, endY);
          canvas.drawPath(path, linePaint);
          break;

        case _DetailType.grainLine:
          linePaint.color = d.brightness > 0
              ? ColorUtils.brighten(baseColor, d.brightness)
                  .withValues(alpha: 0.2)
              : ColorUtils.darken(baseColor, -d.brightness)
                  .withValues(alpha: 0.2);
          linePaint.strokeWidth = 0.015;
          final path = Path();
          path.moveTo(d.x, d.y);
          path.lineTo(
            d.x + cos(d.angle) * d.size,
            d.y + sin(d.angle) * d.size,
          );
          canvas.drawPath(path, linePaint);
          break;

        case _DetailType.mineralFleck:
          paint.color = ColorUtils.brighten(baseColor, d.brightness)
              .withValues(alpha: 0.6);
          canvas.drawCircle(Offset(d.x, d.y), d.size, paint);
          break;

        case _DetailType.fractureLine:
          linePaint.color = ColorUtils.brighten(baseColor, d.brightness)
              .withValues(alpha: 0.25);
          linePaint.strokeWidth = 0.01;
          final path = Path();
          path.moveTo(d.x, d.y);
          // Jagged fracture with 2-3 segments
          final segments = 2 + (d.size * 3).floor();
          double cx = d.x, cy = d.y;
          final segLen = d.size / segments;
          final rng2 = Random((d.x * 100 + d.y * 77).toInt());
          for (int s = 0; s < segments; s++) {
            cx += cos(d.angle + (rng2.nextDouble() - 0.5) * 1.0) * segLen;
            cy += sin(d.angle + (rng2.nextDouble() - 0.5) * 1.0) * segLen;
            path.lineTo(cx, cy);
          }
          canvas.drawPath(path, linePaint);
          break;

        case _DetailType.sedimentLine:
          linePaint.color = d.brightness > 0
              ? ColorUtils.brighten(baseColor, d.brightness)
                  .withValues(alpha: 0.12)
              : ColorUtils.darken(baseColor, -d.brightness)
                  .withValues(alpha: 0.12);
          linePaint.strokeWidth = 0.02;
          canvas.drawLine(
            Offset(d.x, d.y),
            Offset(d.x + d.size, d.y + 0.02),
            linePaint,
          );
          break;
      }
    }
  }

  /// Draw grass blades on top of surface-facing terrain edges.
  void _renderGrassOnChunk(
    Canvas canvas,
    Chunk chunk,
    int chunkWorldY,
    Paint paint,
  ) {
    final chunkKey = '${chunk.chunkX},${chunk.chunkY}';
    const chunkSize = GameConstants.chunkSize;

    // Only generate grass near the surface (within first few chunks)
    final depthAtTop = chunkWorldY * GameConstants.feetPerTile;
    if (depthAtTop > GameConstants.grassDepthThreshold + 100 || depthAtTop < -200) {
      _grassCache.remove(chunkKey);
      return;
    }

    // Check cache
    if (!_grassCache.containsKey(chunkKey) || chunk.isDirty) {
      final blades = <_GrassBlade>[];
      final rng = Random(chunk.chunkX * 1000 + chunk.chunkY);

      // Scan cells to find grass-eligible surfaces
      for (int y = 0; y < chunkSize - 1; y++) {
        for (int x = 0; x < chunkSize - 1; x++) {
          final cell = chunk.cells[y][x];
          final cellAbove = y > 0 ? chunk.cells[y - 1][x] : null;

          // Grass grows where solid meets air above
          if (cell.isSolid && (cellAbove == null || !cellAbove.isSolid)) {
            final worldY = (chunkWorldY + y) * GameConstants.feetPerTile;
            if (!ColorUtils.isGrassSurface(worldY)) continue;

            // Generate 2-4 grass blades per surface cell
            final bladeCount = 2 + rng.nextInt(3);
            for (int b = 0; b < bladeCount; b++) {
              final bx = x + 0.1 + rng.nextDouble() * 0.8;
              // Place blades at the top edge of the cell
              final by = y.toDouble() - 0.02;
              final height = 0.15 + rng.nextDouble() * 0.35;
              final lean = (rng.nextDouble() - 0.5) * 0.3;
              final shade = rng.nextDouble();

              blades.add(_GrassBlade(
                x: bx,
                y: by,
                height: height,
                lean: lean,
                shade: shade,
              ));
            }
          }
        }
      }
      _grassCache[chunkKey] = blades;
    }

    final blades = _grassCache[chunkKey]!;
    if (blades.isEmpty) return;

    for (final blade in blades) {
      // Wind sway with varied frequency per blade
      final sway = sin(_time * (1.2 + blade.shade * 0.8) + blade.x * 3.7 + blade.y * 2.3) * 0.06;
      final tipX = blade.x + blade.lean + sway;
      final tipY = blade.y - blade.height;

      // Color varies between dark green, bright green, yellow-green
      Color bladeColor;
      if (blade.shade < 0.2) {
        bladeColor = const Color(0xFF1B5E20); // Deep forest green
      } else if (blade.shade < 0.4) {
        bladeColor = const Color(0xFF2E7D32); // Dark green
      } else if (blade.shade < 0.65) {
        bladeColor = const Color(0xFF4CAF50); // Medium green
      } else if (blade.shade < 0.85) {
        bladeColor = const Color(0xFF66BB6A); // Light green
      } else {
        bladeColor = const Color(0xFF7CB342); // Yellow-green
      }

      // Draw blade as a curved quadratic bezier for natural look
      final baseWidth = 0.03 + blade.height * 0.06; // Wider base for taller blades
      final midX = blade.x + blade.lean * 0.4 + sway * 0.3;
      final midY = blade.y - blade.height * 0.55;

      final path = Path();
      path.moveTo(blade.x - baseWidth, blade.y);
      // Left edge curves outward slightly
      path.quadraticBezierTo(midX - baseWidth * 0.3, midY, tipX, tipY);
      // Right edge curves back
      path.quadraticBezierTo(midX + baseWidth * 0.3, midY, blade.x + baseWidth, blade.y);
      path.close();

      paint.color = bladeColor;
      canvas.drawPath(path, paint);

      // Subtle highlight on the left side of the blade
      if (blade.height > 0.25) {
        paint.color = ColorUtils.brighten(bladeColor, 0.2).withValues(alpha: 0.3);
        final hlPath = Path();
        hlPath.moveTo(blade.x - baseWidth * 0.5, blade.y);
        hlPath.quadraticBezierTo(midX - baseWidth * 0.5, midY + blade.height * 0.1, tipX, tipY);
        hlPath.lineTo(midX, midY);
        hlPath.close();
        canvas.drawPath(hlPath, paint);
      }
    }
  }

  /// Render animated per-frame effects that shouldn't be cached.
  void _renderAnimatedEffects(Canvas canvas, List<Chunk> visibleChunks) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final chunk in visibleChunks) {
      final chunkOffsetX = chunk.chunkX * GameConstants.chunkSize.toDouble();
      final chunkOffsetY = chunk.chunkY * GameConstants.chunkSize.toDouble();

      for (final poly in chunk.meshResult.polygons) {
        // Ore shimmer
        if (poly.isOre) {
          final shimmer =
              (sin(_time * 2.0 + poly.fillColor.r * 20) * 0.5 + 0.5);
          final glowAlpha = 0.05 + shimmer * 0.1;
          paint.color = ColorUtils.brighten(poly.fillColor, 0.4)
              .withValues(alpha: glowAlpha);

          canvas.save();
          canvas.translate(chunkOffsetX, chunkOffsetY);
          canvas.drawPath(poly.path, paint);
          canvas.restore();
        }

        // Lava glow
        if (poly.isLava) {
          final pulse = sin(_time * 1.5 + chunkOffsetX * 0.1) * 0.5 + 0.5;
          paint.color = Color.from(
            alpha: 0.1 + pulse * 0.15,
            red: 1.0,
            green: 0.3 + pulse * 0.2,
            blue: 0.0,
          );

          canvas.save();
          canvas.translate(chunkOffsetX, chunkOffsetY);
          canvas.drawPath(poly.path, paint);
          canvas.restore();
        }
      }
    }
  }
}

/// A single grass blade with position and visual properties
class _GrassBlade {
  final double x, y, height, lean, shade;
  const _GrassBlade({
    required this.x,
    required this.y,
    required this.height,
    required this.lean,
    required this.shade,
  });
}

/// Types of procedural terrain detail
enum _DetailType {
  speckle,       // Tiny dots (sand grains, dirt particles)
  pebble,        // Small oval stones
  rootLine,      // Curved organic lines (roots, worms in shallow dirt)
  grainLine,     // Straight rock grain / stratification lines
  mineralFleck,  // Bright tiny dots (crystal/mineral inclusions in rock)
  fractureLine,  // Jagged cracks in obsidian/hard rock
  sedimentLine,  // Horizontal layer boundary lines
}

/// A single procedural terrain detail element
class _TerrainDetail {
  final double x, y, size;
  final _DetailType type;
  final double brightness; // Positive = lighter, negative = darker
  final double angle;      // Rotation for lines

  const _TerrainDetail({
    required this.x,
    required this.y,
    required this.size,
    required this.type,
    this.brightness = 0.0,
    this.angle = 0.0,
  });
}
