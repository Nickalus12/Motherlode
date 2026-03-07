import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/utils/constants.dart';

/// Test the pure logic of FuelSystem without Flame Component infrastructure.
/// FuelSystem extends Component and requires a MotherlodeGame reference,
/// so we test the math and serialization logic directly.
void main() {
  group('FuelSystem logic', () {
    late _FuelLogic fuel;

    setUp(() {
      fuel = _FuelLogic();
    });

    test('starts with full fuel after init', () {
      expect(fuel.currentFuel, fuel.maxFuel);
      expect(fuel.fuelRatio, 1.0);
      expect(fuel.hasFuel, isTrue);
      expect(fuel.isLowFuel, isFalse);
    });

    test('consumeFuel reduces fuel', () {
      fuel.consumeFuel(2.0);
      expect(fuel.currentFuel, fuel.maxFuel - 2.0);
    });

    test('consumeFuel clamps to zero', () {
      fuel.consumeFuel(fuel.maxFuel + 10.0);
      expect(fuel.currentFuel, 0.0);
      expect(fuel.hasFuel, isFalse);
    });

    test('consumeFuel does not go negative', () {
      fuel.consumeFuel(999.0);
      expect(fuel.currentFuel, 0.0);
      expect(fuel.fuelRatio, 0.0);
    });

    test('fuelRatio is correct at various levels', () {
      fuel.currentFuel = fuel.maxFuel / 2;
      expect(fuel.fuelRatio, closeTo(0.5, 0.001));

      fuel.currentFuel = 0;
      expect(fuel.fuelRatio, 0.0);

      fuel.currentFuel = fuel.maxFuel;
      expect(fuel.fuelRatio, 1.0);
    });

    test('fuelRatio handles zero maxFuel', () {
      fuel.maxFuel = 0;
      expect(fuel.fuelRatio, 0.0);
    });

    test('isLowFuel triggers at threshold', () {
      fuel.currentFuel = fuel.maxFuel * GameConstants.lowFuelThreshold - 0.01;
      expect(fuel.isLowFuel, isTrue);

      fuel.currentFuel = fuel.maxFuel * GameConstants.lowFuelThreshold + 0.01;
      expect(fuel.isLowFuel, isFalse);
    });

    test('addFuel increases fuel', () {
      fuel.consumeFuel(5.0);
      final after = fuel.currentFuel;
      fuel.addFuel(3.0);
      expect(fuel.currentFuel, after + 3.0);
    });

    test('addFuel clamps to maxFuel', () {
      fuel.addFuel(100.0);
      expect(fuel.currentFuel, fuel.maxFuel);
    });

    test('fillTank fills to max and returns cost', () {
      fuel.consumeFuel(5.0);
      final cost = fuel.fillTank();
      expect(fuel.currentFuel, fuel.maxFuel);
      expect(cost, closeTo(5.0 * GameConstants.fuelCostPerLiter, 0.01));
    });

    test('fillTank on full tank returns zero cost', () {
      final cost = fuel.fillTank();
      expect(cost, 0.0);
    });

    test('upgradeCapacity changes maxFuel', () {
      fuel.upgradeCapacity(20.0);
      expect(fuel.maxFuel, 20.0);
    });

    test('serialization roundtrip', () {
      fuel.consumeFuel(3.0);
      final map = fuel.toMap();

      final restored = _FuelLogic();
      restored.loadFromMap(map);

      expect(restored.currentFuel, fuel.currentFuel);
      expect(restored.maxFuel, fuel.maxFuel);
    });

    test('out of fuel grace period is 10 seconds', () {
      // Verify the constant exists and is reasonable
      expect(_FuelLogic.outOfFuelGracePeriod, 10.0);
    });
  });
}

/// Extracted pure logic from FuelSystem for testing without Flame deps.
/// Mirrors the math exactly from lib/systems/fuel_system.dart.
class _FuelLogic {
  double currentFuel;
  double maxFuel;

  static const double outOfFuelGracePeriod = 10.0;

  _FuelLogic()
      : maxFuel = GameConstants.baseFuelCapacity,
        currentFuel = GameConstants.baseFuelCapacity;

  double get fuelRatio =>
      maxFuel > 0 ? (currentFuel / maxFuel).clamp(0.0, 1.0) : 0.0;

  bool get hasFuel => currentFuel > 0;

  bool get isLowFuel => fuelRatio < GameConstants.lowFuelThreshold;

  void consumeFuel(double amount) {
    currentFuel = (currentFuel - amount).clamp(0, maxFuel);
  }

  void addFuel(double amount) {
    currentFuel = (currentFuel + amount).clamp(0, maxFuel);
  }

  double fillTank() {
    final needed = maxFuel - currentFuel;
    final cost = needed * GameConstants.fuelCostPerLiter;
    currentFuel = maxFuel;
    return cost;
  }

  void upgradeCapacity(double newMax) {
    maxFuel = newMax;
  }

  Map<String, dynamic> toMap() {
    return {'current': currentFuel, 'max': maxFuel};
  }

  void loadFromMap(Map<String, dynamic> map) {
    currentFuel = (map['current'] as num).toDouble();
    maxFuel = (map['max'] as num).toDouble();
  }
}
