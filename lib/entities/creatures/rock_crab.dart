import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';

/// Rock Crab - dormant until disturbed, then scuttles and attacks
///
/// Spawns: 1500-3000ft
/// DORMANT: Starts idle, camouflaged as rock. Activates when pod within 4 tiles.
/// SCUTTLE: Sideways movement pattern with quick direction changes.
/// ATTACK: Lunge-pause-lunge claw strikes (5 damage per lunge).
/// Drops: Bronzium chunk on death
class RockCrab extends Creature {
  double _legAnimTimer = 0;
  bool _facingRight = true;
  double _patrolDirection = 1;
  bool _isDormant = true;
  double _scuttleTimer = 0;
  static const double _activationRadius = 4.0; // tiles

  RockCrab({required Vector2 initialPosition})
      : super(
          name: 'Rock Crab',
          maxHealth: 50,
          damage: 5,
          speed: 20,
          bodyColor: const Color(0xFF7A6A5A),
          eyeColor: const Color(0xFFFF4444),
          cashDrop: 500,
          initialPosition: initialPosition,
        );

  @override
  Shape get bodyShape {
    return PolygonShape()..setAsBoxXY(0.6, 0.35);
  }

  @override
  double get bodyRadius => 0.5;

  @override
  double get detectionRadius => 20.0;

  @override
  void update(double dt) {
    if (state == CreatureState.dead) return;

    // Dormant check: don't run AI until pod is close
    if (_isDormant) {
      final distToPod = position.distanceTo(motherlodeGame.pod.position);
      if (distToPod < _activationRadius) {
        _isDormant = false;
        state = CreatureState.chase;
        // Brief shake to show awakening
        motherlodeGame.earthquakeSystem.startShake(0.15, 0.15);
      } else {
        // Stay completely still while dormant
        body.linearVelocity = Vector2.zero();
        return;
      }
    }

    super.update(dt);

    _legAnimTimer += dt * 8;
    _scuttleTimer += dt;

    // Track facing direction
    if (body.linearVelocity.x > 0.5) _facingRight = true;
    if (body.linearVelocity.x < -0.5) _facingRight = false;

    // Scuttle sideways movement during wander
    if (state == CreatureState.wander) {
      // Quick direction changes for scuttle effect
      if (_scuttleTimer > 0.6) {
        _scuttleTimer = 0;
        _patrolDirection *= -1;
      }
      body.applyForce(Vector2(_patrolDirection * speed * 0.7, 0));

      // Reverse at walls
      final frontX = position.x + _patrolDirection * 1.5;
      final cellType =
          motherlodeGame.getCellType(frontX.round(), position.y.round());
      if (cellType != 0) {
        _patrolDirection *= -1;
        _scuttleTimer = 0;
      }
    }

    // Scuttle sideways while chasing too (not straight-line)
    if (state == CreatureState.chase) {
      final sideForce = sin(_scuttleTimer * 6) * speed * 0.4;
      body.applyForce(Vector2(sideForce, 0));
    }
  }

  @override
  bool shouldChase(double distToPod) {
    if (_isDormant) return false;
    return distToPod < detectionRadius;
  }

  @override
  bool shouldFlee(Pod pod, double distToPod) {
    // Rock crabs are tough — only flee at 20% health
    return healthRatio < 0.2 && distToPod < detectionRadius;
  }

  @override
  void onAttackLunge(Pod pod) {
    pod.takeDamage(damage);
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Invulnerability flash
    if (isInvulnerable) {
      if (((invulnTimer * 30).toInt() % 2 == 0)) return;
    }

    canvas.save();
    if (!_facingRight) {
      canvas.scale(-1, 1);
    }

    // Dormant: darker, more rock-like appearance
    final colorMult = _isDormant ? 0.6 : 1.0;

    // Body (oval, rock-textured)
    final bodyPaint = Paint()
      ..color = Color.from(
        alpha: 1.0,
        red: bodyColor.r * colorMult,
        green: bodyColor.g * colorMult,
        blue: bodyColor.b * colorMult,
      )
      ..style = PaintingStyle.fill;

    // Main shell
    canvas.drawOval(
      const Rect.fromLTWH(-0.55, -0.3, 1.1, 0.6),
      bodyPaint,
    );

    // Shell texture lines
    final texturePaint = Paint()
      ..color = const Color(0xFF5A4A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03;

    canvas.drawLine(
      const Offset(-0.3, -0.15),
      const Offset(0.3, -0.15),
      texturePaint,
    );
    canvas.drawLine(
      const Offset(-0.2, 0.05),
      const Offset(0.2, 0.05),
      texturePaint,
    );

    // Don't draw claws/legs/eyes while dormant (camouflage)
    if (!_isDormant) {
      // Claws
      final clawPaint = Paint()
        ..color = const Color(0xFF8A7A6A)
        ..style = PaintingStyle.fill;

      final clawPath = Path();
      clawPath.moveTo(0.5, -0.1);
      clawPath.lineTo(0.8, -0.25);
      clawPath.lineTo(0.75, -0.05);
      clawPath.lineTo(0.8, 0.1);
      clawPath.lineTo(0.5, 0.05);
      clawPath.close();
      canvas.drawPath(clawPath, clawPaint);

      // Legs (animated)
      final legPaint = Paint()
        ..color = const Color(0xFF6A5A4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04;

      for (int i = 0; i < 3; i++) {
        final baseX = -0.2 + i * 0.2;
        final legPhase = sin(_legAnimTimer + i * 1.2);
        final legEndY = 0.3 + legPhase.abs() * 0.1;

        canvas.drawLine(
          Offset(baseX, 0.25),
          Offset(baseX - 0.1, legEndY),
          legPaint,
        );
      }

      // Eyes on stalks
      final eyePaint = Paint()
        ..color = eyeColor
        ..style = PaintingStyle.fill;

      canvas.drawLine(
        const Offset(0.2, -0.3),
        const Offset(0.25, -0.5),
        legPaint,
      );
      canvas.drawLine(
        const Offset(0.35, -0.3),
        const Offset(0.4, -0.5),
        legPaint,
      );

      canvas.drawCircle(const Offset(0.25, -0.5), 0.04, eyePaint);
      canvas.drawCircle(const Offset(0.4, -0.5), 0.04, eyePaint);
    }

    canvas.restore();
  }
}
