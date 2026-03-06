import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Forge2D BodyComponent for the player pod
///
/// Pod is a BodyType.dynamic body with:
/// - Mass: base 500kg + cargo weight
/// - Linear damping: 0.8 (floaty but controllable)
/// - Angular damping: 5.0 (no spinning)
/// - Fixture: rounded rectangle shape matching pod bounds
class PodBody extends BodyComponent with ContactCallbacks {
  @override
  final MotherlodeGame game;
  late final double _width;
  late final double _height;

  // Contact tracking
  bool isGrounded = false;
  int _groundContactCount = 0;

  PodBody({required this.game}) {
    // Pod dimensions in Forge2D meters
    _width = 1.8;
    _height = 2.2;
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: Vector2(0, -2), // Start slightly above ground
      linearDamping: GameConstants.podLinearDamping,
      angularDamping: GameConstants.podAngularDamping,
      fixedRotation: true, // Prevent spinning
      bullet: true, // Better collision detection for fast movement
    );

    final body = world.createBody(bodyDef);

    // Create pod shape as a polygon (rounded rect approximation)
    final shape = PolygonShape()..setAsBoxXY(_width / 2, _height / 2);

    body.createFixture(FixtureDef(shape)
      ..density = _calculateDensity()
      ..friction = 0.6
      ..restitution = 0.0
      ..userData = this);

    // Add a sensor at the bottom for ground detection
    final sensorShape = PolygonShape()
      ..setAsBox(
        _width / 2 * 0.8,
        0.1,
        Vector2(0, _height / 2),
        0,
      );

    body.createFixture(FixtureDef(sensorShape)
      ..isSensor = true
      ..userData = 'ground_sensor');

    return body;
  }

  /// Calculate density to achieve desired mass
  double _calculateDensity() {
    final area = _width * _height;
    final totalMass =
        GameConstants.podBaseMass + game.pod.cargoSystem.currentWeight;
    return totalMass / area;
  }

  /// Update mass when cargo changes
  void updateMass() {
    if (body.fixtures.isEmpty) return;
    final fixture = body.fixtures.first;
    final newDef = FixtureDef(fixture.shape)
      ..density = _calculateDensity()
      ..friction = 0.6
      ..restitution = 0.0
      ..userData = this;

    body.destroyFixture(fixture);
    body.createFixture(newDef);
  }

  /// Apply engine thrust upward
  void applyThrust(double enginePower) {
    final fuelRatio = game.fuelSystem.fuelRatio;
    var thrustMultiplier = 1.0;

    // Reduced thrust at low fuel
    if (fuelRatio < GameConstants.reducedThrustThreshold) {
      thrustMultiplier = fuelRatio / GameConstants.reducedThrustThreshold;
    }

    final force = Vector2(0, -enginePower * 0.1 * thrustMultiplier);
    body.applyForce(force);
  }

  /// Apply horizontal movement
  void applyHorizontalThrust(double enginePower, double direction) {
    final force = Vector2(enginePower * 0.06 * direction, 0);
    body.applyForce(force);
  }

  /// Apply an explosion impulse to the pod
  void applyExplosionImpulse(Vector2 impulse) {
    body.applyLinearImpulse(impulse);
  }

  /// Apply gravity-adjusted force for drill descent
  void applyDrillForce() {
    // Slight downward push to maintain contact while drilling
    body.applyForce(Vector2(0, body.mass * 2));
  }

  double get width => _width;
  double get height => _height;

  @override
  void beginContact(Object other, Contact contact) {
    final fixtureA = contact.fixtureA;
    final fixtureB = contact.fixtureB;

    // Check ground sensor
    if (fixtureA.userData == 'ground_sensor' ||
        fixtureB.userData == 'ground_sensor') {
      _groundContactCount++;
      isGrounded = true;
    }
  }

  @override
  void endContact(Object other, Contact contact) {
    final fixtureA = contact.fixtureA;
    final fixtureB = contact.fixtureB;

    if (fixtureA.userData == 'ground_sensor' ||
        fixtureB.userData == 'ground_sensor') {
      _groundContactCount--;
      if (_groundContactCount <= 0) {
        _groundContactCount = 0;
        isGrounded = false;
      }
    }
  }
}
