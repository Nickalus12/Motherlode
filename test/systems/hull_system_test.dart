import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/utils/constants.dart';

/// Test the pure logic of HullSystem without Flame Component infrastructure.
/// HullSystem extends Component and requires MotherlodeGame, so we extract
/// and test the math directly.
void main() {
  group('HullSystem logic', () {
    late _HullLogic hull;

    setUp(() {
      hull = _HullLogic();
    });

    test('starts with full hull', () {
      expect(hull.currentHull, hull.maxHull);
      expect(hull.hullRatio, 1.0);
      expect(hull.isDestroyed, isFalse);
      expect(hull.isLowHull, isFalse);
    });

    test('takeDamage reduces hull', () {
      hull.takeDamage(10.0);
      expect(hull.currentHull, hull.maxHull - 10.0);
    });

    test('takeDamage clamps to zero', () {
      hull.takeDamage(hull.maxHull + 50.0);
      expect(hull.currentHull, 0.0);
      expect(hull.isDestroyed, isTrue);
    });

    test('hullRatio is correct at various levels', () {
      hull.currentHull = hull.maxHull / 2;
      expect(hull.hullRatio, closeTo(0.5, 0.001));

      hull.currentHull = 0;
      expect(hull.hullRatio, 0.0);
    });

    test('hullRatio handles zero maxHull', () {
      hull.maxHull = 0;
      expect(hull.hullRatio, 0.0);
    });

    test('isLowHull triggers at threshold', () {
      hull.currentHull = hull.maxHull * GameConstants.lowHullThreshold - 0.01;
      expect(hull.isLowHull, isTrue);

      hull.currentHull = hull.maxHull * GameConstants.lowHullThreshold + 0.01;
      expect(hull.isLowHull, isFalse);
    });

    test('takeHeatDamage applies heat resistance', () {
      hull.heatResistance = 0.5;
      hull.takeHeatDamage(20.0);
      // Should take only half damage
      expect(hull.currentHull, closeTo(hull.maxHull - 10.0, 0.01));
    });

    test('full heat resistance blocks all heat damage', () {
      hull.heatResistance = 1.0;
      hull.takeHeatDamage(100.0);
      expect(hull.currentHull, hull.maxHull);
    });

    test('zero heat resistance takes full damage', () {
      hull.heatResistance = 0.0;
      hull.takeHeatDamage(10.0);
      expect(hull.currentHull, hull.maxHull - 10.0);
    });

    test('takeFallDamage below threshold does nothing', () {
      hull.takeFallDamage(5.0); // Below 8.0 threshold
      expect(hull.currentHull, hull.maxHull);
    });

    test('takeFallDamage above threshold applies damage', () {
      hull.takeFallDamage(12.0); // 4 m/s above threshold -> 8 damage
      expect(hull.currentHull, closeTo(hull.maxHull - 8.0, 0.01));
    });

    test('takeFallDamage uses absolute velocity', () {
      hull.takeFallDamage(-12.0); // Negative velocity (upward impact)
      expect(hull.currentHull, closeTo(hull.maxHull - 8.0, 0.01));
    });

    test('takeFallDamage at exactly threshold does nothing', () {
      hull.takeFallDamage(8.0);
      expect(hull.currentHull, hull.maxHull);
    });

    test('repair increases hull', () {
      hull.takeDamage(20.0);
      hull.repair(10.0);
      expect(hull.currentHull, hull.maxHull - 10.0);
    });

    test('repair clamps to maxHull', () {
      hull.takeDamage(5.0);
      hull.repair(100.0);
      expect(hull.currentHull, hull.maxHull);
    });

    test('fullRepair restores to max and returns needed amount', () {
      hull.takeDamage(15.0);
      final needed = hull.fullRepair();
      expect(needed, closeTo(15.0, 0.01));
      expect(hull.currentHull, hull.maxHull);
    });

    test('fullRepair on full hull returns zero', () {
      final needed = hull.fullRepair();
      expect(needed, 0.0);
    });

    test('upgradeHull maintains health ratio', () {
      hull.takeDamage(hull.maxHull / 2); // 50% health
      hull.upgradeHull(100.0);
      expect(hull.maxHull, 100.0);
      expect(hull.currentHull, closeTo(50.0, 0.01)); // Still 50%
    });

    test('upgradeHull at full health fills to new max', () {
      hull.upgradeHull(100.0);
      expect(hull.currentHull, closeTo(100.0, 0.01));
    });

    test('recentDamage tracks timing', () {
      expect(hull.recentDamage, isFalse);
      hull.takeDamage(1.0);
      expect(hull.recentDamage, isTrue);
      // Simulate time passing
      hull.advanceTime(0.6);
      expect(hull.recentDamage, isFalse);
    });

    test('serialization roundtrip', () {
      hull.takeDamage(10.0);
      hull.heatResistance = 0.75;
      final map = hull.toMap();

      final restored = _HullLogic();
      restored.loadFromMap(map);

      expect(restored.currentHull, hull.currentHull);
      expect(restored.maxHull, hull.maxHull);
      expect(restored.heatResistance, hull.heatResistance);
    });

    test('serialization handles missing optional fields', () {
      final map = {
        'current': 30.0,
        'max': 50.0,
      };
      final restored = _HullLogic();
      restored.loadFromMap(map);
      expect(restored.heatResistance, 0.0);
    });
  });
}

/// Extracted pure logic from HullSystem for testing without Flame deps.
class _HullLogic {
  double currentHull;
  double maxHull;
  double heatResistance = 0.0;
  double _lastDamageTime = 1.0; // Start > 0.5 so recentDamage is false
  double _totalDamageTaken = 0.0;

  _HullLogic()
      : maxHull = GameConstants.baseHullHP,
        currentHull = GameConstants.baseHullHP;

  double get hullRatio =>
      maxHull > 0 ? (currentHull / maxHull).clamp(0.0, 1.0) : 0.0;

  bool get isLowHull => hullRatio < GameConstants.lowHullThreshold;
  bool get recentDamage => _lastDamageTime < 0.5;
  bool get isDestroyed => currentHull <= 0;

  void takeDamage(double amount) {
    currentHull = (currentHull - amount).clamp(0, maxHull);
    _lastDamageTime = 0;
    _totalDamageTaken += amount;
  }

  void takeHeatDamage(double amount) {
    final reducedAmount = amount * (1.0 - heatResistance);
    if (reducedAmount > 0) {
      takeDamage(reducedAmount);
    }
  }

  void takeFallDamage(double impactVelocity) {
    const threshold = 8.0;
    if (impactVelocity.abs() > threshold) {
      final damage = (impactVelocity.abs() - threshold) * 2;
      takeDamage(damage);
    }
  }

  void repair(double amount) {
    currentHull = (currentHull + amount).clamp(0, maxHull);
  }

  double fullRepair() {
    final needed = maxHull - currentHull;
    currentHull = maxHull;
    return needed;
  }

  void upgradeHull(double newMax) {
    final wasRatio = hullRatio;
    maxHull = newMax;
    currentHull = maxHull * wasRatio;
  }

  void advanceTime(double dt) {
    _lastDamageTime += dt;
  }

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
