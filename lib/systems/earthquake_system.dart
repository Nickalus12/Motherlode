import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/physics/collapse_detector.dart';
import 'package:motherlode/physics/explosion_system.dart';

/// Manages earthquakes, cave collapses, and explosion effects
///
/// Random force impulses triggered at score milestones.
/// Handles collapse detection and debris creation.
class EarthquakeSystem extends Component with HasGameReference<MotherlodeGame> {
  final MotherlodeGame _game;
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

  // Explosion flash effect (white bloom that fades)
  double _explosionFlash = 0;

  // Drill vibration state
  bool _isDrillVibrating = false;
  double _drillVibrationIntensity = 0;

  EarthquakeSystem({required MotherlodeGame game}) : _game = game;

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

    // Decay explosion flash
    if (_explosionFlash > 0) {
      _explosionFlash = (_explosionFlash - dt * 4.0).clamp(0.0, 1.0);
    }

    // Drill vibration scales with progress (subtle at start, strong near completion)
    if (_isDrillVibrating && !_shaking) {
      final scale = 0.02 + _drillVibrationIntensity * 0.06;
      final vx = (_random.nextDouble() - 0.5) * scale;
      final vy = (_random.nextDouble() - 0.5) * scale;
      _game.camera.viewfinder.position += Vector2(vx, vy);
    }
    _isDrillVibrating = false; // Reset each frame; DrillSystem sets it

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

  /// Stagger interval between debris spawns for cascade visual effect (seconds).
  static const double _cascadeStaggerInterval = 0.02; // 20ms per cell

  /// Cavity width threshold to trigger extra screen shake.
  static const int _largeCavityThreshold = 4;

  /// Process a list of cells that should collapse.
  /// Cells are pre-sorted by distance for staggered cascade spawning.
  void _processCollapse(List<CollapseCell> cells) {
    if (cells.isEmpty) return;

    // Large cavity detection: if horizontal span is wide, add screen shake
    if (cells.length >= _largeCavityThreshold) {
      int minX = cells.first.gridX, maxX = cells.first.gridX;
      for (final c in cells) {
        if (c.gridX < minX) minX = c.gridX;
        if (c.gridX > maxX) maxX = c.gridX;
      }
      final width = maxX - minX + 1;
      if (width > _largeCavityThreshold) {
        final intensity = (width / 10.0).clamp(0.3, 0.8);
        startShake(intensity, 0.4 + width * 0.05);
      }
    }

    // Spawn debris with staggered delay based on distance from center
    for (int i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final delay = i * _cascadeStaggerInterval;

      if (delay <= 0) {
        _spawnDebris(cell);
      } else {
        Future.delayed(Duration(milliseconds: (delay * 1000).round()), () {
          if (_game.isGameOver) return;
          _spawnDebris(cell);
        });
      }
    }
  }

  /// Spawn a single debris body from a collapse cell.
  void _spawnDebris(CollapseCell cell) {
    _game.removeTerrainCell(cell.gridX, cell.gridY);

    final debris = _game.debrisManager.createDebris(
      position: Vector2(
        cell.gridX.toDouble(),
        cell.gridY.toDouble(),
      ),
      color: cell.color,
      mass: cell.mass,
      halfSize: cell.halfSize,
    );

    _game.world.add(debris);
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

    // Random force to robot
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
    final offsetX =
        (_random.nextDouble() - 0.5) * _shakeIntensity * decay * 0.5;
    final offsetY =
        (_random.nextDouble() - 0.5) * _shakeIntensity * decay * 0.5;

    _game.camera.viewfinder.position += Vector2(offsetX, offsetY);
  }

  /// Trigger a brief white flash overlay (called by ExplosionSystem).
  void triggerExplosionFlash() {
    _explosionFlash = 1.0;
  }

  /// Signal that the drill is actively cutting this frame.
  /// Call every frame during drilling for continuous vibration.
  /// [intensity] is 0.0-1.0 drill progress for scaling vibration strength.
  void setDrillVibrating({double intensity = 0}) {
    _isDrillVibrating = true;
    _drillVibrationIntensity = intensity;
  }

  /// Whether an earthquake is currently happening
  bool get isShaking => _shaking;

  /// Current shake intensity (for HUD effects)
  double get currentShakeIntensity => _shaking ? _shakeIntensity : 0;

  /// Current explosion flash intensity (0.0 to 1.0) for LightingSystem.
  double get explosionFlash => _explosionFlash;
}
