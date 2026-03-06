import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';

/// SDF-native terrain collision system.
///
/// Replaces Forge2D terrain fixtures with direct SDF field queries for
/// smooth, sub-cell collision response. The pod's Forge2D body is still
/// used for gravity and momentum, but terrain penetration is resolved
/// here via SDF gradient projection.
///
/// Drilling is handled separately by [DrillSystem], which delegates SDF
/// carving to [ChunkManager.drillAtWorld].
class SdfCollisionSystem extends Component
    with HasGameReference<MotherlodeGame> {
  /// Pod half-dimensions in Forge2D meters (matches pod shape in Pod.createBody).
  static const double _podHalfWidth = 0.9;
  static const double _podHalfHeight = 1.1;

  /// Friction coefficient applied tangentially when sliding along terrain.
  static const double _frictionCoeff = 0.4;

  /// Small epsilon for gradient sampling offset.
  static const double _gradientEps = 0.1;

  /// Maximum penetration correction per frame to avoid jitter.
  static const double _maxPushOut = 0.5;

  /// Extra depth below the physics hull that bottom probes reach into terrain.
  /// This compensates for the dead-zone so the visual hull sits flush on the surface.
  static const double _skinWidth = 0.005;

  /// Minimum penetration before push-out kicks in (dead-zone to avoid jitter).
  static const double _deadZone = 0.005;

  // Probe points relative to pod center (computed once).
  // Bottom probes extend by _skinWidth below the hull so the visual bottom
  // lands exactly on the terrain surface after dead-zone settling.
  static final List<Vector2> _probeOffsets = [
    Vector2(0, _podHalfHeight + _skinWidth), // bottom center
    Vector2(-_podHalfWidth * 0.5, _podHalfHeight + _skinWidth), // bottom mid-left
    Vector2(_podHalfWidth * 0.5, _podHalfHeight + _skinWidth), // bottom mid-right
    Vector2(-_podHalfWidth, _podHalfHeight + _skinWidth), // bottom left
    Vector2(_podHalfWidth, _podHalfHeight + _skinWidth), // bottom right
    Vector2(-_podHalfWidth, 0), // left center
    Vector2(_podHalfWidth, 0), // right center
    Vector2(-_podHalfWidth, _podHalfHeight * 0.5), // left mid-low
    Vector2(_podHalfWidth, _podHalfHeight * 0.5), // right mid-low
    Vector2(-_podHalfWidth, -_podHalfHeight), // top left
    Vector2(_podHalfWidth, -_podHalfHeight), // top right
  ];

  bool _isOnGround = false;
  bool _wasOnGround = false;

  /// Whether the pod is resting on or very close to terrain.
  bool get isOnGround => _isOnGround;

  @override
  void update(double dt) {
    super.update(dt);

    final pod = game.pod;
    if (!pod.isMounted) return;

    final body = pod.body;
    final pos = body.position.clone();
    final vel = body.linearVelocity.clone();

    // Capture pre-collision velocity for fall damage detection
    final preCollisionSpeed = vel.length;

    bool touchedGround = false;

    for (final offset in _probeOffsets) {
      final probeX = pos.x + offset.x;
      final probeY = pos.y + offset.y;

      final sdf = sampleSdf(probeX, probeY);

      if (sdf < 0) {
        // Bottom probes (at full pod height) indicate ground contact
        if (offset.y >= _podHalfHeight) {
          touchedGround = true;
        }

        // Skip push-out for very shallow penetration to avoid jitter
        if (sdf < -_deadZone) {
          // Inside terrain — compute gradient (surface normal)
          final normal = _sdfGradient(probeX, probeY);
          final penetration = (-sdf - _deadZone).clamp(0.0, _maxPushOut);

          // Push pod out along the normal
          pos.x += normal.x * penetration;
          pos.y += normal.y * penetration;

          // Remove velocity component into the terrain
          final velDotNormal = vel.dot(normal);
          if (velDotNormal < 0) {
            vel.x -= velDotNormal * normal.x;
            vel.y -= velDotNormal * normal.y;

            // Apply friction along the tangent
            final tangent = Vector2(-normal.y, normal.x);
            final velDotTangent = vel.dot(tangent);
            final frictionMag = velDotTangent.abs() * _frictionCoeff * dt;
            if (frictionMag < velDotTangent.abs()) {
              vel.x -= tangent.x * velDotTangent.sign * frictionMag;
              vel.y -= tangent.y * velDotTangent.sign * frictionMag;
            } else {
              vel.x -= tangent.x * velDotTangent;
              vel.y -= tangent.y * velDotTangent;
            }
          }
        }
      }
    }

    // Apply corrected position and velocity back to the Forge2D body
    body.setTransform(pos, body.angle);
    body.linearVelocity = vel;

    // Fall damage and landing SFX: detect transition from airborne to ground contact
    if (touchedGround && !_wasOnGround && preCollisionSpeed > 0) {
      game.hullSystem.takeFallDamage(preCollisionSpeed);
      game.audioManager.playLanding();
    }

    // Update ground state (used by Pod for state machine & drill gating)
    _wasOnGround = _isOnGround;
    _isOnGround = touchedGround;
    pod.podBody.isGrounded = _isOnGround;
  }

  // ---------------------------------------------------------------------------
  // SDF Sampling
  // ---------------------------------------------------------------------------

  /// Sample the terrain SDF at a continuous world position using bilinear
  /// interpolation of the four surrounding cell corners.
  double sampleSdf(double worldX, double worldY) {
    final cx = worldX.floor();
    final cy = worldY.floor();
    final fx = worldX - cx;
    final fy = worldY - cy;

    final s00 = _getCellSdf(cx, cy);
    final s10 = _getCellSdf(cx + 1, cy);
    final s01 = _getCellSdf(cx, cy + 1);
    final s11 = _getCellSdf(cx + 1, cy + 1);

    return s00 * (1 - fx) * (1 - fy) +
        s10 * fx * (1 - fy) +
        s01 * (1 - fx) * fy +
        s11 * fx * fy;
  }

  /// Get the raw SDF value of a single terrain cell at integer grid coords.
  /// Returns a positive value (air) if the cell doesn't exist or is empty.
  double _getCellSdf(int x, int y) {
    final cell = game.chunkManager.getTerrainCell(x, y);
    if (cell == null) return 1.0;
    return cell.sdf;
  }

  /// Compute the normalized SDF gradient (surface normal pointing outward)
  /// at a continuous world position using central differences.
  Vector2 _sdfGradient(double x, double y) {
    final sdfRight = sampleSdf(x + _gradientEps, y);
    final sdfLeft = sampleSdf(x - _gradientEps, y);
    final sdfDown = sampleSdf(x, y + _gradientEps);
    final sdfUp = sampleSdf(x, y - _gradientEps);

    final gx = sdfRight - sdfLeft;
    final gy = sdfDown - sdfUp;

    final len = sqrt(gx * gx + gy * gy);
    if (len < 1e-8) return Vector2(0, -1); // default up if flat

    return Vector2(gx / len, gy / len);
  }
}
