import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import 'package:motherlode/motherlode_game.dart';

/// Lightweight frame-time monitor — debug builds only.
/// Tracks rolling average of frame time, chunk counts, body counts, etc.
class PerfMonitor extends Component with HasGameReference<MotherlodeGame> {
  static const int sampleSize = 60; // 1 second at 60fps
  final List<double> _frameTimes = [];

  double _chunkRenderTime = 0.0;
  double _physicsUpdateTime = 0.0;

  void recordFrame(double dt) {
    if (!kDebugMode) return;
    _frameTimes.add(dt * 1000);
    if (_frameTimes.length > sampleSize) _frameTimes.removeAt(0);
  }

  void recordChunkRenderTime(double ms) {
    _chunkRenderTime = ms;
  }

  void recordPhysicsUpdateTime(double ms) {
    _physicsUpdateTime = ms;
  }

  double get averageFps {
    if (_frameTimes.isEmpty) return 0;
    final avgMs = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
    return avgMs > 0 ? 1000 / avgMs : 0;
  }

  double get averageFrameTimeMs {
    if (_frameTimes.isEmpty) return 0;
    return _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
  }

  @override
  void update(double dt) {
    super.update(dt);
    recordFrame(dt);
  }

  @override
  void render(Canvas canvas) {
    if (!kDebugMode) return;

    final chunkManager = game.chunkManager;
    final particleSystem = game.particleSystem;

    final lines = [
      'FPS: ${averageFps.toStringAsFixed(1)}',
      'Frame: ${averageFrameTimeMs.toStringAsFixed(1)}ms',
      'Chunks: ${chunkManager.loadedChunkCount} loaded / ${chunkManager.dirtyChunkCount} dirty',
      'Particles: ${particleSystem.activeCount}/${particleSystem.pool.capacity}',
      'Render: ${_chunkRenderTime.toStringAsFixed(1)}ms',
      'Physics: ${_physicsUpdateTime.toStringAsFixed(1)}ms',
    ];

    // Background
    final bgPaint = Paint()..color = const Color(0x80000000);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 180, 90),
      bgPaint,
    );

    final textStyle = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 10,
      fontFamily: 'monospace',
    );

    double yOffset = 4;
    for (final line in lines) {
      final builder = ParagraphBuilder(ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: 10,
      ))
        ..pushStyle(textStyle)
        ..addText(line);

      final paragraph = builder.build()
        ..layout(const ParagraphConstraints(width: 176));

      canvas.drawParagraph(paragraph, Offset(4, yOffset));
      yOffset += 13;
    }
  }
}
