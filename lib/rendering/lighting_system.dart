import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show RadialGradient, Alignment;

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Viewport overlay for gameplay feedback effects.
///
/// Environmental lighting (headlight, darkness, lava glow, depth fog) is handled
/// by the terrain and background GPU shaders. This component draws:
/// - Hull-damage pulsing red vignette (heartbeat effect)
/// - Low-fuel amber warning overlay (breathing pulse)
/// - Depth-based darkness overlay
/// - Ore collection golden flash
/// - Underwater caustic shimmer near water table
/// - Smooth hazard state transitions (lava/gas tints)
class LightingSystem extends Component with HasGameReference<MotherlodeGame> {
  @override
  int get priority => 80;

  // Pre-allocated Paint objects — zero GC pressure per frame
  final _overlayPaint = Paint();
  final _flashPaint = Paint();

  // Accumulated time for animated effects
  double _time = 0;

  // Smooth hazard transition state (0.0 = off, 1.0 = full)
  double _lavaIntensity = 0;
  double _gasIntensity = 0;

  // Ore collection flash
  double _oreFlash = 0;

  // Transition speed (per second)
  static const double _hazardFadeInSpeed = 3.0;
  static const double _hazardFadeOutSpeed = 2.0;
  static const double _oreFlashDecay = 4.0;

  /// Trigger a brief golden flash for ore collection feedback.
  void triggerOreFlash() {
    _oreFlash = 1.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Smooth hazard transitions
    final targetLava = game.hullSystem.inLava ? 1.0 : 0.0;
    final targetGas = game.hullSystem.inGas ? 1.0 : 0.0;

    if (_lavaIntensity < targetLava) {
      _lavaIntensity =
          (_lavaIntensity + dt * _hazardFadeInSpeed).clamp(0.0, 1.0);
    } else if (_lavaIntensity > targetLava) {
      _lavaIntensity =
          (_lavaIntensity - dt * _hazardFadeOutSpeed).clamp(0.0, 1.0);
    }

    if (_gasIntensity < targetGas) {
      _gasIntensity = (_gasIntensity + dt * _hazardFadeInSpeed).clamp(0.0, 1.0);
    } else if (_gasIntensity > targetGas) {
      _gasIntensity =
          (_gasIntensity - dt * _hazardFadeOutSpeed).clamp(0.0, 1.0);
    }

    // Decay ore flash
    if (_oreFlash > 0) {
      _oreFlash = (_oreFlash - dt * _oreFlashDecay).clamp(0.0, 1.0);
    }
  }

  @override
  void render(Canvas canvas) {
    final size = game.size;
    final viewportRect = Rect.fromLTWH(0, 0, size.x, size.y);

    // 1. Depth-based darkness overlay
    _renderDepthDarkness(canvas, viewportRect);

    // 2. Explosion flash/bloom
    _renderExplosionFlash(canvas, viewportRect);

    // 3. Hazard screen tints (smooth transitions)
    _renderHazardTints(canvas, viewportRect);

    // 4. Hull damage pulsing vignette
    _renderHullVignette(canvas, viewportRect);

    // 5. Low fuel amber warning
    _renderFuelWarning(canvas, viewportRect);

    // 6. Ore collection flash
    _renderOreFlash(canvas, viewportRect);

    // 7. Underwater caustic shimmer
    _renderCaustics(canvas, viewportRect);
  }

  /// Subtle blue-black overlay that deepens with depth.
  void _renderDepthDarkness(Canvas canvas, Rect rect) {
    final depth = game.depthSystem.normalizedDepth; // 0..1
    if (depth < 0.02) return;

    // Ramp from 0 to ~0.25 opacity over depth, with diminishing returns
    final darkness = (depth * 0.35).clamp(0.0, 0.25);

    _overlayPaint.shader = null;
    _overlayPaint.color = Color.from(
      alpha: darkness,
      red: 0.02,
      green: 0.02,
      blue: 0.08,
    );
    canvas.drawRect(rect, _overlayPaint);
  }

  /// White explosion flash from earthquake system.
  void _renderExplosionFlash(Canvas canvas, Rect rect) {
    final flash = game.earthquakeSystem.explosionFlash;
    if (flash <= 0.01) return;

    _overlayPaint.shader = null;
    _overlayPaint.color =
        Color.from(alpha: flash * 0.6, red: 1.0, green: 1.0, blue: 0.9);
    canvas.drawRect(rect, _overlayPaint);
  }

  /// Lava and gas tints with smooth fade in/out.
  void _renderHazardTints(Canvas canvas, Rect rect) {
    if (_lavaIntensity > 0.01) {
      final lavaAlpha = 0.35 * _lavaIntensity;
      final lavaGradient = RadialGradient(
        colors: [
          const Color(0x00000000),
          Color.from(alpha: lavaAlpha, red: 1.0, green: 0.2, blue: 0.0),
        ],
        radius: 0.9,
      );
      _overlayPaint.shader = lavaGradient.createShader(rect);
      canvas.drawRect(rect, _overlayPaint);
    }

    if (_gasIntensity > 0.01) {
      final gasAlpha = 0.25 * _gasIntensity;
      final gasGradient = RadialGradient(
        colors: [
          const Color(0x00000000),
          Color.from(alpha: gasAlpha, red: 0.0, green: 1.0, blue: 0.2),
        ],
        radius: 0.9,
      );
      _overlayPaint.shader = gasGradient.createShader(rect);
      canvas.drawRect(rect, _overlayPaint);
    }
  }

  /// Hull damage vignette with heartbeat pulse that speeds up as hull drops.
  void _renderHullVignette(Canvas canvas, Rect rect) {
    final hullRatio = game.hullSystem.hullRatio;
    if (hullRatio >= 0.8) return;

    // Base opacity increases as hull decreases
    final baseOpacity = (1.0 - hullRatio) * 0.6;

    // Heartbeat pulse: speed increases as hull drops
    // At 80% hull: slow pulse (~1 Hz), at 0%: fast pulse (~4 Hz)
    final pulseFreq = 1.0 + (1.0 - hullRatio) * 3.0;
    // Double-beat heartbeat pattern: two quick pulses then pause
    final beat1 = math.sin(_time * pulseFreq * math.pi * 2.0).clamp(0.0, 1.0);
    final beat2 =
        math.sin(_time * pulseFreq * math.pi * 2.0 + 0.6).clamp(0.0, 1.0);
    final heartbeat = math.max(beat1, beat2 * 0.7);

    // Pulse modulates opacity between 60% and 100% of base
    final vignetteOpacity = baseOpacity * (0.6 + 0.4 * heartbeat);

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

    _overlayPaint.shader = vignetteGradient.createShader(rect);
    canvas.drawRect(rect, _overlayPaint);
  }

  /// Low fuel amber warning with breathing pulse.
  void _renderFuelWarning(Canvas canvas, Rect rect) {
    final fuelRatio = game.fuelSystem.fuelRatio;
    if (fuelRatio >= GameConstants.lowFuelThreshold) return;

    // Intensity ramps up as fuel approaches zero
    final urgency = 1.0 - (fuelRatio / GameConstants.lowFuelThreshold);

    // Slow breathing pulse (~0.8 Hz)
    final breath = (math.sin(_time * 0.8 * math.pi * 2.0) * 0.5 + 0.5);

    // Max opacity ~0.2 so it's noticeable but not overwhelming
    final alpha = urgency * 0.2 * (0.5 + 0.5 * breath);

    final fuelGradient = RadialGradient(
      center: Alignment.bottomCenter,
      colors: [
        const Color(0x00000000),
        Color.from(alpha: alpha, red: 1.0, green: 0.7, blue: 0.0),
      ],
      radius: 1.0,
    );

    _overlayPaint.shader = fuelGradient.createShader(rect);
    canvas.drawRect(rect, _overlayPaint);
  }

  /// Brief golden flash on ore collection.
  void _renderOreFlash(Canvas canvas, Rect rect) {
    if (_oreFlash <= 0.01) return;

    // Quick golden flash, very subtle
    final alpha = _oreFlash * 0.12;
    _flashPaint.shader = null;
    _flashPaint.color = Color.from(
      alpha: alpha,
      red: 1.0,
      green: 0.85,
      blue: 0.3,
    );
    canvas.drawRect(rect, _flashPaint);
  }

  /// Subtle caustic shimmer when near water table depth.
  void _renderCaustics(Canvas canvas, Rect rect) {
    final depth = game.depthSystem.currentDepth;
    // Water table roughly in the topsoil/rock transition zone (800-1200 ft)
    const waterTableCenter = 1000.0;
    const waterTableRange = 200.0;

    final distFromWater = (depth - waterTableCenter).abs();
    if (distFromWater > waterTableRange) return;

    final proximity = 1.0 - (distFromWater / waterTableRange);

    // Animated caustic pattern using overlapping sine waves
    final cx = math.sin(_time * 1.3) * 0.3;
    final cy = math.cos(_time * 0.9) * 0.3;

    final causticAlpha =
        proximity * 0.06 * (0.5 + 0.5 * math.sin(_time * 2.1 + cx + cy));

    if (causticAlpha < 0.005) return;

    final causticGradient = RadialGradient(
      center: Alignment(cx, cy),
      colors: [
        Color.from(alpha: causticAlpha, red: 0.3, green: 0.7, blue: 1.0),
        const Color(0x00000000),
      ],
      radius: 0.6,
    );

    _overlayPaint.shader = causticGradient.createShader(rect);
    canvas.drawRect(rect, _overlayPaint);
  }
}
