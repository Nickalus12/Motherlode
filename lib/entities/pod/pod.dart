import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:motherlode/entities/pod/cargo_system.dart';
import 'package:motherlode/entities/pod/drill_system.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/physics/pod_body.dart';
import 'package:motherlode/rendering/pod_renderer.dart';
import 'package:motherlode/utils/constants.dart';

/// Robot states
enum PodState {
  idle,
  flying,
  drilling,
  grounded,
  dead,
  surfaced, // At the surface zone
}

/// Main player entity - the mining robot
///
/// Contains the physics body, drill system, cargo system,
/// and state machine for managing robot behavior.
class Pod extends BodyComponent with ContactCallbacks {
  final MotherlodeGame _game;
  final double _spawnY;

  // State
  PodState state = PodState.idle;
  PodState _previousState = PodState.idle;

  // Input state (binary — keyboard)
  bool thrustUp = false;
  bool thrustLeft = false;
  bool thrustRight = false;
  bool drillDown = false;

  // Analog input state (0.0-1.0 magnitude, set by touch controller)
  double thrustAnalogX = 0.0; // -1.0 left, +1.0 right
  double thrustAnalogY = 0.0; // -1.0 up, +1.0 down

  /// Normalized thrust direction for renderer/particles.
  /// Updated every frame. Zero when not thrusting.
  final Vector2 thrustDirection = Vector2.zero();

  // Sub-systems
  late final DrillSystem drillSystem;
  late final CargoSystem cargoSystem;
  late final PodBody podBody;
  late final PodRenderer _renderer;

  // Stats (modified by upgrades)
  double enginePower = 3500.0;
  double maxFuel = GameConstants.baseFuelCapacity;
  double maxHull = GameConstants.baseHullHP;
  double maxCargo = GameConstants.baseCargoCapacity;
  double drillSpeed = GameConstants.baseDrillSpeed;

  // Drill entry smoothing — bleeds horizontal velocity over 0.3s
  double _drillEntryTimer = 0;
  static const double _drillEntryDuration = 0.3;

  // Wall bonk cooldown to avoid spam
  double _wallBonkCooldown = 0;

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

    // Robot shape
    final shape = PolygonShape()..setAsBoxXY(0.9, 1.1);

    body.createFixture(FixtureDef(shape)
      ..density = GameConstants.podBaseMass / (1.8 * 2.2)
      ..friction = 0.3
      ..restitution = 0.0
      ..filter.categoryBits = GameConstants.collisionCategoryPod
      ..filter.maskBits = GameConstants.collisionMaskPod
      ..userData = this);

    // Ground sensor — positioned so its bottom edge is flush with the hull
    // bottom (y=1.1). A half-height of 0.05 centered at y=1.05 means the
    // sensor spans y=1.0 to y=1.1, detecting ground exactly when the hull
    // touches terrain. The old position (center y=1.1, halfH=0.1) extended
    // to y=1.2, detecting ground 0.1m before physical contact = floating.
    final sensorShape = PolygonShape()
      ..setAsBox(0.7, 0.05, Vector2(0, 1.05), 0);

    body.createFixture(FixtureDef(sensorShape)
      ..isSensor = true
      ..filter.categoryBits = GameConstants.collisionCategoryPod
      ..filter.maskBits = GameConstants.collisionMaskPod
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

    _previousState = state;

    // Update state based on conditions
    _updateState();

    // Detect drill entry transition
    if (state == PodState.drilling && _previousState != PodState.drilling) {
      _drillEntryTimer = _drillEntryDuration;
    }

    // Apply physics forces
    _applyForces(dt);

    // Update depth-based damping
    _updateDamping();

    // Soft velocity cap — instead of a hard clamp that causes jerky stopping,
    // apply a drag force that ramps up as speed exceeds the limit.
    // This produces smooth deceleration rather than abrupt velocity snapping.
    final speed = body.linearVelocity.length;
    if (speed > GameConstants.podMaxSpeed) {
      final excess = speed - GameConstants.podMaxSpeed;
      // Quadratic drag: gentle near the limit, strong well above it
      final dragMag = body.mass * excess * excess * 2.0;
      final drag = body.linearVelocity.clone()
        ..normalize()
        ..scale(-dragMag);
      body.applyForce(drag);
    }

    // Consume fuel
    _consumeFuel(dt);

    // Update wall bonk cooldown
    if (_wallBonkCooldown > 0) _wallBonkCooldown -= dt;

    // Check death conditions
    _checkDeath();
  }

  void _updateState() {
    if (_game.hullSystem.currentHull <= 0 || state == PodState.dead) {
      state = PodState.dead;
      return;
    }

    // Drilling takes highest priority — drillDown + grounded should always win
    if (drillDown && podBody.isGrounded) {
      state = PodState.drilling;
      return;
    }

    // Surfaced only when above ground AND not actively thrusting/drilling
    if (_game.isAtSurface && !thrustUp && !thrustLeft && !thrustRight) {
      state = PodState.surfaced;
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
    // gravity = 9.8 m/s², so thrustAccel > 9.8 means robot can fly upward.
    // At level 0 (3000 power): 11.5 m/s² → net upward ~1.7 m/s² (sluggish starter)
    // At V4 1600cc (4500): 17.25 → comfortable flight
    // At V4 Turbo (6500): 24.9 → agile
    final thrustAccel = 11.5 * (enginePower / 3000.0);

    // Determine thrust magnitude: analog (touch) takes priority over binary (keyboard)
    final hasAnalog = thrustAnalogX != 0.0 || thrustAnalogY != 0.0;
    final forceX = hasAnalog
        ? thrustAnalogX
        : (thrustLeft ? -1.0 : 0.0) + (thrustRight ? 1.0 : 0.0);
    final forceY = hasAnalog ? thrustAnalogY : (thrustUp ? -1.0 : 0.0);

    // Update public thrust direction for renderer/particles
    thrustDirection.setValues(forceX, forceY);
    if (thrustDirection.length2 > 0) {
      thrustDirection.normalize();
    }

    final isThrusting = forceX != 0 || forceY < 0;

    if (_game.fuelSystem.hasFuel && isThrusting) {
      // Reduce thrust when fuel is critically low
      final fuelRatio = _game.fuelSystem.fuelRatio;
      double thrustMultiplier = 1.0;
      if (fuelRatio < GameConstants.reducedThrustThreshold) {
        thrustMultiplier = fuelRatio / GameConstants.reducedThrustThreshold;
      }

      // Cargo-dependent handling: thrust drops to 70% at full cargo
      final cargoFill = cargoSystem.fillRatio;
      final cargoMultiplier = 1.0 - cargoFill * 0.3; // 1.0 empty → 0.7 full

      final effectiveAccel = thrustAccel * thrustMultiplier * cargoMultiplier;

      if (forceY < 0) {
        body.applyForce(Vector2(0, body.mass * effectiveAccel * forceY));
        _game.audioManager.playEngineThrust();
      }
      if (forceX != 0) {
        body.applyForce(Vector2(body.mass * effectiveAccel * 0.85 * forceX, 0));
        _game.audioManager.playEngineThrust();
      }
    }

    // Grounded friction: stronger horizontal damping when grounded and not thrusting
    if (podBody.isGrounded && !isThrusting && state != PodState.drilling) {
      final vel = body.linearVelocity;
      if (vel.x.abs() > 0.1) {
        body.applyForce(Vector2(-vel.x * body.mass * 6.0, 0));
      }
    }

    // Drilling
    if (state == PodState.drilling) {
      // Drill entry smoothing: bleed horizontal velocity over 0.3s
      if (_drillEntryTimer > 0) {
        _drillEntryTimer -= dt;
        final t = (_drillEntryTimer / _drillEntryDuration).clamp(0.0, 1.0);
        final vel = body.linearVelocity;
        body.linearVelocity = Vector2(vel.x * t, vel.y);
      }

      drillSystem.drill(dt);
      body.applyForce(Vector2(0, body.mass * 2));
    }
  }

  // Smoothed damping value to prevent frame-to-frame jitter
  double _smoothedDamping = GameConstants.podLinearDamping;

  /// Adjust linear damping based on depth for heavier underground feel.
  /// Uses smoothing to prevent the per-frame damping changes from causing
  /// micro-stutters as the robot oscillates around depth thresholds.
  void _updateDamping() {
    // Surface: base damping (0.4). Deep underground: up to 0.8.
    // Reduced max damping from 1.0 to 0.8 — 1.0 felt too sluggish.
    final depthRatio =
        _game.depthSystem.normalizedDepth; // 0.0 surface → 1.0 max
    final targetDamping =
        GameConstants.podLinearDamping + depthRatio * 0.4; // 0.4 → 0.8
    // Smooth toward target to prevent jitter (lerp at ~2 Hz effective rate)
    _smoothedDamping += (targetDamping - _smoothedDamping) * 0.05;
    body.linearDamping = _smoothedDamping;
  }

  void _consumeFuel(double dt) {
    if (state == PodState.surfaced || state == PodState.dead) return;

    double consumption;

    if (state == PodState.flying) {
      // Analog thrust magnitude affects fuel burn (partial stick = less fuel)
      final hasAnalog = thrustAnalogX != 0.0 || thrustAnalogY != 0.0;
      final thrustMag = hasAnalog
          ? (thrustAnalogX.abs() + thrustAnalogY.abs().clamp(0.0, 1.0))
              .clamp(0.3, 1.0)
          : 1.0;
      consumption = GameConstants.fuelConsumptionThrust * thrustMag;
    } else if (state == PodState.drilling) {
      consumption = GameConstants.fuelConsumptionDrill;
    } else if (state == PodState.grounded || state == PodState.idle) {
      consumption = 0; // No fuel drain when grounded
    } else {
      consumption = GameConstants.fuelConsumptionIdle;
    }

    if (consumption > 0) {
      _game.fuelSystem.consumeFuel(consumption * dt);
    }
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

  /// Get robot position in world units
  Vector2 get podPosition => body.position;

  /// Get current depth in feet
  double get depthFeet => position.y * GameConstants.feetPerTile;

  /// Update physics body mass when cargo changes.
  ///
  /// Replaces the main fixture with a new one whose density reflects
  /// the combined robot base mass + current cargo weight.
  void updateMass() {
    // Find the first non-sensor fixture (the main robot shape)
    Fixture? mainFixture;
    for (final f in body.fixtures) {
      if (f.userData != 'ground_sensor') {
        mainFixture = f;
        break;
      }
    }
    if (mainFixture == null) return;

    const area = 1.8 * 2.2; // Robot width * height
    final totalMass = GameConstants.podBaseMass + cargoSystem.currentWeight;
    final newDensity = totalMass / area;

    final newDef = FixtureDef(mainFixture.shape)
      ..density = newDensity
      ..friction = 0.3
      ..restitution = 0.0
      ..filter.categoryBits = GameConstants.collisionCategoryPod
      ..filter.maskBits = GameConstants.collisionMaskPod
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
    } else {
      // Non-sensor collision — check for wall bonk (horizontal impact)
      _checkWallBonk(contact);
    }
  }

  /// Detect horizontal terrain collisions and trigger camera shake + haptic.
  /// Uses velocity to infer impact direction since Contact doesn't expose
  /// world manifold normals in flame_forge2d.
  void _checkWallBonk(Contact contact) {
    if (_wallBonkCooldown > 0) return;

    final vel = body.linearVelocity;
    final horizSpeed = vel.x.abs();

    // Only trigger on meaningful horizontal impact where horizontal velocity
    // dominates (wall, not floor)
    if (horizSpeed < 3.0 || horizSpeed < vel.y.abs()) return;

    final intensity = (horizSpeed / 15.0).clamp(0.1, 0.4);
    _game.earthquakeSystem.startShake(intensity, 0.15);
    HapticFeedback.lightImpact();
    _wallBonkCooldown = 0.3;
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
