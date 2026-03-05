import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/physics/collapse_detector.dart';
import 'package:hellbore/physics/debris_body.dart';
import 'package:hellbore/physics/explosion_system.dart';
import 'package:hellbore/utils/constants.dart';

/// Manages earthquakes, cave collapses, and explosion effects
///
/// Random force impulses triggered at score milestones.
/// Handles collapse detection and debris creation.
class EarthquakeSystem extends Component with HasGameReference<HellboreGame> {
  final HellboreGame _game;
  late final CollapseDetector _collapseDetector;
  late final ExplosionSystem _explosionSystem;

  final Random _random = Random();

  // Earthquake tracking
  double _earthquakeTimer = 0;
  double _nextEarthquakeTime = 60; // First earthquake after 60 seconds
  double _lastCashMilestone = 0;
  bool _shaking = false;
  double _shakeIntensity = 0;
  double _shakeDuration = 0;

  EarthquakeSystem({required HellboreGame game}) : _game = game;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _collapseDetector = CollapseDetector(game: _game);
    _explosionSystem = ExplosionSystem(game: _game);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Update earthquake timer
    _earthquakeTimer += dt;

    // Check for random earthquakes
    if (_earthquakeTimer >= _nextEarthquakeTime && !_game.isAtSurface) {
      _triggerRandomEarthquake();
    }

    // Check for cash milestone earthquakes
    _checkCashMilestone();

    // Update screen shake
    if (_shaking) {
      _shakeDuration -= dt;
      if (_shakeDuration <= 0) {
        _shaking = false;
        _shakeIntensity = 0;
      } else {
        _applyShake(dt);
      }
    }
  }

  /// Check structural integrity after a cell is removed
  void checkCollapse(int gridX, int gridY) {
    final collapseCells = _collapseDetector.checkCollapse(gridX, gridY);
    _processCollapse(collapseCells);
  }

  /// Check collapse in a larger area (after explosion)
  void checkCollapseArea(int centerX, int centerY, int radius) {
    final collapseCells =
        _collapseDetector.checkCollapseArea(centerX, centerY, radius);
    _processCollapse(collapseCells);
  }

  /// Trigger an explosion (from consumable)
  void triggerExplosion(Vector2 position, int radius, double force) {
    _explosionSystem.explode(position, radius, force);
  }

  /// Process a list of cells that should collapse
  void _processCollapse(List<CollapseCell> cells) {
    for (final cell in cells) {
      // Remove the terrain cell
      _game.removeTerrainCell(cell.gridX, cell.gridY);

      // Create debris body
      final debris = DebrisBody(
        initialPosition: Vector2(
          cell.gridX.toDouble(),
          cell.gridY.toDouble(),
        ),
        color: cell.color,
        mass: cell.density * 100,
      );

      _game.world.add(debris);
    }
  }

  void _triggerRandomEarthquake() {
    _earthquakeTimer = 0;
    _nextEarthquakeTime = 45 + _random.nextDouble() * 60; // 45-105 seconds

    // Only earthquake if deep enough
    if (_game.currentDepthFeet < 500) return;

    final intensity = 0.3 + _random.nextDouble() * 0.5;
    startShake(intensity, 1.5 + _random.nextDouble());

    // Cause some random collapses nearby
    final podX = _game.pod.position.x.round();
    final podY = _game.pod.position.y.round();
    final radius = 3 + _random.nextInt(5);

    // Random force to pod
    _game.pod.applyImpulse(Vector2(
      (_random.nextDouble() - 0.5) * intensity * 50,
      (_random.nextDouble() - 0.5) * intensity * 30,
    ));

    // Check for collapses
    checkCollapseArea(
      podX + _random.nextInt(10) - 5,
      podY + _random.nextInt(6),
      radius,
    );
  }

  void _checkCashMilestone() {
    // Trigger earthquake at cash milestones
    final cash = _game.playerCash;
    final milestone = (cash / 50000).floor() * 50000;

    if (milestone > _lastCashMilestone && milestone > 0) {
      _lastCashMilestone = milestone.toDouble();
      if (!_game.isAtSurface && _game.currentDepthFeet > 200) {
        startShake(0.5, 2.0);
      }
    }
  }

  /// Start screen shake
  void startShake(double intensity, double duration) {
    _shaking = true;
    _shakeIntensity = intensity;
    _shakeDuration = duration;
  }

  void _applyShake(double dt) {
    final decay = (_shakeDuration / 2.0).clamp(0.0, 1.0);
    final offsetX = (_random.nextDouble() - 0.5) * _shakeIntensity * decay * 0.5;
    final offsetY = (_random.nextDouble() - 0.5) * _shakeIntensity * decay * 0.5;

    _game.camera.viewfinder.position += Vector2(offsetX, offsetY);
  }

  /// Whether an earthquake is currently happening
  bool get isShaking => _shaking;

  /// Current shake intensity (for HUD effects)
  double get currentShakeIntensity => _shaking ? _shakeIntensity : 0;
}
