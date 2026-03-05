import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/utils/constants.dart';

/// Dynamic lighting system drawn as a Canvas layer OVER the terrain
///
/// 1. Darkness overlay (depth-based opacity)
/// 2. Pod headlight (radial gradient cutout)
/// 3. Lava glow (pulsing orange radials)
/// 4. Gas shimmer (faint green bioluminescence)
/// 5. Creature eyes (sharp point lights)
/// 6. Hull damage vignette
class LightingSystem extends Component with HasGameReference<HellboreGame> {
  @override
  int get priority => 80; // Draw above terrain and fog, below HUD

  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final depthFeet = game.currentDepthFeet;
    if (depthFeet <= 0) return; // No darkness at surface

    final size = game.size;
    final viewportRect = Rect.fromLTWH(0, 0, size.x, size.y);

    // 1. Dark overlay
    final darknessOpacity =
        (depthFeet / GameConstants.maxDepth * GameConstants.maxDarknessOpacity)
            .clamp(0.0, GameConstants.maxDarknessOpacity);

    // Save layer for compositing
    canvas.saveLayer(viewportRect, Paint());

    // Fill with darkness
    final darkPaint = Paint()
      ..color = Color.from(
        alpha: darknessOpacity,
        red: 0.0,
        green: 0.0,
        blue: 0.0,
      );
    canvas.drawRect(viewportRect, darkPaint);

    // 2. Cut out pod headlight using dstOut blend mode
    final podScreenPos = _getPodScreenPosition();
    final lightRadius = GameConstants.podLightBaseRadius +
        game.engineLevel * GameConstants.podLightPerLevel;

    final lightGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        const Color(0xFFFFFFFF), // Fully transparent center (will punch through)
        const Color(0x00FFFFFF), // Fade to nothing at edge
      ],
      stops: const [0.0, 1.0],
    );

    final lightRect = Rect.fromCircle(
      center: podScreenPos,
      radius: lightRadius,
    );

    final lightPaint = Paint()
      ..shader = lightGradient.createShader(lightRect)
      ..blendMode = BlendMode.dstOut;

    canvas.drawCircle(podScreenPos, lightRadius, lightPaint);

    // 3. Lava glow points (punch additional light holes)
    _renderLavaGlow(canvas, darknessOpacity);

    // 4. Gas shimmer
    _renderGasShimmer(canvas);

    // Restore composited layer
    canvas.restore();

    // 5. Hull damage vignette (drawn separately on top)
    _renderHullVignette(canvas, viewportRect);

    // 6. Hell zone red ambient
    if (depthFeet >= GameConstants.hellStart) {
      final hellIntensity = ((depthFeet - GameConstants.hellStart) /
              (GameConstants.maxDepth - GameConstants.hellStart))
          .clamp(0.0, 1.0);

      final redPulse = sin(_time * 2.0) * 0.02;
      canvas.drawRect(
        viewportRect,
        Paint()
          ..color = Color.from(
            alpha: (hellIntensity * 0.1 + redPulse).clamp(0.0, 1.0),
            red: 1.0,
            green: 0.0,
            blue: 0.0,
          )
          ..blendMode = BlendMode.overlay,
      );
    }
  }

  Offset _getPodScreenPosition() {
    // Pod is always at center of viewport since camera follows it
    final size = game.size;
    return Offset(size.x / 2, size.y / 2);
  }

  void _renderLavaGlow(Canvas canvas, double darknessOpacity) {
    // Scan cells around the pod for lava
    final podX = game.pod.position.x.round();
    final podY = game.pod.position.y.round();
    final screenCenter = _getPodScreenPosition();

    for (int dy = -8; dy <= 8; dy++) {
      for (int dx = -8; dx <= 8; dx++) {
        final cellType = game.getCellType(podX + dx, podY + dy);
        if (cellType == 5) {
          // CellType.lava
          // Calculate screen position relative to pod
          final screenX = screenCenter.dx +
              dx * GameConstants.pixelsPerMeter;
          final screenY = screenCenter.dy +
              dy * GameConstants.pixelsPerMeter;

          final pulseRadius =
              15 + 5 * sin(_time * 3.0 + dx * 0.5 + dy * 0.3);

          final lavaGradient = RadialGradient(
            colors: [
              Color.from(alpha: 0.6, red: 1.0, green: 0.3, blue: 0.0),
              const Color(0x00000000),
            ],
          );

          final lavaRect = Rect.fromCircle(
            center: Offset(screenX, screenY),
            radius: pulseRadius,
          );

          final lavaPaint = Paint()
            ..shader = lavaGradient.createShader(lavaRect)
            ..blendMode = BlendMode.dstOut;

          canvas.drawCircle(
            Offset(screenX, screenY),
            pulseRadius,
            lavaPaint,
          );
        }
      }
    }
  }

  void _renderGasShimmer(Canvas canvas) {
    final podX = game.pod.position.x.round();
    final podY = game.pod.position.y.round();
    final screenCenter = _getPodScreenPosition();

    for (int dy = -6; dy <= 6; dy++) {
      for (int dx = -6; dx <= 6; dx++) {
        final cellType = game.getCellType(podX + dx, podY + dy);
        if (cellType == 6) {
          // CellType.gas
          final screenX = screenCenter.dx +
              dx * GameConstants.pixelsPerMeter;
          final screenY = screenCenter.dy +
              dy * GameConstants.pixelsPerMeter;

          final shimmerRadius =
              20 + 8 * sin(_time * 1.5 + dx * 0.7 + dy * 0.5);

          final gasGradient = RadialGradient(
            colors: [
              Color.from(alpha: 0.2, red: 0.0, green: 1.0, blue: 0.3),
              const Color(0x00000000),
            ],
          );

          final gasRect = Rect.fromCircle(
            center: Offset(screenX, screenY),
            radius: shimmerRadius,
          );

          final gasPaint = Paint()
            ..shader = gasGradient.createShader(gasRect)
            ..blendMode = BlendMode.dstOut;

          canvas.drawCircle(
            Offset(screenX, screenY),
            shimmerRadius,
            gasPaint,
          );
        }
      }
    }
  }

  void _renderHullVignette(Canvas canvas, Rect viewportRect) {
    final hullRatio = game.hullSystem.hullRatio;
    if (hullRatio >= 0.8) return;

    final vignetteOpacity = (1.0 - hullRatio) * 0.6;
    final vignetteGradient = RadialGradient(
      colors: [
        Colors.transparent,
        Color.from(
          alpha: vignetteOpacity,
          red: 1.0,
          green: 0.0,
          blue: 0.0,
        ),
      ],
      radius: 0.8,
    );

    canvas.drawRect(
      viewportRect,
      Paint()..shader = vignetteGradient.createShader(viewportRect),
    );
  }
}
