import 'package:flame/components.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Hull damage and integrity system
///
/// Hull takes damage from:
/// - Lava contact
/// - Gas exposure
/// - Creature attacks
/// - Cave collapse debris
/// - Fall damage (high velocity impact)
class HullSystem extends Component {
  final MotherlodeGame game;

  double currentHull = 0;
  double maxHull = GameConstants.baseHullHP;

  // Damage tracking for HUD effects
  double _lastDamageTime = 0;
  double _totalDamageTaken = 0;

  // Lava/gas damage immunity after radiator upgrade
  double heatResistance = 0; // 0.0 to 1.0

  // Hazard exposure state (for visual feedback in LightingSystem)
  bool inLava = false;
  bool inGas = false;

  HullSystem({required this.game});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    currentHull = maxHull;
  }

  /// Current hull as a ratio (0.0 to 1.0)
  double get hullRatio =>
      maxHull > 0 ? (currentHull / maxHull).clamp(0.0, 1.0) : 0.0;

  /// Whether hull is critically low
  bool get isLowHull => hullRatio < GameConstants.lowHullThreshold;

  /// Whether hull damage was recently taken (for HUD flash)
  bool get recentDamage => _lastDamageTime < 0.5;

  /// Whether the pod is destroyed
  bool get isDestroyed => currentHull <= 0;

  @override
  void update(double dt) {
    super.update(dt);
    _lastDamageTime += dt;

    // Continuous damage from hazards
    _checkHazardDamage(dt);
  }

  /// Take hull damage from a source
  void takeDamage(double amount) {
    currentHull = (currentHull - amount).clamp(0, maxHull);
    _lastDamageTime = 0;
    _totalDamageTaken += amount;
    game.audioManager.playHullDamage();

    if (currentHull <= 0) {
      game.triggerGameOver();
    }
  }

  /// Take heat damage (reduced by radiator)
  void takeHeatDamage(double amount) {
    final reducedAmount = amount * (1.0 - heatResistance);
    if (reducedAmount > 0) {
      takeDamage(reducedAmount);
    }
  }

  /// Take fall damage based on impact velocity
  void takeFallDamage(double impactVelocity) {
    // Only damage above a threshold velocity
    const threshold = 8.0; // m/s
    if (impactVelocity.abs() > threshold) {
      final damage = (impactVelocity.abs() - threshold) * 2;
      takeDamage(damage);
      // Camera shake proportional to impact severity
      final shakeIntensity =
          ((impactVelocity.abs() - threshold) / 10.0).clamp(0.2, 0.8);
      game.earthquakeSystem.startShake(shakeIntensity, 0.3);
      HapticFeedback.mediumImpact();
    }
  }

  /// Repair hull (from nanobots or repair station)
  void repair(double amount) {
    currentHull = (currentHull + amount).clamp(0, maxHull);
  }

  /// Full repair
  double fullRepair() {
    final needed = maxHull - currentHull;
    currentHull = maxHull;
    return needed;
  }

  /// Upgrade max hull
  void upgradeHull(double newMax) {
    final wasRatio = hullRatio;
    maxHull = newMax;
    // Maintain the same health ratio after upgrade
    currentHull = maxHull * wasRatio;
  }

  /// Check if pod is in contact with lava or gas
  void _checkHazardDamage(double dt) {
    inLava = false;
    inGas = false;

    if (game.isAtSurface) return;

    // Check cells around pod position for hazards
    final podX = game.pod.position.x.round();
    final podY = game.pod.position.y.round();

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        final cellType = game.getCellType(podX + dx, podY + dy);

        // CellType.lava = 5, CellType.gas = 6
        if (cellType == 5) {
          inLava = true;
          game.audioManager.playLavaBurn();
          takeHeatDamage(GameConstants.lavaDamagePerSecond * dt);
        } else if (cellType == 6) {
          inGas = true;
          takeHeatDamage(GameConstants.gasDamagePerSecond * dt);
        }
      }
    }
  }

  /// Serialize
  Map<String, dynamic> toMap() {
    return {
      'current': currentHull,
      'max': maxHull,
      'heatResist': heatResistance,
      'totalDamage': _totalDamageTaken,
    };
  }

  void loadFromMap(Map<String, dynamic> map) {
    currentHull = (map['current'] as num).toDouble();
    maxHull = (map['max'] as num).toDouble();
    heatResistance = (map['heatResist'] as num?)?.toDouble() ?? 0;
    _totalDamageTaken = (map['totalDamage'] as num?)?.toDouble() ?? 0;
  }
}
