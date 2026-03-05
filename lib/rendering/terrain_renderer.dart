import 'dart:ui';

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/chunk.dart';

/// Renders marching squares mesh per chunk with depth-graded colors.
/// Uses viewport culling and cached Pictures for performance.
class TerrainRenderer extends Component with HasGameReference<MotherlodeGame> {
  @override
  void render(Canvas canvas) {
    // Only render chunks visible in the camera viewport
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
  }

  /// Get only chunks that overlap the camera viewport
  List<Chunk> _getVisibleChunks() {
    final viewport = game.camera.visibleWorldRect;
    final chunkTileSize = GameConstants.chunkSize.toDouble();

    // Convert world rect to chunk coordinates with 1-chunk buffer
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

  /// Render a dirty chunk, record to Picture, and cache it
  void _renderChunkToCache(Canvas canvas, Chunk chunk) {
    final mesh = chunk.meshResult;

    // Record to a Picture for caching
    final recorder = PictureRecorder();
    final recordCanvas = Canvas(recorder);

    final strokeWidth =
        GameConstants.terrainStrokeWidth / GameConstants.pixelsPerMeter;

    for (final poly in mesh.polygons) {
      // Always draw fill
      final fillPaint = Paint()
        ..color = poly.fillColor
        ..style = PaintingStyle.fill;
      recordCanvas.drawPath(poly.path, fillPaint);

      // Only draw strokes on boundary polygons (where solid meets empty)
      // Interior (case 15) polygons get no stroke to prevent grid lines
      if (!poly.isInterior) {
        final strokePaint = Paint()
          ..color = poly.strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        recordCanvas.drawPath(poly.path, strokePaint);
      }
    }

    final picture = recorder.endRecording();
    chunk.markClean(picture);

    // Draw to the actual canvas
    canvas.save();
    canvas.translate(
      chunk.chunkX * GameConstants.chunkSize.toDouble(),
      chunk.chunkY * GameConstants.chunkSize.toDouble(),
    );
    canvas.drawPicture(picture);
    canvas.restore();
  }
}
