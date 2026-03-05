import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:hellbore/entities/pod/pod.dart';
import 'package:hellbore/utils/constants.dart';

/// Dynamic falling dirt/rock body created from collapsed terrain
///
/// Falls under gravity, bounces off terrain, deals hull damage
/// on pod contact. Settles after 3 seconds and becomes static.
class DebrisBody extends BodyComponent with ContactCallbacks {
  final Vector2 initialPosition;
  final Color color;
  final double mass;

  double _settleTimer = GameConstants.debrisSettleTime;
  bool _settled = false;

  DebrisBody({
    required this.initialPosition,
    required this.color,
    this.mass = 50.0,
  });

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: initialPosition,
      linearDamping: 0.3,
      angularDamping: 0.5,
    );

    final body = world.createBody(bodyDef);

    // Debris shape - small square
    final shape = PolygonShape()
      ..setAsBox(0.3, 0.3);

    body.createFixture(FixtureDef(shape)
      ..density = mass / (0.6 * 0.6)
      ..friction = 0.8
      ..restitution = 0.2
      ..userData = this);

    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_settled) return;

    _settleTimer -= dt;

    // Check if debris has settled (low velocity or timer expired)
    if (_settleTimer <= 0 || body.linearVelocity.length < 0.1) {
      _settle();
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw as colored square
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      const Rect.fromLTWH(-0.3, -0.3, 0.6, 0.6),
      paint,
    );

    // Outline
    final outlinePaint = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04;
    canvas.drawRect(
      const Rect.fromLTWH(-0.3, -0.3, 0.6, 0.6),
      outlinePaint,
    );
  }

  void _settle() {
    if (_settled) return;
    _settled = true;

    // Convert to static body
    body.setType(BodyType.static);
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0;

    // Remove after a short delay (debris fades)
    Future.delayed(const Duration(seconds: 5), () {
      removeFromParent();
    });
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (_settled) return;

    // Deal hull damage to pod on contact
    if (other is Pod) {
      final impactSpeed = body.linearVelocity.length;
      final damage = mass * impactSpeed * GameConstants.debrisDamageMultiplier;
      if (damage > 0.5) {
        other.takeDamage(damage);
      }
    }
  }
}
