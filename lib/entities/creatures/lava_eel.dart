import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/pod/pod.dart';

/// Lava Eel - swims in lava, surfaces to launch projectile attacks
///
/// Spawns: 3500–5500ft, in/near lava pockets
/// ATTACK: launches lava glob projectile toward pod (slow arc)
/// Cannot leave lava
/// Visual: glowing orange serpent with flickering light trail
class LavaEel extends Creature {
  double _attackCooldown = 0;
  double _swimTimer = 0;
  final List<Vector2> _bodyTrail = [];
  static const double _attackInterval = 3.0;
  static const double _projectileSpeed = 5.0;

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
    // Initialize trail
    for (int i = 0; i < 8; i++) {
      _bodyTrail.add(initialPosition.clone());
    }
  }

  @override
  Shape get bodyShape => CircleShape()..radius = 0.3;

  @override
  double get bodyRadius => 0.3;

  @override
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    _swimTimer += dt;
    _attackCooldown -= dt;

    // Update body trail
    _updateTrail();

    // Swimming motion (sinusoidal)
    final swimForce = Vector2(
      sin(_swimTimer * 3) * speed * 0.3,
      cos(_swimTimer * 2) * speed * 0.15,
    );
    body.applyForce(swimForce);

    // Check for attack opportunity
    final pod = motherlodeGame.pod;
    final distToPod = position.distanceTo(pod.position);

    if (_attackCooldown <= 0 && distToPod < 15 && distToPod > 2) {
      _launchProjectile(pod);
      _attackCooldown = _attackInterval;
    }
  }

  void _updateTrail() {
    // Shift trail positions
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
    // Calculate launch direction toward pod
    final direction = (pod.position - position).normalized();

    // Create projectile as a separate component
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
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Draw body trail (serpent body segments)
    for (int i = _bodyTrail.length - 1; i >= 1; i--) {
      final segment = _bodyTrail[i];
      final relX = segment.x - position.x;
      final relY = segment.y - position.y;
      final segRadius = 0.25 - i * 0.02;
      final t = i / _bodyTrail.length.toDouble();

      // Gradient from bright orange to dark orange
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

  double _lifeTime = 5.0; // Max lifetime before despawn
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
      ..isSensor = true // Pass through terrain, only hit pod
      ..userData = this);

    // Apply initial velocity
    body.linearVelocity = direction * speed;

    // Add some gravity effect for arc
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
    // Lava glob
    canvas.drawCircle(
      Offset.zero,
      0.15,
      Paint()..color = const Color(0xFFFF6600),
    );

    // Glow
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
