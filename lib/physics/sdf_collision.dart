import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';

/// SDF-based ground detection and fall damage system.
///
/// Forge2D handles actual collision response via chunk fixtures.
/// This system supplements Forge2D by:
/// - Detecting ground contact via SDF probes (for drill gating)
/// - Calculating fall damage from vertical velocity
/// - Capping velocity to prevent tunneling
/// - Providing slope normal for rendering/particles
class SdfCollisionSystem extends Component
    with HasGameReference<MotherlodeGame> {
  static const double _podHalfWidth = 0.9;
  static const double _podHalfHeight = 1.1;
  static const double _gradientEps = 0.1;
  static const double _deadZone = 0.05;

  /// Bottom probe offsets for ground detection only.
  /// Probes sit exactly at hull bottom (not below) to match Forge2D contact
  /// surface and prevent the "floating" illusion caused by detecting ground
  /// too early via probes that extend past the collision shape.
  static final List<Vector2> _bottomProbes = [
    Vector2(0, _podHalfHeight), // bottom center (flush with hull)
    Vector2(-_podHalfWidth * 0.5, _podHalfHeight),
    Vector2(_podHalfWidth * 0.5, _podHalfHeight),
    Vector2(-_podHalfWidth * 0.8, _podHalfHeight),
    Vector2(_podHalfWidth * 0.8, _podHalfHeight),
  ];

  /// Hull perimeter probes for penetration detection (safety net).
  /// Samples around the full pod hull to detect when the body has
  /// entered terrain despite Forge2D collision (e.g., during fixture
  /// rebuild after drilling).
  static final List<Vector2> _hullProbes = [
    // Bottom
    Vector2(0, _podHalfHeight),
    Vector2(-_podHalfWidth, _podHalfHeight),
    Vector2(_podHalfWidth, _podHalfHeight),
    // Sides (mid-height)
    Vector2(-_podHalfWidth, 0),
    Vector2(_podHalfWidth, 0),
    // Lower sides
    Vector2(-_podHalfWidth, _podHalfHeight * 0.5),
    Vector2(_podHalfWidth, _podHalfHeight * 0.5),
    // Center (detects full embedding)
    Vector2(0, 0),
  ];

  /// Maximum push-out distance per frame to avoid teleporting
  static const double _maxPushOut = 0.4;

  bool _isOnGround = false;
  bool _wasOnGround = false;
  double _prevVerticalSpeed = 0;

  final Vector2 _normal = Vector2.zero();

  bool get isOnGround => _isOnGround;
  final Vector2 slopeNormal = Vector2(0, -1);

  @override
  void update(double dt) {
    super.update(dt);

    final pod = game.pod;
    if (!pod.isMounted) return;

    final body = pod.body;
    final pos = body.position;
    final vel = body.linearVelocity;

    // Capture vertical speed before any modification (for fall damage)
    final verticalSpeed = vel.y;

    // -------------------------------------------------------------------
    // Penetration push-out (safety net): if the pod hull is inside terrain
    // (SDF < 0), push the body out along the SDF gradient. This catches
    // cases where Forge2D fixture collision misses during rebuild after
    // drilling, or at chunk boundaries with gaps between edge shapes.
    // -------------------------------------------------------------------
    double worstPenetration = 0;
    double pushX = 0, pushY = 0;

    for (final offset in _hullProbes) {
      final probeX = pos.x + offset.x;
      final probeY = pos.y + offset.y;
      final sdf = sampleSdf(probeX, probeY);

      if (sdf < -_deadZone) {
        final penetration = -sdf;
        if (penetration > worstPenetration) {
          worstPenetration = penetration;
          _computeGradient(probeX, probeY, _normal);
          // Push out along negative gradient (toward air)
          pushX = -_normal.x * penetration;
          pushY = -_normal.y * penetration;
        }
      }
    }

    if (worstPenetration > _deadZone) {
      // Clamp push-out magnitude to prevent teleporting
      final pushLen = sqrt(pushX * pushX + pushY * pushY);
      if (pushLen > _maxPushOut) {
        final scale = _maxPushOut / pushLen;
        pushX *= scale;
        pushY *= scale;
      }

      // Move body out of terrain
      body.setTransform(
        Vector2(pos.x + pushX, pos.y + pushY),
        body.angle,
      );

      // Kill velocity component into the terrain so the pod doesn't
      // immediately re-enter on the next frame
      if (pushLen > 0.001) {
        final pushNormX = pushX / pushLen;
        final pushNormY = pushY / pushLen;
        // Dot product of velocity with inward direction (negative push normal)
        final intoTerrain = vel.x * (-pushNormX) + vel.y * (-pushNormY);
        if (intoTerrain > 0) {
          vel.x += pushNormX * intoTerrain;
          vel.y += pushNormY * intoTerrain;
        }
      }
    }

    // -------------------------------------------------------------------
    // Ground detection via SDF probes
    // Supplements Forge2D contact callbacks — only SETS grounded, never
    // clears it. Forge2D endContact handles clearing. This prevents the
    // two systems from fighting and flickering isGrounded each frame.
    // -------------------------------------------------------------------
    bool touchedGround = false;
    int groundContacts = 0;
    double normalSumX = 0, normalSumY = 0;

    for (final offset in _bottomProbes) {
      final probeX = pos.x + offset.x;
      final probeY = pos.y + offset.y;
      final sdf = sampleSdf(probeX, probeY);

      if (sdf < _deadZone) {
        touchedGround = true;
        groundContacts++;
        _computeGradient(probeX, probeY, _normal);
        normalSumX += _normal.x;
        normalSumY += _normal.y;
      }
    }

    // Average slope normal
    if (groundContacts > 0) {
      final inv = 1.0 / groundContacts;
      slopeNormal.setValues(normalSumX * inv, normalSumY * inv);
      final len = slopeNormal.length;
      if (len > 1e-6) {
        slopeNormal.scale(1.0 / len);
      } else {
        slopeNormal.setValues(0, -1);
      }
    } else {
      slopeNormal.setValues(0, -1);
    }

    // Fall damage + landing effects: trigger on landing (ground contact after being airborne)
    if (touchedGround && !_wasOnGround && _prevVerticalSpeed > 1.0) {
      // Landing dust burst (even soft landings get a small puff)
      game.particleSystem.emitLandingDust(
        pos,
        _prevVerticalSpeed,
        game.currentDepthFeet,
      );

      if (_prevVerticalSpeed > 3.0) {
        game.hullSystem.takeFallDamage(_prevVerticalSpeed);
        game.audioManager.playLanding();
      }
    }

    _wasOnGround = _isOnGround;
    _isOnGround = touchedGround;
    // Only SET grounded from SDF probes, never clear it.
    // Forge2D contact callbacks (Pod.beginContact/endContact) manage the
    // authoritative grounded state. SDF probes supplement by detecting ground
    // in cases where Forge2D edge shapes have gaps. This prevents the two
    // systems from fighting and causing ground-state flicker.
    if (_isOnGround) {
      pod.podBody.isGrounded = true;
    }
    _prevVerticalSpeed = verticalSpeed;
  }

  // -------------------------------------------------------------------------
  // SDF Sampling
  // -------------------------------------------------------------------------

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

  double _getCellSdf(int x, int y) {
    final cell = game.chunkManager.getTerrainCell(x, y);
    if (cell == null) return 1.0;
    return cell.sdf;
  }

  void _computeGradient(double x, double y, Vector2 out) {
    final cx = x.round();
    final cy = y.round();
    final nearGrid = (x - cx).abs() < 0.3 && (y - cy).abs() < 0.3;

    double gx, gy;
    if (nearGrid) {
      final sdfRight = _getCellSdf(cx + 1, cy);
      final sdfLeft = _getCellSdf(cx - 1, cy);
      final sdfDown = _getCellSdf(cx, cy + 1);
      final sdfUp = _getCellSdf(cx, cy - 1);
      gx = sdfRight - sdfLeft;
      gy = sdfDown - sdfUp;
    } else {
      final sdfRight = sampleSdf(x + _gradientEps, y);
      final sdfLeft = sampleSdf(x - _gradientEps, y);
      final sdfDown = sampleSdf(x, y + _gradientEps);
      final sdfUp = sampleSdf(x, y - _gradientEps);
      gx = sdfRight - sdfLeft;
      gy = sdfDown - sdfUp;
    }

    final len = sqrt(gx * gx + gy * gy);
    if (len < 1e-8) {
      out.setValues(0, -1);
    } else {
      out.setValues(gx / len, gy / len);
    }
  }
}
