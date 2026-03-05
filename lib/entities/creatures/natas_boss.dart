import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:hellbore/entities/creatures/creature.dart';
import 'package:hellbore/entities/creatures/rock_crab.dart';
import 'package:hellbore/entities/pod/pod.dart';

/// Mr. Natas - Final boss at -7187ft, multi-phase fight
///
/// Phase 1 (100–60% HP): Ground slam attacks, summons Rock Crabs
/// Phase 2 (60–30% HP): Lava wave attacks, faster movement
/// Phase 3 (30–0% HP): Berserker mode, all attacks + constant earthquake
/// Arena: pre-generated Hell chamber, immune to cave collapse
class NatasBoss extends Creature {
  int currentPhase = 1;
  double _phaseTimer = 0;
  double _attackTimer = 0;
  double _summonTimer = 0;
  int _summonCount = 0;
  final int ngPlusLevel; // New game+ scaling

  // Phase timing
  static const double _slamCooldown = 3.0;
  static const double _lavaWaveCooldown = 4.0;
  static const double _summonCooldown = 8.0;
  static const int _maxSummons = 4;

  NatasBoss({
    required Vector2 initialPosition,
    this.ngPlusLevel = 0,
  }) : super(
          name: 'Mr. Natas',
          maxHealth: 500 + ngPlusLevel * 200,
          damage: 10,
          speed: 25 + ngPlusLevel * 5,
          bodyColor: const Color(0xFFCC0000),
          eyeColor: const Color(0xFFFFFF00),
          cashDrop: 100000 + ngPlusLevel * 50000,
          initialPosition: initialPosition,
        );

  @override
  Shape get bodyShape {
    return PolygonShape()..setAsBox(1.2, 1.5);
  }

  @override
  double get bodyRadius => 1.2;

  @override
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    _phaseTimer += dt;
    _attackTimer += dt;
    _summonTimer += dt;

    // Update phase based on health
    final healthRatio = health / maxHealth;
    if (healthRatio <= 0.3 && currentPhase < 3) {
      _enterPhase(3);
    } else if (healthRatio <= 0.6 && currentPhase < 2) {
      _enterPhase(2);
    }

    // Phase-specific behavior
    switch (currentPhase) {
      case 1:
        _phase1Behavior(dt);
        break;
      case 2:
        _phase2Behavior(dt);
        break;
      case 3:
        _phase3Behavior(dt);
        break;
    }
  }

  void _enterPhase(int phase) {
    currentPhase = phase;
    _phaseTimer = 0;
    _attackTimer = 0;

    // Screen shake on phase transition
    game.earthquakeSystem.startShake(0.8, 2.0);

    // Visual flash effect
    game.particleSystem.emitExplosionDebris(position, 3);
  }

  /// Phase 1: Ground slams + Rock Crab summons
  void _phase1Behavior(double dt) {
    // Always chase the pod
    final pod = game.pod;
    final direction = (pod.position - position).normalized();
    body.applyForce(direction * speed);

    // Ground slam attack
    if (_attackTimer >= _slamCooldown) {
      _attackTimer = 0;
      _groundSlam();
    }

    // Summon Rock Crabs
    if (_summonTimer >= _summonCooldown && _summonCount < _maxSummons) {
      _summonTimer = 0;
      _summonRockCrab();
    }
  }

  /// Phase 2: Lava waves + faster movement
  void _phase2Behavior(double dt) {
    final pod = game.pod;
    final direction = (pod.position - position).normalized();
    body.applyForce(direction * speed * 1.3); // Faster

    // Ground slam (faster cooldown)
    if (_attackTimer >= _slamCooldown * 0.7) {
      _attackTimer = 0;
      _groundSlam();
    }

    // Lava wave attack
    if (_phaseTimer > 0 &&
        _phaseTimer.remainder(_lavaWaveCooldown) < dt) {
      _lavaWaveAttack();
    }
  }

  /// Phase 3: Berserker - all attacks + constant earthquake
  void _phase3Behavior(double dt) {
    final pod = game.pod;
    final direction = (pod.position - position).normalized();
    body.applyForce(direction * speed * 1.6); // Even faster

    // Constant screen shake
    game.earthquakeSystem.startShake(0.3, 0.5);

    // Rapid ground slams
    if (_attackTimer >= _slamCooldown * 0.4) {
      _attackTimer = 0;
      _groundSlam();
    }

    // Lava waves
    if (_phaseTimer > 0 &&
        _phaseTimer.remainder(_lavaWaveCooldown * 0.6) < dt) {
      _lavaWaveAttack();
    }

    // More summons
    if (_summonTimer >= _summonCooldown * 0.5 && _summonCount < _maxSummons + 2) {
      _summonTimer = 0;
      _summonRockCrab();
    }
  }

  void _groundSlam() {
    // Camera shake
    game.earthquakeSystem.startShake(0.6, 1.0);

    // Damage pod if nearby
    final distToPod = position.distanceTo(game.pod.position);
    if (distToPod < 4) {
      final slamDamage = 15 * (1 - distToPod / 4);
      game.pod.takeDamage(slamDamage);
      game.pod.applyImpulse(
        (game.pod.position - position).normalized() * 30,
      );
    }

    // Destroy nearby terrain
    final gridX = position.x.round();
    final gridY = position.y.round();
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        if (dx * dx + dy * dy <= 4) {
          game.removeTerrainCell(gridX + dx, gridY + dy);
        }
      }
    }

    // Particles
    game.particleSystem.emitExplosionDebris(position, 2);
  }

  void _lavaWaveAttack() {
    // Launch multiple projectiles in an arc
    final pod = game.pod;
    final baseAngle = (pod.position - position).angleTo(Vector2(1, 0));

    for (int i = -2; i <= 2; i++) {
      final angle = baseAngle + i * 0.3;
      final direction = Vector2(cos(angle), sin(angle));

      // Reuse lava glob projectile logic
      game.particleSystem.emitLavaSplash(
        position + direction * 1.5,
      );
    }

    // Damage in cone
    final distToPod = position.distanceTo(game.pod.position);
    if (distToPod < 8) {
      game.pod.takeDamage(10);
    }
  }

  void _summonRockCrab() {
    _summonCount++;

    final offset = Vector2(
      (Random().nextDouble() - 0.5) * 6,
      (Random().nextDouble() - 0.5) * 4,
    );

    final crab = RockCrab(
      initialPosition: position + offset,
    );

    game.world.add(crab);
  }

  @override
  void die() {
    // Epic death sequence
    game.earthquakeSystem.startShake(1.0, 3.0);

    // Large explosion
    for (int i = 0; i < 5; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (game.isMounted) {
          game.particleSystem.emitExplosionDebris(
            position + Vector2(
              (Random().nextDouble() - 0.5) * 3,
              (Random().nextDouble() - 0.5) * 3,
            ),
            4,
          );
        }
      });
    }

    super.die();
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Phase-dependent visual
    final phaseColor = switch (currentPhase) {
      1 => const Color(0xFFCC0000),
      2 => const Color(0xFFFF3300),
      3 => const Color(0xFFFF0000),
      _ => bodyColor,
    };

    // Aura glow (increases with phase)
    final auraRadius = 1.5 + currentPhase * 0.3;
    canvas.drawCircle(
      Offset.zero,
      auraRadius,
      Paint()
        ..color = Color.from(
          alpha: 0.1 + currentPhase * 0.05,
          red: 1.0,
          green: 0.0,
          blue: 0.0,
        ),
    );

    // Main body
    final bodyPath = Path();
    bodyPath.moveTo(0, -1.5); // Top (horns)
    bodyPath.lineTo(-0.3, -1.0);
    bodyPath.lineTo(-1.0, -0.8);
    bodyPath.lineTo(-1.1, 0);
    bodyPath.lineTo(-0.9, 0.8);
    bodyPath.lineTo(-0.5, 1.3);
    bodyPath.lineTo(0.5, 1.3);
    bodyPath.lineTo(0.9, 0.8);
    bodyPath.lineTo(1.1, 0);
    bodyPath.lineTo(1.0, -0.8);
    bodyPath.lineTo(0.3, -1.0);
    bodyPath.close();

    canvas.drawPath(
      bodyPath,
      Paint()..color = phaseColor,
    );

    // Horns
    final hornPaint = Paint()
      ..color = const Color(0xFF440000)
      ..style = PaintingStyle.fill;

    final leftHorn = Path();
    leftHorn.moveTo(-0.3, -1.0);
    leftHorn.lineTo(-0.8, -1.8);
    leftHorn.lineTo(-0.1, -1.2);
    leftHorn.close();
    canvas.drawPath(leftHorn, hornPaint);

    final rightHorn = Path();
    rightHorn.moveTo(0.3, -1.0);
    rightHorn.lineTo(0.8, -1.8);
    rightHorn.lineTo(0.1, -1.2);
    rightHorn.close();
    canvas.drawPath(rightHorn, hornPaint);

    // Eyes (menacing, large)
    final eyeGlow = Paint()
      ..color = Color.from(
        alpha: 0.5 + sin(_phaseTimer * 4) * 0.2,
        red: 1.0,
        green: 1.0,
        blue: 0.0,
      );

    canvas.drawCircle(const Offset(-0.35, -0.5), 0.15, eyeGlow);
    canvas.drawCircle(const Offset(0.35, -0.5), 0.15, eyeGlow);

    final pupilPaint = Paint()..color = const Color(0xFFFF0000);
    canvas.drawCircle(const Offset(-0.35, -0.5), 0.08, pupilPaint);
    canvas.drawCircle(const Offset(0.35, -0.5), 0.08, pupilPaint);

    // Mouth
    final mouthPath = Path();
    mouthPath.moveTo(-0.4, 0.2);
    mouthPath.quadraticBezierTo(0, 0.6, 0.4, 0.2);
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = const Color(0xFF880000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06,
    );

    // Health bar above
    final healthRatio = health / maxHealth;
    final barWidth = 2.0;
    final barHeight = 0.12;
    final barY = -2.0;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(-barWidth / 2, barY, barWidth, barHeight),
      Paint()..color = const Color(0x80000000),
    );

    // Fill
    canvas.drawRect(
      Rect.fromLTWH(-barWidth / 2, barY, barWidth * healthRatio, barHeight),
      Paint()..color = const Color(0xFFFF0000),
    );
  }
}
