import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/utils/constants.dart';

/// Gas Spore - floating explosive organism near gas pockets
///
/// Spawns: 2000–4000ft, clusters near gas pockets
/// Floats slowly, no active chase
/// TRIGGER: if pod drills within 3 cells, explodes
/// Chain reactions with adjacent spores
class GasSpore extends Creature {
  double _pulseTimer = 0;
  double _pulseIntensity = 0;
  bool _triggered = false;
  double _triggerCountdown = 0;
  static const double _triggerTime = 0.8; // seconds before explosion

  GasSpore({required Vector2 initialPosition})
      : super(
          name: 'Gas Spore',
          maxHealth: 10,
          damage: 0, // Damage comes from explosion, not contact
          speed: 3,
          bodyColor: const Color(0xFF44FF44),
          eyeColor: const Color(0xFF88FF88),
          cashDrop: 100,
          initialPosition: initialPosition,
        );

  @override
  Shape get bodyShape => CircleShape()..radius = 0.35;

  @override
  double get bodyRadius => 0.35;

  @override
  void update(double dt) {
    if (state == CreatureState.dead) return;

    _pulseTimer += dt;
    _pulseIntensity = (sin(_pulseTimer * 2) + 1) / 2;

    // Check if pod is drilling nearby
    if (!_triggered) {
      final pod = motherlodeGame.pod;
      final distToPod = position.distanceTo(pod.position);

      if (pod.state == PodState.drilling &&
          distToPod < GameConstants.gasSporeChainRadius) {
        _trigger();
      }
    }

    // Handle trigger countdown
    if (_triggered) {
      _triggerCountdown -= dt;
      _pulseIntensity = 1.0; // Max glow when triggered

      if (_triggerCountdown <= 0) {
        _explode();
        return;
      }
    }

    // Gentle floating movement
    body.applyForce(Vector2(
      sin(_pulseTimer * 0.5) * speed * 0.1,
      cos(_pulseTimer * 0.3) * speed * 0.05 - 1, // Slight upward float
    ));

    super.update(dt);
  }

  void _trigger() {
    if (_triggered) return;
    _triggered = true;
    _triggerCountdown = _triggerTime;
  }

  void _explode() {
    state = CreatureState.dead;

    // 2x2 cell removal
    final gridX = position.x.round();
    final gridY = position.y.round();

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        motherlodeGame.removeTerrainCell(gridX + dx, gridY + dy);
      }
    }

    // Explosion effects
    motherlodeGame.particleSystem.emitExplosionDebris(position, 2);
    motherlodeGame.earthquakeSystem.startShake(0.4, 0.5);

    // Hull damage if pod is nearby
    final distToPod = position.distanceTo(motherlodeGame.pod.position);
    if (distToPod < 4) {
      final damage = 15 * (1 - distToPod / 4);
      motherlodeGame.pod.takeDamage(damage);
    }

    // Chain reaction: trigger nearby spores
    for (final component in game.world.children) {
      if (component is GasSpore &&
          component != this &&
          component.state != CreatureState.dead) {
        final dist = position.distanceTo(component.position);
        if (dist < GameConstants.gasSporeChainRadius * 1.5) {
          component._trigger();
        }
      }
    }

    // Check collapse
    motherlodeGame.earthquakeSystem.checkCollapseArea(gridX, gridY, 3);

    // Remove
    Future.delayed(const Duration(milliseconds: 300), () {
      removeFromParent();
    });
  }

  @override
  bool shouldChase(double distToPod) => false; // Never chases

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Outer glow
    final glowPaint = Paint()
      ..color = Color.from(
        alpha: 0.15 + _pulseIntensity * 0.15,
        red: 0.0,
        green: 1.0,
        blue: 0.3,
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset.zero,
      bodyRadius + 0.2 + _pulseIntensity * 0.1,
      glowPaint,
    );

    // Body (translucent bio-sphere)
    final bodyPaint = Paint()
      ..color = Color.from(
        alpha: 0.6 + _pulseIntensity * 0.2,
        red: bodyColor.r,
        green: bodyColor.g,
        blue: bodyColor.b,
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, bodyRadius, bodyPaint);

    // Inner membrane
    final membranePaint = Paint()
      ..color = const Color(0x4088FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03;
    canvas.drawCircle(Offset.zero, bodyRadius * 0.7, membranePaint);

    // Nucleus (darker center)
    canvas.drawCircle(
      const Offset(0.02, -0.02),
      bodyRadius * 0.25,
      Paint()..color = const Color(0xFF22AA22),
    );

    // Warning glow when triggered
    if (_triggered) {
      final warningPaint = Paint()
        ..color = Color.from(
          alpha: (sin(_triggerCountdown * 20) + 1) / 2 * 0.5,
          red: 1.0,
          green: 0.0,
          blue: 0.0,
        )
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, bodyRadius + 0.1, warningPaint);
    }
  }
}
