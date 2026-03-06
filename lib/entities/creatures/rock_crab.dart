import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';

/// Rock Crab - patrols horizontal tunnels, chases pod, climbs walls
///
/// Spawns: 1500–3000ft
/// CHASE: if pod within 200px, sprints toward pod
/// ATTACK: 5 hull damage/sec on contact
/// Drops: Bronzium chunk on death
class RockCrab extends Creature {
  double _legAnimTimer = 0;
  bool _facingRight = true;
  double _patrolDirection = 1;

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
    // Wider body shape
    return PolygonShape()..setAsBoxXY(0.6, 0.35);
  }

  @override
  double get bodyRadius => 0.5;

  @override
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    _legAnimTimer += dt * 8;

    // Track facing direction
    if (body.linearVelocity.x > 0.5) _facingRight = true;
    if (body.linearVelocity.x < -0.5) _facingRight = false;

    // Patrol behavior enhancement
    if (state == CreatureState.wander) {
      // Patrol horizontally
      body.applyForce(Vector2(_patrolDirection * speed * 0.5, 0));

      // Reverse at walls
      final frontX = position.x + _patrolDirection * 1.5;
      final cellType =
          motherlodeGame.getCellType(frontX.round(), position.y.round());
      if (cellType != 0) {
        // Not empty = wall
        _patrolDirection *= -1;
      }
    }
  }

  @override
  bool shouldChase(double distToPod) {
    // More aggressive chase range
    return distToPod < 20;
  }

  @override
  void onAttack(Pod pod, double dt) {
    pod.takeDamage(damage * dt);
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    canvas.save();
    if (!_facingRight) {
      canvas.scale(-1, 1);
    }

    // Body (oval, rock-textured)
    final bodyPaint = Paint()
      ..color = bodyColor
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

    // Claws
    final clawPaint = Paint()
      ..color = const Color(0xFF8A7A6A)
      ..style = PaintingStyle.fill;

    // Front claw (larger)
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

    canvas.restore();
  }
}
