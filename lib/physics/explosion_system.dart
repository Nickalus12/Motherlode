import 'dart:math';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Radial impulse force application for dynamite and explosives
///
/// Removes terrain cells in radius, applies impulse to dynamic bodies,
/// chains through lava (60%) and gas (150%) pockets.
class ExplosionSystem {
  final MotherlodeGame game;

  ExplosionSystem({required this.game});

  /// Trigger an explosion at a world position
  void explode(Vector2 position, int radius, double force) {
    final gridX = position.x.round();
    final gridY = position.y.round();

    // Track chain explosion positions
    final chainExplosions = <_ChainExplosion>[];

    // 1. Remove terrain cells in radius
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy > radius * radius) continue;

        final x = gridX + dx;
        final y = gridY + dy;
        final cellType = game.getCellType(x, y);

        // Check for chain reaction triggers
        if (cellType == 5) {
          // CellType.lava
          chainExplosions.add(_ChainExplosion(
            position: Vector2(x.toDouble(), y.toDouble()),
            force: force * 0.6,
            radius: (radius * 0.7).round(),
          ));
        } else if (cellType == 6) {
          // CellType.gas
          chainExplosions.add(_ChainExplosion(
            position: Vector2(x.toDouble(), y.toDouble()),
            force: force * 1.5,
            radius: (radius * 1.2).round(),
          ));
        }

        game.removeTerrainCell(x, y);
      }
    }

    // 2. Apply radial impulse to all dynamic bodies
    _applyRadialImpulse(position, radius.toDouble() * 2, force);

    // 3. Emit explosion particles
    game.particleSystem.emitExplosionDebris(position, radius);

    // 4. Screen shake
    _applyCameraShake(radius == GameConstants.dynamiteRadius
        ? GameConstants.dynamiteCameraTrauma
        : GameConstants.plasticCameraTrauma);

    // 5. Check for collapse around explosion
    game.earthquakeSystem.checkCollapseArea(gridX, gridY, radius + 2);

    // 6. Trigger chain explosions (delayed for visual effect)
    for (int i = 0; i < chainExplosions.length; i++) {
      final chain = chainExplosions[i];
      Future.delayed(Duration(milliseconds: 100 + i * 50), () {
        explode(chain.position, chain.radius, chain.force);
      });
    }
  }

  /// Apply impulse force to all dynamic bodies within range
  void _applyRadialImpulse(Vector2 center, double radius, double force) {
    // Query the physics world for bodies near the explosion
    final aabb = AABB.withVec2(
      center - Vector2.all(radius),
      center + Vector2.all(radius),
    );

    game.world.physicsWorld.queryAABB(_ExplosionQueryCallback(
      reportFixture: (fixture) {
        final body = fixture.body;
        if (body.bodyType != BodyType.dynamic) return true;

        final bodyPos = body.position;
        final direction = bodyPos - center;
        final distance = direction.length;

        if (distance < radius && distance > 0.01) {
          final impulseStrength = force / (distance * distance);
          final impulse = direction.normalized() * impulseStrength;
          body.applyLinearImpulse(impulse);
        }

        return true; // Continue querying
      },
    ), aabb);
  }

  /// Apply camera shake effect
  void _applyCameraShake(double trauma) {
    // Simple camera shake by applying small random offset
    final random = Random();
    final offsetX = (random.nextDouble() - 0.5) * trauma * 2;
    final offsetY = (random.nextDouble() - 0.5) * trauma * 2;

    game.camera.viewfinder.position.x += offsetX;
    game.camera.viewfinder.position.y += offsetY;

    // Decay back to normal over time (handled by game update)
    Future.delayed(const Duration(milliseconds: 100), () {
      game.camera.viewfinder.position.x -= offsetX;
      game.camera.viewfinder.position.y -= offsetY;
    });
  }
}

class _ChainExplosion {
  final Vector2 position;
  final double force;
  final int radius;

  const _ChainExplosion({
    required this.position,
    required this.force,
    required this.radius,
  });
}

/// Forge2D query callback for AABB queries
class _ExplosionQueryCallback extends QueryCallback {
  final bool Function(Fixture fixture) _reportFixture;

  _ExplosionQueryCallback({required bool Function(Fixture fixture) reportFixture})
      : _reportFixture = reportFixture;

  @override
  bool reportFixture(Fixture fixture) {
    return _reportFixture(fixture);
  }
}
