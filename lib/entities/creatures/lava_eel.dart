import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Lava Eel - swims in lava, constrained to lava/volcanic cells
///
/// Spawns: 3500-5500ft, in/near lava pockets
/// MOVEMENT: Sinusoidal swimming motion, stays in lava cells
/// ATTACK: launches lava glob projectile toward robot (slow arc)
/// Cannot leave lava — steers back toward lava when at boundary
/// Visual: glowing orange serpent with flickering light trail
class LavaEel extends Creature {
  double _attackCooldown = 0;
  final List<Vector2> _bodyTrail = [];
  static const double _attackInterval = 3.0;
  static const double _projectileSpeed = 5.0;
  double _swimPhase = 0; // For sinusoidal motion

  LavaEel({required Vector2 initialPosition})
      : super(
          name: 'Lava Eel',
          maxHealth: 80,
          damage: 3,
          speed: 12,
          bodyColor: const Color(0xFFFF6600),
          eyeColor: const Color(0xFFFFFF00),
          cashDrop: 1000,
          initialPosition: initialPosition,
        ) {
    for (int i = 0; i < 8; i++) {
      _bodyTrail.add(initialPosition.clone());
    }
    _swimPhase = Random().nextDouble() * pi * 2;
  }

  @override
  Shape get bodyShape => CircleShape()..radius = 0.3;

  @override
  double get bodyRadius => 0.3;

  @override
  double get detectionRadius => 15.0;

  @override
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    _attackCooldown -= dt;

    // Update body trail
    _updateTrail();

    // Sinusoidal swimming motion: lateral oscillation perpendicular to velocity
    _applySinusoidalSwim(dt);

    // Constrain to lava/volcanic cells — steer back if leaving
    _constrainToLava();

    // Check for attack opportunity
    final pod = motherlodeGame.pod;
    final distToPod = position.distanceTo(pod.position);

    if (_attackCooldown <= 0 && distToPod < detectionRadius && distToPod > 2) {
      _launchProjectile(pod);
      _attackCooldown = _attackInterval;
    }
  }

  /// Sinusoidal swimming: oscillate perpendicular to forward direction
  void _applySinusoidalSwim(double dt) {
    _swimPhase += dt * 3.0;

    final vel = body.linearVelocity;
    final forward = vel.length > 0.1 ? vel.normalized() : Vector2(1, 0);
    // Perpendicular direction
    final lateral = Vector2(-forward.y, forward.x);

    final sinForce = sin(_swimPhase) * speed * 0.4;
    body.applyForce(lateral * sinForce);

    // Also add gentle forward propulsion
    body.applyForce(forward * speed * 0.2);
  }

  /// Steer back toward lava if the eel strays into non-lava cells
  void _constrainToLava() {
    final headX = position.x.round();
    final headY = position.y.round();
    final currentCell = motherlodeGame.getCellType(headX, headY);

    // If currently in lava, fine
    if (currentCell == CellType.lava.index) return;

    // Not in lava — search nearby for lava cells and steer toward them
    Vector2? nearestLava;
    double nearestDist = double.infinity;

    for (int dy = -3; dy <= 3; dy++) {
      for (int dx = -3; dx <= 3; dx++) {
        final checkType = motherlodeGame.getCellType(headX + dx, headY + dy);
        if (checkType == CellType.lava.index) {
          final lavaPos = Vector2(
            (headX + dx).toDouble(),
            (headY + dy).toDouble(),
          );
          final dist = position.distanceTo(lavaPos);
          if (dist < nearestDist) {
            nearestDist = dist;
            nearestLava = lavaPos;
          }
        }
      }
    }

    if (nearestLava != null) {
      // Strong steering force back toward lava
      final direction = (nearestLava - position).normalized();
      body.applyForce(direction * speed * 2.0);
    }
  }

  void _updateTrail() {
    for (int i = _bodyTrail.length - 1; i > 0; i--) {
      final target = _bodyTrail[i - 1];
      final current = _bodyTrail[i];
      final dir = target - current;
      final dist = dir.length;
      if (dist > 0.3) {
        _bodyTrail[i] = current + dir.normalized() * (dist - 0.25);
      }
    }
    _bodyTrail[0] = position.clone();
  }

  void _launchProjectile(Pod pod) {
    final direction = (pod.position - position).normalized();

    final projectile = LavaGlobProjectile(
      startPosition: position.clone(),
      direction: direction,
      speed: _projectileSpeed,
    );

    game.world.add(projectile);
  }

  @override
  bool shouldChase(double distToPod) =>
      false; // Doesn't chase, attacks from distance

  @override
  bool shouldFlee(Pod pod, double distToPod) {
    // Flee when health is low
    return healthRatio < 0.3 && distToPod < detectionRadius;
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Invulnerability flash
    if (isInvulnerable && ((invulnTimer * 30).toInt() % 2 == 0)) return;

    // Draw body trail (serpent body segments)
    for (int i = _bodyTrail.length - 1; i >= 1; i--) {
      final segment = _bodyTrail[i];
      final relX = segment.x - position.x;
      final relY = segment.y - position.y;
      final segRadius = 0.25 - i * 0.02;
      final t = i / _bodyTrail.length.toDouble();

      final segColor = Color.lerp(
        const Color(0xFFFF8800),
        const Color(0xFF993300),
        t,
      )!;

      canvas.drawCircle(
        Offset(relX, relY),
        segRadius,
        Paint()..color = segColor,
      );

      // Light trail effect
      canvas.drawCircle(
        Offset(relX, relY),
        segRadius + 0.1,
        Paint()
          ..color = Color.from(
            alpha: (1 - t) * 0.15,
            red: 1.0,
            green: 0.5,
            blue: 0.0,
          ),
      );
    }

    // Head
    final headPaint = Paint()
      ..color = const Color(0xFFFF8800)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, bodyRadius, headPaint);

    // Head glow
    canvas.drawCircle(
      Offset.zero,
      bodyRadius + 0.15,
      Paint()..color = const Color(0x30FF6600),
    );

    // Eyes
    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(-0.1, -0.1), 0.04, eyePaint);
    canvas.drawCircle(const Offset(0.1, -0.1), 0.04, eyePaint);

    // Mouth (when attacking)
    if (_attackCooldown > _attackInterval - 0.5) {
      canvas.drawCircle(
        const Offset(0, 0.15),
        0.08,
        Paint()..color = const Color(0xFFFFCC00),
      );
    }
  }
}

/// Lava glob projectile fired by the Lava Eel
class LavaGlobProjectile extends BodyComponent with ContactCallbacks {
  final Vector2 startPosition;
  final Vector2 direction;
  final double speed;

  double _lifeTime = 5.0;
  static const double _damage = 20.0;

  LavaGlobProjectile({
    required this.startPosition,
    required this.direction,
    required this.speed,
  });

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: startPosition,
      bullet: true,
      linearDamping: 0.0,
    );

    final body = world.createBody(bodyDef);

    body.createFixture(FixtureDef(CircleShape()..radius = 0.15)
      ..density = 0.5
      ..isSensor = true
      ..userData = this);

    body.linearVelocity = direction * speed;
    body.gravityScale = Vector2(0, 0.3);

    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime -= dt;
    if (_lifeTime <= 0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(
      Offset.zero,
      0.15,
      Paint()..color = const Color(0xFFFF6600),
    );
    canvas.drawCircle(
      Offset.zero,
      0.3,
      Paint()..color = const Color(0x40FF4400),
    );
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is Pod) {
      other.takeDamage(_damage);
      removeFromParent();
    }
  }
}
