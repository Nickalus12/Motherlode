import 'dart:ui';

import 'package:flame/components.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/utils/color_utils.dart';
import 'package:hellbore/utils/constants.dart';

/// Depth-based color grading overlay drawn between terrain and UI
///
/// 1. Depth tint: Color.lerp applied as BlendMode.multiply overlay
/// 2. Atmospheric perspective for distant cave walls
class DepthFog extends Component with HasGameReference<HellboreGame> {
  @override
  int get priority => 50; // Draw above terrain, below HUD

  @override
  void render(Canvas canvas) {
    final depthFeet = game.currentDepthFeet;
    if (depthFeet <= 0) return; // No fog at surface

    final size = game.size;

    // Depth tint overlay
    final fogColor = ColorUtils.getDepthFogColor(depthFeet);
    if (fogColor.a > 0.01) {
      final fogPaint = Paint()
        ..color = fogColor
        ..blendMode = BlendMode.multiply;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        fogPaint,
      );
    }

    // Hell zone: additional red tint
    if (depthFeet >= GameConstants.hellStart) {
      final hellIntensity = ((depthFeet - GameConstants.hellStart) /
              (GameConstants.maxDepth - GameConstants.hellStart))
          .clamp(0.0, 1.0);
      final hellPaint = Paint()
        ..color = Color.from(
          alpha: hellIntensity * 0.15,
          red: 1.0,
          green: 0.0,
          blue: 0.0,
        )
        ..blendMode = BlendMode.overlay;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        hellPaint,
      );
    }

    // Volcanic zone: heat shimmer effect (simplified without GLSL)
    if (depthFeet >= GameConstants.rockEnd) {
      final heatIntensity = ((depthFeet - GameConstants.rockEnd) /
              (GameConstants.volcanicEnd - GameConstants.rockEnd))
          .clamp(0.0, 1.0);
      if (heatIntensity > 0.1) {
        final heatPaint = Paint()
          ..color = Color.from(
            alpha: heatIntensity * 0.05,
            red: 1.0,
            green: 0.5,
            blue: 0.0,
          )
          ..blendMode = BlendMode.softLight;
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.x, size.y),
          heatPaint,
        );
      }
    }
  }
}
