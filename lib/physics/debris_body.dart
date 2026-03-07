import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Dynamic falling dirt/rock body created from collapsed terrain
///
/// Falls under gravity, bounces off terrain, deals hull damage
/// on robot contact. Auto-sleeps after resting and converts to static terrain.
/// Size and mass vary by material type.
class DebrisBody extends BodyComponent with ContactCallbacks {
  final Vector2 initialPosition;
  final Color color;
  final double mass;
  final double halfSize;

  static const double sleepAfterSeconds = 3.0;
  static const double sleepVelocityThreshold = 0.5; // m/s
  static final Random _rng = Random();

  double _restingTime = 0.0;
  bool _settled = false;

  // Pre-allocated Paint objects to avoid per-frame GC pressure
  late final Paint _fillPaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final Paint _outlinePaint = Paint()
    ..color = const Color(0x40000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.04;

  // Cached rect for rendering
  late final Rect _drawRect =
      Rect.fromLTWH(-halfSize, -halfSize, halfSize * 2, halfSize * 2);

  /// Callback invoked when this debris converts to terrain.
  /// Parameters: grid x, grid y of the settled cell.
  void Function(int gridX, int gridY)? onConvertToTerrain;

  /// Callback invoked when debris settles (for impact dust).
  void Function(Vector2 position)? onSettle;

  DebrisBody({
    required this.initialPosition,
    required this.color,
    this.mass = 50.0,
    this.halfSize = 0.3,
    this.onConvertToTerrain,
    this.onSettle,
  });

  bool get isSettled => _settled;

  @override
  Body createBody() {
    // Random angular velocity on spawn (±3 rad/s)
    final angularVel = (_rng.nextDouble() - 0.5) * 6.0;

    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: initialPosition,
      linearDamping: 0.3,
      angularDamping: 0.5,
      angularVelocity: angularVel,
    );

    final body = world.createBody(bodyDef);

    final shape = PolygonShape()..setAsBoxXY(halfSize, halfSize);
    final area = (halfSize * 2) * (halfSize * 2);

    body.createFixture(FixtureDef(shape)
      ..density = mass / area
      ..friction = 0.8
      ..restitution = 0.2
      ..filter.categoryBits = GameConstants.collisionCategoryDebris
      ..filter.maskBits = GameConstants.collisionMaskDebris
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
    canvas.drawRect(_drawRect, _fillPaint);
    canvas.drawRect(_drawRect, _outlinePaint);
  }

  /// Convert this debris body to a static terrain cell and remove it
  void _convertToStaticTerrain() {
    if (_settled) return;
    _settled = true;

    // Emit impact dust at settle position
    onSettle?.call(body.position.clone());

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
  static const int maxDebris = 50;
  static const int forceSettleCount = 10;

  final List<DebrisBody> _activeDebris = [];

  /// Create and register a new debris body
  DebrisBody createDebris({
    required Vector2 position,
    required Color color,
    double mass = 50.0,
    double halfSize = 0.3,
  }) {
    // Enforce body count limit
    if (_activeDebris.length >= maxDebris) {
      _forceSettleOldest();
    }

    final debris = DebrisBody(
      initialPosition: position,
      color: color,
      mass: mass,
      halfSize: halfSize,
      onConvertToTerrain: _onDebrisConvert,
      onSettle: _onDebrisSettle,
    );

    _activeDebris.add(debris);
    return debris;
  }

  /// Emit a small dust puff when debris settles
  void _onDebrisSettle(Vector2 position) {
    if (!game.isMounted) return;
    game.particleSystem.emitDrillParticles(
      position,
      const Color(0xFF8B7355), // Dusty brown
    );
  }

  void _onDebrisConvert(int gridX, int gridY) {
    // Set the corresponding terrain cell to solid dirt
    final cell = game.chunkManager.getTerrainCell(gridX, gridY);
    if (cell != null) {
      cell.type = CellType.dirt;
      cell.sdf = -1.0;
      cell.oreType = null;
      cell.isDirty = true;
      game.chunkManager.markCellDirty(gridX, gridY);
    }
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

  double _cleanupTimer = 0;

  @override
  void update(double dt) {
    super.update(dt);
    // Rate-limit cleanup to avoid per-frame list iteration
    _cleanupTimer += dt;
    if (_cleanupTimer >= 0.5) {
      _cleanupTimer = 0;
      _activeDebris.removeWhere((d) => d.isSettled);
    }
  }

  int get activeCount => _activeDebris.length;
}
