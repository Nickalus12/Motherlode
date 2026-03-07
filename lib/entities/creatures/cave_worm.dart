import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';

/// Cave Worm - tunnels through solid terrain toward the robot
///
/// Spawns: 500-1500ft
/// Behavior: Tunnels through terrain, creating natural passages.
/// TUNNEL: Moves through solid terrain toward pod when chasing.
/// FLEE: moves away from robot drill sounds.
/// Passive - only damages if robot moves INTO it.
class CaveWorm extends Creature {
  double _tunnelTimer = 0;
  double _moveAngle = 0;
  final List<Vector2> _bodySegments = [];
  bool _isTunneling = false; // Whether currently inside solid terrain

  CaveWorm({required Vector2 initialPosition})
      : super(
          name: 'Cave Worm',
          maxHealth: 30,
          damage: 2,
          speed: 15,
          bodyColor: const Color(0xFF8B6E4B),
          eyeColor: const Color(0xFFFFFF88),
          cashDrop: 200,
          initialPosition: initialPosition,
        ) {
    for (int i = 0; i < 6; i++) {
      _bodySegments.add(Vector2(
        initialPosition.x - i * 0.4,
        initialPosition.y,
      ));
    }
  }

  @override
  Shape get bodyShape => CircleShape()..radius = 0.4;

  @override
  double get bodyRadius => 0.4;

  @override
  double get detectionRadius => 12.0;

  @override
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    // Check if worm is inside solid terrain
    final headX = position.x.round();
    final headY = position.y.round();
    final cellType = motherlodeGame.getCellType(headX, headY);
    _isTunneling = cellType >= 1 && cellType <= 4;

    // Tunneling behavior: carve path through terrain
    _tunnelTimer += dt;
    if (_tunnelTimer >= 0.5) {
      _tunnelTimer = 0;
      _tunnel();
    }

    // When chasing, steer toward pod through terrain
    if (state == CreatureState.chase) {
      final pod = motherlodeGame.pod;
      _moveAngle = atan2(
        pod.position.y - position.y,
        pod.position.x - position.x,
      );
      // Apply stronger force when tunneling (burrow toward player)
      final force = _isTunneling ? speed * 1.2 : speed * 0.8;
      body.applyForce(Vector2(cos(_moveAngle), sin(_moveAngle)) * force);
    }

    // Update body segments to follow head
    _updateSegments();
  }

  /// Tunnel through terrain ahead of the worm
  void _tunnel() {
    final headX = position.x.round();
    final headY = position.y.round();

    final dx = cos(_moveAngle).round();
    final dy = sin(_moveAngle).round();
    final targetX = headX + dx;
    final targetY = headY + dy;

    final cellType = motherlodeGame.getCellType(targetX, targetY);
    if (cellType >= 1 && cellType <= 4) {
      motherlodeGame.removeTerrainCell(targetX, targetY);
    }

    // Slightly adjust movement angle for natural tunneling when wandering
    if (state == CreatureState.wander) {
      _moveAngle += (Random().nextDouble() - 0.5) * 0.3;
    }
  }

  void _updateSegments() {
    if (_bodySegments.isEmpty) return;

    _bodySegments[0] = position.clone();

    for (int i = 1; i < _bodySegments.length; i++) {
      final target = _bodySegments[i - 1];
      final current = _bodySegments[i];
      final dir = target - current;
      final dist = dir.length;

      if (dist > 0.4) {
        _bodySegments[i] = current + dir.normalized() * (dist - 0.35);
      }
    }
  }

  @override
  bool shouldFlee(Pod pod, double distToPod) {
    // Flee when robot is drilling nearby OR when health is low
    return (pod.state == PodState.drilling && distToPod < 8) ||
        (healthRatio < 0.3 && distToPod < detectionRadius);
  }

  @override
  void onAttackLunge(Pod pod) {
    // Passive - minimal contact damage per lunge
    pod.takeDamage(damage);
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Invulnerability flash
    if (isInvulnerable && ((invulnTimer * 30).toInt() % 2 == 0)) return;

    // When tunneling, render with reduced opacity (partially in rock)
    final alpha = _isTunneling ? 0.5 : 1.0;

    final paint = Paint()
      ..color = bodyColor.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = const Color(0xFF6B5030).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    // Draw body segments (back to front)
    for (int i = _bodySegments.length - 1; i >= 0; i--) {
      final segment = _bodySegments[i];
      final relX = segment.x - position.x;
      final relY = segment.y - position.y;
      final segmentRadius = 0.35 - i * 0.03;

      canvas.drawCircle(
        Offset(relX, relY),
        segmentRadius,
        i % 2 == 0 ? paint : darkPaint,
      );
    }

    // Draw head
    canvas.drawCircle(Offset.zero, bodyRadius, paint);

    // Eyes
    _renderEyes(canvas, alpha);

    // Mandibles (wider when tunneling)
    final mandibleSpread = _isTunneling ? 0.4 : 0.3;
    final mandiblePaint = Paint()
      ..color = Color.from(alpha: alpha, red: 0.35, green: 0.29, blue: 0.19)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;

    canvas.drawLine(
      const Offset(-0.15, 0.3),
      Offset(-mandibleSpread, 0.5),
      mandiblePaint,
    );
    canvas.drawLine(
      const Offset(0.15, 0.3),
      Offset(mandibleSpread, 0.5),
      mandiblePaint,
    );
  }

  void _renderEyes(Canvas canvas, double alpha) {
    final eyePaint = Paint()
      ..color = eyeColor.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(-0.12, -0.1), 0.04, eyePaint);
    canvas.drawCircle(const Offset(0.12, -0.1), 0.04, eyePaint);
  }
}
