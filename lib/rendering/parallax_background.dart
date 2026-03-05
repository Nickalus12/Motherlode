import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

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
    final viewportSize = game.size;
    final depthFeet = game.currentDepthFeet;

    // Sky gradient at surface
    if (depthFeet <= 200) {
      _drawSkyGradient(canvas, viewportSize, depthFeet);
    }

    // Draw parallax layers (far to near)
    for (int layerIdx = 0; layerIdx < _layers.length; layerIdx++) {
      final parallaxFactor = 0.3 + layerIdx * 0.2; // 0.3, 0.5, 0.7
      final opacity = 0.3 + layerIdx * 0.15; // 0.3, 0.45, 0.6

      final offsetX = cameraPos.x * parallaxFactor;
      final offsetY = cameraPos.y * parallaxFactor;

      for (final formation in _layers[layerIdx]) {
        final screenX = formation.x - offsetX;
        final screenY = formation.y - offsetY;

        // Skip if not visible
        if (screenX + formation.width < -viewportSize.x / 2 ||
            screenX - formation.width > viewportSize.x / 2 ||
            screenY + formation.height < -viewportSize.y / 2 ||
            screenY - formation.height > viewportSize.y / 2) {
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

  void _drawSkyGradient(Canvas canvas, Vector2 size, double depthFeet) {
    final skyOpacity = (1.0 - depthFeet / 200).clamp(0.0, 1.0);
    if (skyOpacity <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.from(alpha: skyOpacity, red: 0.33, green: 0.61, blue: 0.89),
        Color.from(alpha: skyOpacity * 0.5, red: 0.56, green: 0.80, blue: 0.93),
      ],
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
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
