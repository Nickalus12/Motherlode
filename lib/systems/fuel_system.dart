import 'package:flame/components.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Fuel consumption and management system
///
/// Fuel is consumed by movement (thrust) and drilling.
/// Low fuel reduces thrust power. Running out leaves the robot stranded.
class FuelSystem extends Component {
  final MotherlodeGame game;

  double currentFuel = 0;
  double maxFuel = GameConstants.baseFuelCapacity;

  // Warning flags
  bool _lowFuelWarningActive = false;
  bool _fuelDeathTriggered = false;
  double _outOfFuelTimer = 0;
  static const double _outOfFuelGracePeriod = 10.0; // seconds before game over

  // Low fuel audio warning (beep every 5 seconds when below 30%)
  double _fuelWarningBeepCooldown = 0;
  static const double _fuelWarningBeepInterval = 5.0;
  static const double _fuelWarningThreshold = 0.3;

  FuelSystem({required this.game});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Start with full fuel
    currentFuel = maxFuel;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Out of fuel underground: give player 10 seconds before game over
    // (they might have a teleporter or transmitter)
    if (currentFuel <= 0 &&
        !game.isAtSurface &&
        !game.isGameOver &&
        !_fuelDeathTriggered) {
      _outOfFuelTimer += dt;
      if (_outOfFuelTimer >= _outOfFuelGracePeriod) {
        _fuelDeathTriggered = true;
        game.triggerGameOver();
        game.particleSystem.emitExplosionDebris(game.pod.position, 5);
        game.audioManager.playExplosion();
        game.earthquakeSystem.startShake(0.8, 0.6);
        HapticFeedback.heavyImpact();
      }
    } else if (currentFuel > 0 || game.isAtSurface) {
      _outOfFuelTimer = 0;
    }

    // Low fuel audio warning: beep every 5 seconds when below 30%
    if (fuelRatio > 0 && fuelRatio < _fuelWarningThreshold && !game.isAtSurface) {
      _fuelWarningBeepCooldown -= dt;
      if (_fuelWarningBeepCooldown <= 0) {
        game.audioManager.playFuelWarning();
        _fuelWarningBeepCooldown = _fuelWarningBeepInterval;
      }
    } else {
      _fuelWarningBeepCooldown = 0;
    }
  }

  /// Current fuel as a ratio (0.0 to 1.0)
  double get fuelRatio =>
      maxFuel > 0 ? (currentFuel / maxFuel).clamp(0.0, 1.0) : 0.0;

  /// Whether any fuel remains
  bool get hasFuel => currentFuel > 0;

  /// Whether fuel is critically low
  bool get isLowFuel => fuelRatio < GameConstants.lowFuelThreshold;

  /// Consume fuel by a given amount
  void consumeFuel(double amount) {
    currentFuel = (currentFuel - amount).clamp(0, maxFuel);

    // Check low fuel warning
    if (isLowFuel && !_lowFuelWarningActive) {
      _lowFuelWarningActive = true;
      game.audioManager.playFuelWarning();
    } else if (!isLowFuel && _lowFuelWarningActive) {
      _lowFuelWarningActive = false;
    }
  }

  /// Add fuel (from reserve tank consumable or fuel station)
  void addFuel(double amount) {
    currentFuel = (currentFuel + amount).clamp(0, maxFuel);
    if (!isLowFuel) _lowFuelWarningActive = false;
  }

  /// Fill tank completely (at fuel station)
  /// Returns cost
  double fillTank() {
    final needed = maxFuel - currentFuel;
    final cost = needed * GameConstants.fuelCostPerLiter;
    currentFuel = maxFuel;
    _lowFuelWarningActive = false;
    return cost;
  }

  /// Upgrade max fuel capacity
  void upgradeCapacity(double newMax) {
    maxFuel = newMax;
  }

  /// Serialize
  Map<String, dynamic> toMap() {
    return {
      'current': currentFuel,
      'max': maxFuel,
    };
  }

  /// Load from save (handles missing/null keys gracefully)
  void loadFromMap(Map<String, dynamic> map) {
    currentFuel =
        (map['current'] as num?)?.toDouble() ?? GameConstants.baseFuelCapacity;
    maxFuel =
        (map['max'] as num?)?.toDouble() ?? GameConstants.baseFuelCapacity;
  }
}
