import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/pod/cargo_system.dart';
import 'package:motherlode/entities/pod/drill_system.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/physics/pod_body.dart';
import 'package:motherlode/rendering/pod_renderer.dart';
import 'package:motherlode/utils/constants.dart';

/// Pod states
enum PodState {
  idle,
  flying,
  drilling,
  grounded,
  dead,
  surfaced, // At the surface zone
}

/// Main player entity - the mining pod
///
/// Contains the physics body, drill system, cargo system,
/// and state machine for managing pod behavior.
class Pod extends BodyComponent with ContactCallbacks {
  final MotherlodeGame _game;
  final double _spawnY;

  // State
  PodState state = PodState.idle;

  // Input state
  bool thrustUp = false;
  bool thrustLeft = false;
  bool thrustRight = false;
  bool drillDown = false;

  // Sub-systems
  late final DrillSystem drillSystem;
  late final CargoSystem cargoSystem;
  late final PodBody podBody;
  late final PodRenderer _renderer;

  // Stats (modified by upgrades)
  double enginePower = 3000.0;
  double maxFuel = GameConstants.baseFuelCapacity;
  double maxHull = GameConstants.baseHullHP;
  double maxCargo = GameConstants.baseCargoCapacity;
  double drillSpeed = GameConstants.baseDrillSpeed;

  Pod({required MotherlodeGame game, double spawnY = -3.0})
      : _game = game,
        _spawnY = spawnY;

  @override
  Body createBody() {
    podBody = PodBody(game: _game);

    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: Vector2(0, _spawnY),
      linearDamping: GameConstants.podLinearDamping,
      angularDamping: GameConstants.podAngularDamping,
      fixedRotation: true,
      bullet: true,
    );

    final body = world.createBody(bodyDef);

    // Pod shape
    final shape = PolygonShape()
      ..setAsBoxXY(0.9, 1.1);

    body.createFixture(FixtureDef(shape)
      ..density = GameConstants.podBaseMass / (1.8 * 2.2)
      ..friction = 0.5
      ..restitution = 0.1
      ..userData = this);

    // Ground sensor
    final sensorShape = PolygonShape()
      ..setAsBox(0.7, 0.1, Vector2(0, 1.1), 0);

    body.createFixture(FixtureDef(sensorShape)
      ..isSensor = true
      ..userData = 'ground_sensor');

    return body;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    drillSystem = DrillSystem(pod: this, game: _game);
    cargoSystem = CargoSystem(maxCapacity: maxCargo);
    _renderer = PodRenderer(pod: this);

    add(drillSystem);
    add(_renderer);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (state == PodState.dead) return;

    // Update state based on conditions
    _updateState();

    // Apply physics forces
    _applyForces(dt);

    // Consume fuel
    _consumeFuel(dt);

    // Check death conditions
    _checkDeath();
  }

  void _updateState() {
    if (_game.hullSystem.currentHull <= 0 || state == PodState.dead) {
      state = PodState.dead;
      return;
    }

    if (_game.isAtSurface) {
      state = PodState.surfaced;
      return;
    }

    if (drillDown && podBody.isGrounded) {
      state = PodState.drilling;
      return;
    }

    if (thrustUp || thrustLeft || thrustRight) {
      state = PodState.flying;
      return;
    }

    if (podBody.isGrounded) {
      state = PodState.grounded;
      return;
    }

    state = PodState.flying;
  }

  void _applyForces(double dt) {
    if (state == PodState.dead) return;

    // Thrust scaled to mass so controls feel consistent regardless of cargo.
    // gravity = 9.8 m/s², so thrustAccel > 9.8 means pod can fly upward.
    final thrustAccel = 18.0;

    // Engine thrust
    if (thrustUp && _game.fuelSystem.hasFuel) {
      body.applyForce(Vector2(0, -body.mass * thrustAccel));
    }

    // Horizontal movement
    if (thrustLeft && _game.fuelSystem.hasFuel) {
      body.applyForce(Vector2(-body.mass * thrustAccel * 0.6, 0));
    }
    if (thrustRight && _game.fuelSystem.hasFuel) {
      body.applyForce(Vector2(body.mass * thrustAccel * 0.6, 0));
    }

    // Drilling
    if (state == PodState.drilling) {
      drillSystem.drill(dt);
      body.applyForce(Vector2(0, body.mass * 2));
    }
  }

  void _consumeFuel(double dt) {
    if (state == PodState.surfaced || state == PodState.dead) return;

    double consumption = GameConstants.fuelConsumptionIdle;

    if (state == PodState.flying) {
      consumption = GameConstants.fuelConsumptionThrust;
    } else if (state == PodState.drilling) {
      consumption = GameConstants.fuelConsumptionDrill;
    }

    _game.fuelSystem.consumeFuel(consumption * dt);
  }

  void _checkDeath() {
    if (_game.hullSystem.currentHull <= 0) {
      state = PodState.dead;
      _game.triggerGameOver();
    }

    // Out of fuel at depth - slow death (hull damage from being stranded)
    if (!_game.fuelSystem.hasFuel && !_game.isAtSurface) {
      // No immediate death, but can't thrust back up
      // Player might have teleporter/transmitter
    }
  }

  /// Get pod position in world units
  Vector2 get podPosition => body.position;

  /// Get current depth in feet
  double get depthFeet => position.y * GameConstants.feetPerTile;

  /// Update physics body mass when cargo changes.
  ///
  /// Replaces the main fixture with a new one whose density reflects
  /// the combined pod base mass + current cargo weight.
  void updateMass() {
    // Find the first non-sensor fixture (the main pod shape)
    Fixture? mainFixture;
    for (final f in body.fixtures) {
      if (f.userData != 'ground_sensor') {
        mainFixture = f;
        break;
      }
    }
    if (mainFixture == null) return;

    final area = 1.8 * 2.2; // Pod width * height
    final totalMass = GameConstants.podBaseMass + cargoSystem.currentWeight;
    final newDensity = totalMass / area;

    final newDef = FixtureDef(mainFixture.shape)
      ..density = newDensity
      ..friction = 0.5
      ..restitution = 0.1
      ..userData = this;

    body.destroyFixture(mainFixture);
    body.createFixture(newDef);
  }

  /// Apply an impulse (from explosion, etc.)
  void applyImpulse(Vector2 impulse) {
    body.applyLinearImpulse(impulse);
  }

  /// Take hull damage
  void takeDamage(double amount) {
    _game.hullSystem.takeDamage(amount);
  }

  // Ground contact tracking (moved from PodBody since it's never mounted)
  int _groundContactCount = 0;

  @override
  void beginContact(Object other, Contact contact) {
    final fixtureA = contact.fixtureA;
    final fixtureB = contact.fixtureB;

    if (fixtureA.userData == 'ground_sensor' ||
        fixtureB.userData == 'ground_sensor') {
      _groundContactCount++;
      podBody.isGrounded = true;
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
        podBody.isGrounded = false;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    // Rendering handled by PodRenderer child component
  }
}
