import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/world/ore_registry.dart';

/// Tracks a price boom event for a specific ore.
class MarketBoom {
  final String oreName;
  final double multiplier;
  double remainingSeconds;

  MarketBoom({
    required this.oreName,
    required this.multiplier,
    required this.remainingSeconds,
  });
}

/// Dynamic ore pricing system with supply/demand mechanics.
///
/// - Selling ore depresses its price multiplier.
/// - Prices recover toward 1.0x over time.
/// - Random boom events temporarily spike one ore's price.
/// - Combo bonus for selling 5+ of the same ore in one trip.
class MarketSystem extends Component {
  static const double _minMultiplier = 0.5;
  static const double _maxMultiplier = 3.0;
  static const double _sellPenaltyPerUnit = 0.05;
  static const double _recoveryPerSecond = 0.02 / 60; // 0.02 per game-minute
  static const double _boomMultiplier = 2.5;
  static const double _boomDurationSeconds = 60.0;
  static const double _boomIntervalMin = 180.0; // 3 minutes
  static const double _boomIntervalMax = 300.0; // 5 minutes
  static const int _comboThreshold = 5;
  static const double _comboBonus = 0.15;

  final Random _rng = Random();

  /// Current price multiplier per ore name. Default is 1.0x.
  final Map<String, double> _multipliers = {};

  /// Active boom event (null if none).
  MarketBoom? activeBoom;

  /// Countdown to next boom event.
  double _nextBoomTimer = 0;

  MarketSystem() {
    _scheduleNextBoom();
  }

  /// Get the current price multiplier for an ore (includes boom).
  double getMultiplier(String oreName) {
    double base = _multipliers[oreName] ?? 1.0;
    if (activeBoom != null && activeBoom!.oreName == oreName) {
      base = max(base, activeBoom!.multiplier);
    }
    return base.clamp(_minMultiplier, _maxMultiplier);
  }

  /// Get the effective sell price for one unit of an ore.
  double getEffectivePrice(OreType ore) {
    return ore.value * getMultiplier(ore.name);
  }

  /// Calculate sale value for a batch of ore, applying market multiplier
  /// and combo bonus if count >= threshold.
  double calculateSaleValue(OreType ore, int count) {
    final unitPrice = getEffectivePrice(ore);
    double total = unitPrice * count;
    if (count >= _comboThreshold) {
      total *= (1.0 + _comboBonus);
    }
    return total;
  }

  /// Record a sale: depress the ore's price multiplier.
  void recordSale(String oreName, int count) {
    final current = _multipliers[oreName] ?? 1.0;
    _multipliers[oreName] = (current - _sellPenaltyPerUnit * count)
        .clamp(_minMultiplier, _maxMultiplier);
  }

  /// Whether an ore currently has a combo bonus (informational for UI).
  bool hasComboBonus(int count) => count >= _comboThreshold;

  /// Whether a boom is active for the given ore.
  bool isBoomActive(String oreName) =>
      activeBoom != null && activeBoom!.oreName == oreName;

  @override
  void update(double dt) {
    super.update(dt);

    // Recover multipliers toward 1.0
    for (final key in _multipliers.keys.toList()) {
      final current = _multipliers[key]!;
      if (current < 1.0) {
        _multipliers[key] = min(1.0, current + _recoveryPerSecond * dt);
      } else if (current > 1.0 && !isBoomActive(key)) {
        _multipliers[key] = max(1.0, current - _recoveryPerSecond * dt);
      }
    }

    // Update active boom
    if (activeBoom != null) {
      activeBoom!.remainingSeconds -= dt;
      if (activeBoom!.remainingSeconds <= 0) {
        activeBoom = null;
      }
    }

    // Boom timer
    _nextBoomTimer -= dt;
    if (_nextBoomTimer <= 0) {
      _triggerBoom();
      _scheduleNextBoom();
    }
  }

  void _scheduleNextBoom() {
    _nextBoomTimer = _boomIntervalMin +
        _rng.nextDouble() * (_boomIntervalMax - _boomIntervalMin);
  }

  void _triggerBoom() {
    const ores = OreRegistry.standardOres;
    if (ores.isEmpty) return;
    final chosen = ores[_rng.nextInt(ores.length)];
    activeBoom = MarketBoom(
      oreName: chosen.name,
      multiplier: _boomMultiplier,
      remainingSeconds: _boomDurationSeconds,
    );
  }

  /// Serialize market state for saving.
  Map<String, dynamic> toMap() {
    return {
      'multipliers': Map<String, double>.from(_multipliers),
      'boomOreName': activeBoom?.oreName,
      'boomMultiplier': activeBoom?.multiplier,
      'boomRemaining': activeBoom?.remainingSeconds,
      'nextBoomTimer': _nextBoomTimer,
    };
  }

  /// Restore market state from save data.
  void loadFromMap(Map<String, dynamic> map) {
    _multipliers.clear();
    final saved = map['multipliers'] as Map<String, dynamic>?;
    if (saved != null) {
      for (final entry in saved.entries) {
        _multipliers[entry.key] = (entry.value as num).toDouble();
      }
    }
    final boomOre = map['boomOreName'] as String?;
    if (boomOre != null) {
      activeBoom = MarketBoom(
        oreName: boomOre,
        multiplier:
            (map['boomMultiplier'] as num?)?.toDouble() ?? _boomMultiplier,
        remainingSeconds: (map['boomRemaining'] as num?)?.toDouble() ?? 0,
      );
      if (activeBoom!.remainingSeconds <= 0) activeBoom = null;
    } else {
      activeBoom = null;
    }
    _nextBoomTimer = (map['nextBoomTimer'] as num?)?.toDouble() ?? 0;
    if (_nextBoomTimer <= 0) _scheduleNextBoom();
  }
}
