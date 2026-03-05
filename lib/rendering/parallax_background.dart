import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/color_utils.dart';
import 'package:motherlode/utils/constants.dart';

/// Multi-layer parallax cave walls for background depth
class ParallaxBackground extends Component
    with HasGameReference<MotherlodeGame> {
  @override
  int get priority => -10; // Draw behind terrain

  // Pre-generated rock formations for each layer
  final List<List<_RockFormation>> _layers = [];
  bool _initialized = false;

  void _initialize() {
    if (_initialized) return;
    _initialized = true;

    final random = Random(42); // Fixed seed for consistent parallax

    // Generate 3 parallax layers (far, mid, near)
    for (int layer = 0; layer < 3; layer++) {
      final formations = <_RockFormation>[];
      final count = 20 + layer * 10;

      for (int i = 0; i < count; i++) {
        formations.add(_RockFormation(
          x: random.nextDouble() * 2000 - 1000,
          y: random.nextDouble() * 10000,
          width: 20 + random.nextDouble() * 60,
          height: 30 + random.nextDouble() * 80,
          seed: random.nextInt(10000),
        ));
      }
      _layers.add(formations);
    }
  }

  @override
  void render(Canvas canvas) {
    _initialize();

    final cameraPos = game.camera.viewfinder.position;
    final visibleRect = game.camera.visibleWorldRect;
    final depthFeet = game.currentDepthFeet;

    // Underground fill: dark brown/black behind terrain to prevent sky bleed
    final groundTop = 0.0; // y=0 is surface
    if (visibleRect.bottom > groundTop) {
      final groundRect = Rect.fromLTRB(
        visibleRect.left,
        groundTop.clamp(visibleRect.top, visibleRect.bottom),
        visibleRect.right,
        visibleRect.bottom,
      );
      final groundGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF3D2810), // Brown at surface
          const Color(0xFF1A0D05), // Dark brown deeper
          const Color(0xFF0A0505), // Near black
        ],
        stops: const [0.0, 0.3, 1.0],
      );
      canvas.drawRect(
        groundRect,
        Paint()..shader = groundGradient.createShader(groundRect),
      );
    }

    // Sky gradient ONLY above ground level
    if (visibleRect.top < groundTop) {
      final skyRect = Rect.fromLTRB(
        visibleRect.left,
        visibleRect.top,
        visibleRect.right,
        groundTop.clamp(visibleRect.top, visibleRect.bottom),
      );
      final skyOpacity = (1.0 - depthFeet / 200).clamp(0.0, 1.0);
      if (skyOpacity > 0) {
        final gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.from(alpha: skyOpacity, red: 0.2, green: 0.45, blue: 0.75),
            Color.from(alpha: skyOpacity, red: 0.5, green: 0.7, blue: 0.9),
          ],
        );
        canvas.drawRect(
          skyRect,
          Paint()..shader = gradient.createShader(skyRect),
        );
      }
    }

    // Draw parallax layers (far to near)
    for (int layerIdx = 0; layerIdx < _layers.length; layerIdx++) {
      final parallaxFactor = 0.3 + layerIdx * 0.2;
      final opacity = 0.3 + layerIdx * 0.15;

      final shiftX = cameraPos.x * (1 - parallaxFactor);
      final shiftY = cameraPos.y * (1 - parallaxFactor);

      for (final formation in _layers[layerIdx]) {
        final screenX = formation.x + shiftX;
        final screenY = formation.y + shiftY;

        if (screenX + formation.width < visibleRect.left ||
            screenX - formation.width > visibleRect.right ||
            screenY + formation.height < visibleRect.top ||
            screenY - formation.height > visibleRect.bottom) {
          continue;
        }

        final formationDepth = formation.y * GameConstants.feetPerTile;
        final baseColor = ColorUtils.getTerrainColor(formationDepth);
        final color = ColorUtils.darken(baseColor, 0.3 + (1 - opacity) * 0.2);

        _drawFormation(canvas, formation, screenX, screenY,
            color.withValues(alpha: opacity));
      }
    }
  }

  void _drawFormation(
    Canvas canvas,
    _RockFormation formation,
    double x,
    double y,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw a simple jagged rock formation using Path
    final path = Path();
    final random = Random(formation.seed);
    final w = formation.width;
    final h = formation.height;

    path.moveTo(x, y + h);
    path.lineTo(x + w * 0.1, y + h * (0.3 + random.nextDouble() * 0.2));
    path.lineTo(x + w * 0.3, y + h * (0.1 + random.nextDouble() * 0.2));
    path.lineTo(x + w * 0.5, y);
    path.lineTo(x + w * 0.7, y + h * (0.15 + random.nextDouble() * 0.2));
    path.lineTo(x + w * 0.9, y + h * (0.3 + random.nextDouble() * 0.2));
    path.lineTo(x + w, y + h);
    path.close();

    canvas.drawPath(path, paint);
  }
}

class _RockFormation {
  final double x;
  final double y;
  final double width;
  final double height;
  final int seed;

  const _RockFormation({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.seed,
  });
}
