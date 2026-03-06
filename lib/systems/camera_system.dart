import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';

/// Dynamic camera system that adds velocity-based look-ahead and
/// optional speed-based zoom adjustment.
///
/// Works alongside `camera.follow(pod)` — this component applies an
/// additional offset to the camera viewfinder each frame so the player
/// can see further in the direction they are moving.
class CameraSystem extends Component with HasGameReference<MotherlodeGame> {
  /// Maximum look-ahead offset in world units (tiles).
  static const double _maxLookAhead = 6.0;

  /// Velocity magnitude (m/s) at which look-ahead reaches full extent.
  static const double _fullSpeedThreshold = 12.0;

  /// Lerp speed for offset smoothing (higher = snappier).
  static const double _offsetLerpSpeed = 3.0;

  /// Lerp speed for zoom smoothing.
  static const double _zoomLerpSpeed = 2.0;

  /// Base zoom level (matches GameConstants.pixelsPerMeter).
  static const double _baseZoom = 24.0;

  /// Zoom-out factor when moving at full speed (1.0 = no change, <1.0 = zoom out).
  static const double _minZoomScale = 0.85;

  /// Speed threshold where zoom starts pulling out.
  static const double _zoomSpeedThreshold = 6.0;

  // Smoothed state
  double _currentOffsetX = 0.0;
  double _currentOffsetY = 0.0;
  double _currentZoom = _baseZoom;

  @override
  void update(double dt) {
    super.update(dt);

    final pod = game.pod;
    if (!pod.isMounted) return;

    final vel = pod.body.linearVelocity;
    final speed = vel.length;

    // --- Look-ahead offset ---
    // Target offset proportional to velocity, clamped to max
    double targetOffsetX = 0.0;
    double targetOffsetY = 0.0;

    if (speed > 0.5) {
      final t = min(speed / _fullSpeedThreshold, 1.0);
      targetOffsetX = (vel.x / speed) * t * _maxLookAhead;
      targetOffsetY = (vel.y / speed) * t * _maxLookAhead;
    }

    // Smooth interpolation toward target
    final lerpFactor = min(1.0, _offsetLerpSpeed * dt);
    _currentOffsetX += (targetOffsetX - _currentOffsetX) * lerpFactor;
    _currentOffsetY += (targetOffsetY - _currentOffsetY) * lerpFactor;

    // Apply offset to camera viewfinder
    game.camera.viewfinder.position = Vector2(
      pod.position.x + _currentOffsetX,
      pod.position.y + _currentOffsetY,
    );

    // --- Dynamic zoom ---
    double targetZoom = _baseZoom;
    if (speed > _zoomSpeedThreshold) {
      final zoomT = min(
          (speed - _zoomSpeedThreshold) /
              (_fullSpeedThreshold - _zoomSpeedThreshold),
          1.0);
      targetZoom = _baseZoom * (1.0 - zoomT * (1.0 - _minZoomScale));
    }

    final zoomLerp = min(1.0, _zoomLerpSpeed * dt);
    _currentZoom += (targetZoom - _currentZoom) * zoomLerp;
    game.camera.viewfinder.zoom = _currentZoom;
  }
}
