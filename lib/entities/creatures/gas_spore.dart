import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/utils/constants.dart';

/// Gas Spore - floating explosive organism near gas pockets
///
/// Spawns: 2000-4000ft, clusters near gas pockets
/// Floats slowly, no active chase
/// TRIGGER: if robot drills within 3 cells OR proximity detonation within 2 tiles
/// Pulsing/swelling animation before explosion
/// Chain reactions with adjacent spores
class GasSpore extends Creature {
  double _pulseTimer = 0;
  double _pulseIntensity = 0;
  bool _triggered = false;
  double _triggerCountdown = 0;
  static const double _triggerTime =
      1.2; // seconds before explosion (longer for drama)
  static const double _proximityDetonationRange = 2.0; // tiles
  static const double _explosionRadius = 4.0; // damage falloff radius
  static const double _maxExplosionDamage = 20.0;

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
  double get detectionRadius => 5.0; // Small detection, mostly passive

  @override
  void update(double dt) {
    if (state == CreatureState.dead) return;

    _pulseTimer += dt;
    _pulseIntensity = (sin(_pulseTimer * 2) + 1) / 2;

    final pod = motherlodeGame.pod;
    final distToPod = position.distanceTo(pod.position);

    if (!_triggered) {
      // Trigger on drill vibration
      if (pod.state == PodState.drilling &&
          distToPod < GameConstants.gasSporeChainRadius) {
        _trigger();
      }
      // Proximity detonation: auto-trigger when robot gets very close
      if (distToPod < _proximityDetonationRange) {
        _trigger();
      }
    }

    // Handle trigger countdown with swelling effect
    if (_triggered) {
      _triggerCountdown -= dt;

      // Accelerating pulse as countdown progresses
      final urgency = 1.0 - (_triggerCountdown / _triggerTime).clamp(0.0, 1.0);
      _pulseIntensity = (sin(_pulseTimer * (4 + urgency * 16)) + 1) / 2;

      if (_triggerCountdown <= 0) {
        _explode();
        return;
      }
    }

    // Gentle floating movement
    body.applyForce(Vector2(
      sin(_pulseTimer * 0.5) * speed * 0.1,
      cos(_pulseTimer * 0.3) * speed * 0.05 - 1,
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

    // 3x3 cell removal (area destruction)
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

    // Area damage with distance falloff
    final distToPod = position.distanceTo(motherlodeGame.pod.position);
    if (distToPod < _explosionRadius) {
      final falloff = 1.0 - (distToPod / _explosionRadius);
      final dmg = _maxExplosionDamage * falloff;
      motherlodeGame.pod.takeDamage(dmg);
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
      if (isMounted) removeFromParent();
    });
  }

  @override
  bool shouldChase(double distToPod) => false; // Never chases

  @override
  bool shouldFlee(Pod pod, double distToPod) => false; // Explodes instead

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Invulnerability flash
    if (isInvulnerable && ((invulnTimer * 30).toInt() % 2 == 0)) return;

    // Swelling effect when triggered: body grows as countdown progresses
    final swellFactor = _triggered
        ? 1.0 + (1.0 - (_triggerCountdown / _triggerTime).clamp(0.0, 1.0)) * 0.4
        : 1.0;
    final currentRadius = bodyRadius * swellFactor;

    // Outer glow (more intense when triggered)
    final glowAlpha = _triggered
        ? 0.2 + _pulseIntensity * 0.3
        : 0.15 + _pulseIntensity * 0.15;
    final glowColor = _triggered
        ? Color.from(alpha: glowAlpha, red: 1.0, green: 0.3, blue: 0.0)
        : Color.from(alpha: glowAlpha, red: 0.0, green: 1.0, blue: 0.3);

    canvas.drawCircle(
      Offset.zero,
      currentRadius + 0.2 + _pulseIntensity * 0.15,
      Paint()..color = glowColor,
    );

    // Body (translucent bio-sphere, tints red when triggered)
    final bodyAlpha = 0.6 + _pulseIntensity * 0.2;
    final Color displayColor;
    if (_triggered) {
      final urgency = 1.0 - (_triggerCountdown / _triggerTime).clamp(0.0, 1.0);
      displayColor = Color.lerp(bodyColor, const Color(0xFFFF4444), urgency)!
          .withValues(alpha: bodyAlpha);
    } else {
      displayColor = bodyColor.withValues(alpha: bodyAlpha);
    }

    canvas.drawCircle(
      Offset.zero,
      currentRadius,
      Paint()..color = displayColor,
    );

    // Inner membrane
    final membranePaint = Paint()
      ..color = const Color(0x4088FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03;
    canvas.drawCircle(Offset.zero, currentRadius * 0.7, membranePaint);

    // Nucleus (darker center)
    canvas.drawCircle(
      const Offset(0.02, -0.02),
      currentRadius * 0.25,
      Paint()
        ..color =
            _triggered ? const Color(0xFFAA2222) : const Color(0xFF22AA22),
    );

    // Warning glow when triggered (pulsing red ring)
    if (_triggered) {
      final warningAlpha = (sin(_triggerCountdown * 20) + 1) / 2 * 0.5;
      final warningPaint = Paint()
        ..color = Color.from(
          alpha: warningAlpha,
          red: 1.0,
          green: 0.0,
          blue: 0.0,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06;
      canvas.drawCircle(Offset.zero, currentRadius + 0.1, warningPaint);
    }
  }
}
