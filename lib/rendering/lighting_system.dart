import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show RadialGradient;

import 'package:motherlode/motherlode_game.dart';

/// Lightweight viewport overlay for gameplay feedback effects.
///
/// Environmental lighting (headlight, darkness, lava glow, depth fog) is now
/// handled entirely by the terrain and background GPU shaders. This component
/// only draws the hull-damage vignette, which is a UI feedback effect that
/// belongs in the viewport layer.
class LightingSystem extends Component with HasGameReference<MotherlodeGame> {
  @override
  int get priority => 80;

  // Pre-allocated Paint objects to avoid per-frame GC pressure
  final _overlayPaint = Paint();

  @override
  void render(Canvas canvas) {
    final size = game.size;
    final viewportRect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Explosion flash/bloom (white overlay that fades)
    final flash = game.earthquakeSystem.explosionFlash;
    if (flash > 0.01) {
      _overlayPaint.shader = null;
      _overlayPaint.color =
          Color.from(alpha: flash * 0.6, red: 1.0, green: 1.0, blue: 0.9);
      canvas.drawRect(viewportRect, _overlayPaint);
    }

    // Hazard screen tints
    if (game.hullSystem.inLava) {
      const lavaGradient = RadialGradient(
        colors: [
          Color(0x00000000),
          Color.from(alpha: 0.35, red: 1.0, green: 0.2, blue: 0.0),
        ],
        radius: 0.9,
      );
      _overlayPaint.shader = lavaGradient.createShader(viewportRect);
      canvas.drawRect(viewportRect, _overlayPaint);
    } else if (game.hullSystem.inGas) {
      const gasGradient = RadialGradient(
        colors: [
          Color(0x00000000),
          Color.from(alpha: 0.25, red: 0.0, green: 1.0, blue: 0.2),
        ],
        radius: 0.9,
      );
      _overlayPaint.shader = gasGradient.createShader(viewportRect);
      canvas.drawRect(viewportRect, _overlayPaint);
    }

    // Hull damage vignette
    final hullRatio = game.hullSystem.hullRatio;
    if (hullRatio >= 0.8) return;

    final vignetteOpacity = (1.0 - hullRatio) * 0.6;
    final vignetteGradient = RadialGradient(
      colors: [
        const Color(0x00000000),
        Color.from(
          alpha: vignetteOpacity,
          red: 1.0,
          green: 0.0,
          blue: 0.0,
        ),
      ],
      radius: 0.8,
    );

    _overlayPaint.shader = vignetteGradient.createShader(viewportRect);
    canvas.drawRect(viewportRect, _overlayPaint);
  }
}
