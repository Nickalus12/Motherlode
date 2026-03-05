import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:hellbore/entities/creatures/creature.dart';
import 'package:hellbore/entities/pod/pod.dart';
import 'package:hellbore/hellbore_game.dart';

/// Cave Worm - tunnels through solid terrain, creates persistent tunnels
///
/// Spawns: 500–1500ft
/// Behavior: Tunnels through terrain ahead of it, creating natural passages.
/// FLEE: moves away from pod drill sounds.
/// Passive - only damages if pod moves INTO it.
class CaveWorm extends Creature {
  double _tunnelTimer = 0;
  double _moveAngle = 0;
  final List<Vector2> _bodySegments = [];

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
    // Initialize body segments (worm has a long body)
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
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    // Tunneling behavior
    _tunnelTimer += dt;
    if (_tunnelTimer >= 0.5) {
      _tunnelTimer = 0;
      _tunnel();
    }

    // Update body segments to follow head
    _updateSegments();
  }

  /// Tunnel through terrain ahead of the worm
  void _tunnel() {
    final headX = position.x.round();
    final headY = position.y.round();

    // Remove cell in movement direction
    final dx = cos(_moveAngle).round();
    final dy = sin(_moveAngle).round();
    final targetX = headX + dx;
    final targetY = headY + dy;

    final cellType = game.getCellType(targetX, targetY);
    // Only tunnel through solid cells (not empty, lava, gas)
    if (cellType >= 1 && cellType <= 4) {
      game.removeTerrainCell(targetX, targetY);
    }

    // Slightly adjust movement angle for natural tunneling
    _moveAngle += (Random().nextDouble() - 0.5) * 0.3;
  }

  void _updateSegments() {
    if (_bodySegments.isEmpty) return;

    // Head position
    _bodySegments[0] = position.clone();

    // Each segment follows the one ahead
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
    // Flee when pod is drilling nearby
    return pod.state == PodState.drilling && distToPod < 8;
  }

  @override
  void onAttack(Pod pod, double dt) {
    // Passive - minimal contact damage
    pod.takeDamage(damage * dt * 0.3);
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    final paint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = const Color(0xFF6B5030)
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
    _renderEyes(canvas);

    // Mandibles
    final mandiblePaint = Paint()
      ..color = const Color(0xFF5A4A30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;

    canvas.drawLine(
      const Offset(-0.15, 0.3),
      const Offset(-0.3, 0.5),
      mandiblePaint,
    );
    canvas.drawLine(
      const Offset(0.15, 0.3),
      const Offset(0.3, 0.5),
      mandiblePaint,
    );
  }

  void _renderEyes(Canvas canvas) {
    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(-0.12, -0.1), 0.04, eyePaint);
    canvas.drawCircle(const Offset(0.12, -0.1), 0.04, eyePaint);
  }
}
