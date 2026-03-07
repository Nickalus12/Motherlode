import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Dynamic camera system that adds velocity-based look-ahead,
/// drill zoom, depth-based zoom, impact shake, and smooth transitions.
class CameraSystem extends Component with HasGameReference<MotherlodeGame> {
  /// Maximum look-ahead offset in world units (tiles).
  static const double _maxLookAheadX = 6.0;
  static const double _maxLookAheadY = 4.0;

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

  // --- Drill zoom ---
  /// Zoom multiplier when drilling (>1.0 = zoom in).
  static const double _drillZoomScale = 1.08;

  /// Lerp speed for drill zoom transition.
  static const double _drillZoomLerpSpeed = 1.5;

  // --- Depth zoom ---
  /// Maximum zoom-out from depth (at max depth).
  static const double _depthMinZoomScale = 0.88;

  // --- Impact shake ---
  /// Minimum impact velocity to trigger camera shake.
  static const double _impactVelocityThreshold = 5.0;

  /// Maximum trauma from a single impact.
  static const double _maxImpactTrauma = 0.4;

  // --- Surface transition ---
  /// Y offset added when approaching surface to show more sky.
  static const double _surfaceYOffset = -2.5;

  /// Depth (in world units) at which surface offset starts fading in.
  static const double _surfaceTransitionStart = 5.0;

  // Smoothed state
  double _currentOffsetX = 0.0;
  double _currentOffsetY = 0.0;
  double _currentZoom = _baseZoom;

  // Smoothed camera position to prevent micro-jitter from physics
  double _smoothPosX = 0.0;
  double _smoothPosY = 0.0;
  bool _posInitialized = false;

  // Drill zoom tracking
  double _drillZoomFactor = 1.0;

  // Impact shake
  double _impactTrauma = 0.0;
  final Random _random = Random();
  double _prevSpeed = 0.0;

  // Landing dampening
  bool _wasAirborne = false;
  double _landingDampen = 0.0;

  @override
  void update(double dt) {
    super.update(dt);

    final pod = game.pod;
    if (!pod.isMounted) return;

    final vel = pod.body.linearVelocity;
    final speed = vel.length;

    // --- Impact detection ---
    _detectImpact(pod, speed);

    // --- Landing detection ---
    _updateLandingState(pod, dt);

    // --- Look-ahead offset ---
    double targetOffsetX = 0.0;
    double targetOffsetY = 0.0;

    if (speed > 0.5) {
      final t = min(speed / _fullSpeedThreshold, 1.0);
      targetOffsetX = (vel.x / speed) * t * _maxLookAheadX;
      targetOffsetY = (vel.y / speed) * t * _maxLookAheadY;
    }

    // Landing dampening: reduce offset snap after landing
    final offsetLerp = _landingDampen > 0
        ? min(1.0, _offsetLerpSpeed * 2.5 * dt)
        : min(1.0, _offsetLerpSpeed * dt);
    _currentOffsetX += (targetOffsetX - _currentOffsetX) * offsetLerp;
    _currentOffsetY += (targetOffsetY - _currentOffsetY) * offsetLerp;

    // Surface transition: shift camera up when near surface
    double surfaceOffset = 0.0;
    if (pod.position.y < _surfaceTransitionStart) {
      final surfaceT =
          (1.0 - pod.position.y / _surfaceTransitionStart).clamp(0.0, 1.0);
      surfaceOffset = _surfaceYOffset * surfaceT;
    }

    // Impact shake offset
    double shakeX = 0.0;
    double shakeY = 0.0;
    if (_impactTrauma > 0) {
      final shake = _impactTrauma * _impactTrauma; // Quadratic for snappy feel
      shakeX = (_random.nextDouble() - 0.5) * shake * 0.8;
      shakeY = (_random.nextDouble() - 0.5) * shake * 0.8;
      _impactTrauma = (_impactTrauma - dt * 3.0).clamp(0.0, 1.0);
    }

    // Compute target camera position
    final targetX = pod.position.x + _currentOffsetX + shakeX;
    final targetY = pod.position.y + _currentOffsetY + surfaceOffset + shakeY;

    // Smooth camera position to prevent micro-jitter from physics solver.
    // High lerp rate (12) so camera stays responsive but filters out
    // single-frame position discontinuities from collision resolution.
    if (!_posInitialized) {
      _smoothPosX = targetX;
      _smoothPosY = targetY;
      _posInitialized = true;
    } else {
      final posLerp = min(1.0, 12.0 * dt);
      _smoothPosX += (targetX - _smoothPosX) * posLerp;
      _smoothPosY += (targetY - _smoothPosY) * posLerp;
    }

    // Apply smoothed position to camera viewfinder
    game.camera.viewfinder.position = Vector2(_smoothPosX, _smoothPosY);

    // --- Dynamic zoom ---
    double targetZoom = _baseZoom;

    // Speed zoom-out
    if (speed > _zoomSpeedThreshold) {
      final zoomT = min(
          (speed - _zoomSpeedThreshold) /
              (_fullSpeedThreshold - _zoomSpeedThreshold),
          1.0);
      targetZoom *= 1.0 - zoomT * (1.0 - _minZoomScale);
    }

    // Drill zoom-in
    final drillTarget = pod.state == PodState.drilling ? _drillZoomScale : 1.0;
    final drillLerp = min(1.0, _drillZoomLerpSpeed * dt);
    _drillZoomFactor += (drillTarget - _drillZoomFactor) * drillLerp;
    targetZoom *= _drillZoomFactor;

    // Depth zoom-out: gradually zoom out as player goes deeper
    final depthFeet = pod.position.y * GameConstants.feetPerTile;
    if (depthFeet > 0) {
      final depthT = (depthFeet / GameConstants.maxDepth).clamp(0.0, 1.0);
      targetZoom *= 1.0 - depthT * (1.0 - _depthMinZoomScale);
    }

    final zoomLerp = min(1.0, _zoomLerpSpeed * dt);
    _currentZoom += (targetZoom - _currentZoom) * zoomLerp;
    game.camera.viewfinder.zoom = _currentZoom;

    _prevSpeed = speed;
  }

  void _detectImpact(Pod pod, double speed) {
    // Detect sudden velocity drops (collision impact)
    final speedDrop = _prevSpeed - speed;
    if (speedDrop > _impactVelocityThreshold) {
      final trauma =
          (speedDrop / (_fullSpeedThreshold * 2)).clamp(0.0, _maxImpactTrauma);
      _impactTrauma = min(_impactTrauma + trauma, 1.0);
    }
  }

  /// Add camera trauma from external sources (explosions, creature attacks, etc.)
  void addTrauma(double amount) {
    _impactTrauma = (_impactTrauma + amount).clamp(0.0, 1.0);
  }

  void _updateLandingState(Pod pod, double dt) {
    final isAirborne = pod.state == PodState.flying && !pod.podBody.isGrounded;
    if (_wasAirborne && !isAirborne && pod.podBody.isGrounded) {
      // Just landed — dampen camera offset snap
      _landingDampen = 0.3;
    }
    _wasAirborne = isAirborne;

    if (_landingDampen > 0) {
      _landingDampen = (_landingDampen - dt).clamp(0.0, 1.0);
    }
  }
}
