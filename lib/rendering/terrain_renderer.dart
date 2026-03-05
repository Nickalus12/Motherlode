import 'dart:ui';

import 'package:flame/components.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/world/chunk.dart';
import 'package:hellbore/world/marching_squares.dart';

/// Renders marching squares mesh per chunk with depth-graded colors
class TerrainRenderer extends Component with HasGameReference<HellboreGame> {
  @override
  void render(Canvas canvas) {
    final chunks = game.chunkManager.activeChunks;

    for (final chunk in chunks) {
      _renderChunk(canvas, chunk);
    }
  }

  void _renderChunk(Canvas canvas, Chunk chunk) {
    final mesh = chunk.meshResult;

    canvas.save();

    // Translate to chunk world position (in tile units, which maps to Forge2D meters)
    canvas.translate(
      chunk.chunkX * GameConstants.chunkSize.toDouble(),
      chunk.chunkY * GameConstants.chunkSize.toDouble(),
    );

    // Draw each polygon from marching squares
    for (final poly in mesh.polygons) {
      // Fill
      final fillPaint = Paint()
        ..color = poly.fillColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(poly.path, fillPaint);

      // Stroke for subtle rock definition
      final strokePaint = Paint()
        ..color = poly.strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = GameConstants.terrainStrokeWidth /
            GameConstants.pixelsPerMeter;
      canvas.drawPath(poly.path, strokePaint);
    }

    canvas.restore();
  }
}
