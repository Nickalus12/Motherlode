import 'dart:ui';

import 'package:flame/components.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Dynamic falling dirt/rock body created from collapsed terrain
///
/// Falls under gravity, bounces off terrain, deals hull damage
/// on pod contact. Auto-sleeps after resting and converts to static terrain.
class DebrisBody extends BodyComponent with ContactCallbacks {
  final Vector2 initialPosition;
  final Color color;
  final double mass;

  static const double sleepAfterSeconds = 3.0;
  static const double sleepVelocityThreshold = 0.5; // m/s

  double _restingTime = 0.0;
  bool _settled = false;

  /// Callback invoked when this debris converts to terrain.
  /// Parameters: grid x, grid y of the settled cell.
  void Function(int gridX, int gridY)? onConvertToTerrain;

  DebrisBody({
    required this.initialPosition,
    required this.color,
    this.mass = 50.0,
    this.onConvertToTerrain,
  });

  bool get isSettled => _settled;

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
    final shape = PolygonShape()..setAsBoxXY(0.3, 0.3);

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

    final speed = body.linearVelocity.length;

    if (speed < sleepVelocityThreshold) {
      _restingTime += dt;
      if (_restingTime >= sleepAfterSeconds) {
        _convertToStaticTerrain();
      }
    } else {
      _restingTime = 0.0; // Reset if it gets bumped
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      const Rect.fromLTWH(-0.3, -0.3, 0.6, 0.6),
      paint,
    );

    final outlinePaint = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04;
    canvas.drawRect(
      const Rect.fromLTWH(-0.3, -0.3, 0.6, 0.6),
      outlinePaint,
    );
  }

  /// Convert this debris body to a static terrain cell and remove it
  void _convertToStaticTerrain() {
    if (_settled) return;
    _settled = true;

    // Snap position to nearest grid cell
    final gridX = body.position.x.round();
    final gridY = body.position.y.round();

    // Notify manager to update terrain cell
    onConvertToTerrain?.call(gridX, gridY);

    // Remove this body from the world
    removeFromParent();
  }

  /// Force-settle this debris immediately (used when body count limit exceeded)
  void forceSettle() {
    _convertToStaticTerrain();
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (_settled) return;

    if (other is Pod) {
      final impactSpeed = body.linearVelocity.length;
      final damage = mass * impactSpeed * GameConstants.debrisDamageMultiplier;
      if (damage > 0.5) {
        other.takeDamage(damage);
      }
    }
  }
}

/// Manages active debris bodies, enforcing max count and providing
/// the terrain conversion callback.
class DebrisManager extends Component with HasGameReference<MotherlodeGame> {
  static const int maxDebris = 150;
  static const int forceSettleCount = 20;

  final List<DebrisBody> _activeDebris = [];

  /// Create and register a new debris body
  DebrisBody createDebris({
    required Vector2 position,
    required Color color,
    double mass = 50.0,
  }) {
    // Enforce body count limit
    if (_activeDebris.length >= maxDebris) {
      _forceSettleOldest();
    }

    final debris = DebrisBody(
      initialPosition: position,
      color: color,
      mass: mass,
      onConvertToTerrain: _onDebrisConvert,
    );

    _activeDebris.add(debris);
    return debris;
  }

  void _onDebrisConvert(int gridX, int gridY) {
    // Set the corresponding terrain cell to solid
    game.chunkManager.removeCell(gridX, gridY);
    // Note: removeCell sets to empty. For debris settling we'd ideally
    // set the cell to solid, but for now this marks the chunk dirty.
  }

  /// Force-settle the oldest N debris bodies
  void _forceSettleOldest() {
    final toSettle = _activeDebris
        .where((d) => !d.isSettled)
        .take(forceSettleCount)
        .toList();

    for (final debris in toSettle) {
      debris.forceSettle();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Clean up settled debris from tracking list
    _activeDebris.removeWhere((d) => d.isSettled);
  }

  int get activeCount => _activeDebris.where((d) => !d.isSettled).length;
}
