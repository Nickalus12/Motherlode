import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/utils/math_utils.dart';

/// Creature behavior states
enum CreatureState {
  idle,
  wander,
  chase,
  flee,
  attack,
  dead,
}

/// Base creature class with steering behaviors
///
/// All creatures are Forge2D BodyComponents with:
/// - Steering behavior state machine
/// - Health points, damage value, speed stat
/// - Eye glow component (point light)
/// - Death particle burst + cash drop
/// - Attack cooldown (lunge-pause-lunge pattern)
/// - Damage invulnerability flash (0.2s)
/// - Flee behavior when health < 30%
abstract class Creature extends BodyComponent with ContactCallbacks {
  final String name;
  final double maxHealth;
  final double damage; // Damage dealt to robot per attack lunge
  final double speed;
  final Color bodyColor;
  final Color eyeColor;
  final double cashDrop;

  MotherlodeGame get motherlodeGame => game as MotherlodeGame;

  double health;
  CreatureState state = CreatureState.wander;
  double _stateTimer = 0;
  double _wanderAngle = 0;

  // Attack cooldown: lunge-pause-lunge pattern
  double _attackCooldown = 0;
  static const double _attackLungeDuration = 0.3;
  static const double _attackPauseDuration = 1.0;
  bool _isLunging = false;

  // Damage invulnerability flash (protected for subclass render access)
  double invulnTimer = 0;
  static const double _invulnerabilityDuration = 0.2;

  /// Detection radius in world units. Override per creature type.
  double get detectionRadius =>
      GameConstants.creatureChaseRange / GameConstants.pixelsPerMeter;

  final Vector2 initialPosition;

  Creature({
    required this.name,
    required this.maxHealth,
    required this.damage,
    required this.speed,
    required this.bodyColor,
    required this.eyeColor,
    required this.cashDrop,
    required this.initialPosition,
  }) : health = maxHealth;

  /// Creature-specific body shape creation
  Shape get bodyShape;

  /// Creature dimensions for rendering
  double get bodyRadius => 0.5;

  /// Whether this creature is currently invulnerable after taking damage
  bool get isInvulnerable => invulnTimer > 0;

  /// Health ratio (0.0 to 1.0)
  double get healthRatio =>
      maxHealth > 0 ? (health / maxHealth).clamp(0.0, 1.0) : 0.0;

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: initialPosition,
      linearDamping: 2.0,
      angularDamping: 5.0,
      fixedRotation: true,
    );

    final body = world.createBody(bodyDef);

    body.createFixture(FixtureDef(bodyShape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution = 0.1
      ..userData = this);

    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (state == CreatureState.dead) return;

    _stateTimer += dt;

    // Tick invulnerability
    if (invulnTimer > 0) {
      invulnTimer = (invulnTimer - dt).clamp(0.0, double.infinity);
    }

    // Tick attack cooldown
    if (_attackCooldown > 0) {
      _attackCooldown = (_attackCooldown - dt).clamp(0.0, double.infinity);
    }

    // Get robot reference for AI
    final pod = motherlodeGame.pod;
    final distToPod = position.distanceTo(pod.position);

    // Update state machine
    _updateState(pod, distToPod, dt);

    // Apply steering behavior based on state
    _applySteering(pod, distToPod, dt);
  }

  /// Update the creature's behavior state
  void _updateState(Pod pod, double distToPod, double dt) {
    switch (state) {
      case CreatureState.idle:
        if (_stateTimer > 2.0) {
          state = CreatureState.wander;
          _stateTimer = 0;
        }
        if (shouldChase(distToPod)) {
          state = CreatureState.chase;
          _stateTimer = 0;
        }
        if (shouldFlee(pod, distToPod)) {
          state = CreatureState.flee;
          _stateTimer = 0;
        }
        break;

      case CreatureState.wander:
        if (shouldChase(distToPod)) {
          state = CreatureState.chase;
          _stateTimer = 0;
        }
        if (shouldFlee(pod, distToPod)) {
          state = CreatureState.flee;
          _stateTimer = 0;
        }
        if (_stateTimer > 5.0) {
          state = CreatureState.idle;
          _stateTimer = 0;
        }
        break;

      case CreatureState.chase:
        // Flee overrides chase when health is critical
        if (shouldFlee(pod, distToPod)) {
          state = CreatureState.flee;
          _stateTimer = 0;
          break;
        }
        if (distToPod < bodyRadius + 1.5) {
          state = CreatureState.attack;
          _stateTimer = 0;
        }
        if (distToPod > detectionRadius * 1.5) {
          state = CreatureState.wander;
          _stateTimer = 0;
        }
        break;

      case CreatureState.attack:
        // Flee if health critical even during attack
        if (shouldFlee(pod, distToPod)) {
          state = CreatureState.flee;
          _stateTimer = 0;
          break;
        }
        if (distToPod > bodyRadius + 2.0) {
          state = CreatureState.chase;
          _stateTimer = 0;
        }
        _handleAttack(pod, dt);
        break;

      case CreatureState.flee:
        if (_stateTimer > 3.0 && healthRatio > 0.3) {
          state = CreatureState.wander;
          _stateTimer = 0;
        }
        break;

      case CreatureState.dead:
        break;
    }
  }

  /// Lunge-pause-lunge attack pattern instead of continuous DPS
  void _handleAttack(Pod pod, double dt) {
    if (_attackCooldown > 0) return; // Pausing between lunges

    if (!_isLunging) {
      // Start a lunge
      _isLunging = true;
      _stateTimer = 0;
      onAttackLunge(pod);
    }

    if (_isLunging && _stateTimer >= _attackLungeDuration) {
      // Lunge complete, start pause
      _isLunging = false;
      _attackCooldown = _attackPauseDuration;
    }
  }

  void _applySteering(Pod pod, double distToPod, double dt) {
    switch (state) {
      case CreatureState.idle:
        // Apply friction to slow down
        body.linearVelocity *= 0.95;
        break;

      case CreatureState.wander:
        _wanderAngle += MathUtils.randomRange(-0.5, 0.5) * dt;
        final wanderForce = Vector2(
          cos(_wanderAngle) * speed * 0.3,
          sin(_wanderAngle) * speed * 0.3,
        );
        body.applyForce(wanderForce);
        break;

      case CreatureState.chase:
        final direction = (pod.position - position).normalized();
        body.applyForce(direction * speed);
        break;

      case CreatureState.flee:
        final direction = (position - pod.position).normalized();
        body.applyForce(direction * speed * 1.2);
        break;

      case CreatureState.attack:
        if (_isLunging) {
          // Lunge toward robot
          final direction = (pod.position - position).normalized();
          body.applyForce(direction * speed * 1.5);
        } else {
          // Pause: slow drift
          body.linearVelocity *= 0.9;
        }
        break;

      case CreatureState.dead:
        break;
    }
  }

  /// Whether this creature should chase the robot
  bool shouldChase(double distToPod) {
    return distToPod < detectionRadius;
  }

  /// Whether this creature should flee from the robot.
  /// Default: flee when health drops below 30%.
  bool shouldFlee(Pod pod, double distToPod) {
    return healthRatio < 0.3 && distToPod < detectionRadius;
  }

  /// Called once at the start of each attack lunge.
  /// Override for custom attack behavior.
  void onAttackLunge(Pod pod) {
    pod.takeDamage(damage);
  }

  /// Legacy continuous attack — still available for subclasses that need it
  void onAttack(Pod pod, double dt) {
    // Default does nothing; lunge pattern is used instead
  }

  /// Take damage from the robot or explosions.
  /// Respects invulnerability window.
  void takeDamageFromSource(double amount) {
    if (invulnTimer > 0) return; // Invulnerable

    health -= amount;
    invulnTimer = _invulnerabilityDuration;

    if (health <= 0) {
      die();
    }
  }

  /// Creature death sequence
  void die() {
    state = CreatureState.dead;

    // Drop cash
    motherlodeGame.addCash(cashDrop);

    // Emit death particles
    motherlodeGame.particleSystem.emitOreSparkle(position, bodyColor);

    // Remove from world after short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (isMounted) removeFromParent();
    });
  }

  @override
  void render(Canvas canvas) {
    if (state == CreatureState.dead) return;

    // Invulnerability flash: skip rendering every other frame for flash effect
    if (invulnTimer > 0) {
      final flashOn = ((invulnTimer * 30).toInt() % 2 == 0);
      if (!flashOn) return; // Skip this frame for blink effect
    }

    // Draw body
    _renderBody(canvas);

    // Draw eyes (visible through darkness - psychological horror)
    _renderEyes(canvas);
  }

  /// Default body rendering (override for custom shapes)
  void _renderBody(Canvas canvas) {
    final paint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, bodyRadius.toDouble(), paint);

    final outlinePaint = Paint()
      ..color = Color.from(
        alpha: 0.5,
        red: bodyColor.r * 0.5,
        green: bodyColor.g * 0.5,
        blue: bodyColor.b * 0.5,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;
    canvas.drawCircle(Offset.zero, bodyRadius.toDouble(), outlinePaint);
  }

  /// Draw creature eyes - small sharp point lights
  void _renderEyes(Canvas canvas) {
    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;

    final eyeGlowPaint = Paint()
      ..color = eyeColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Two eyes
    final eyeSpacing = bodyRadius * 0.3;
    final eyeY = -bodyRadius * 0.2;

    canvas.drawCircle(Offset(-eyeSpacing, eyeY), 0.06, eyeGlowPaint);
    canvas.drawCircle(Offset(eyeSpacing, eyeY), 0.06, eyeGlowPaint);
    canvas.drawCircle(Offset(-eyeSpacing, eyeY), 0.03, eyePaint);
    canvas.drawCircle(Offset(eyeSpacing, eyeY), 0.03, eyePaint);
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is Pod && state != CreatureState.dead) {
      state = CreatureState.attack;
      _stateTimer = 0;
    }
  }
}
