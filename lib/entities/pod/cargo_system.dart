import 'package:motherlode/world/ore_registry.dart';

/// Cargo inventory and weight tracking system
class CargoSystem {
  double maxCapacity; // kg
  double _currentWeight = 0;

  // Inventory: ore name → count
  final Map<String, int> _inventory = {};

  CargoSystem({required this.maxCapacity});

  /// Current total cargo weight in kg
  double get currentWeight => _currentWeight;

  /// Remaining capacity in kg
  double get remainingCapacity => maxCapacity - _currentWeight;

  /// Whether cargo is full
  bool get isFull => _currentWeight >= maxCapacity;

  /// Current fill ratio (0.0 to 1.0)
  double get fillRatio =>
      (maxCapacity > 0) ? (_currentWeight / maxCapacity).clamp(0.0, 1.0) : 0.0;

  /// Check if an ore of given weight can be added
  bool canAdd(double weight) {
    return _currentWeight + weight <= maxCapacity;
  }

  /// Add an ore to cargo
  void addOre(OreType ore) {
    _currentWeight += ore.weight;
    _inventory[ore.name] = (_inventory[ore.name] ?? 0) + 1;
  }

  /// Get count of a specific ore type in cargo
  int getOreCount(String oreName) {
    return _inventory[oreName] ?? 0;
  }

  /// Get all ores in inventory with their counts
  Map<String, int> get inventory => Map.unmodifiable(_inventory);

  /// Calculate total value of all cargo
  double get totalValue {
    double total = 0;
    for (final entry in _inventory.entries) {
      final ore = OreRegistry.getByName(entry.key);
      if (ore != null) {
        total += ore.value * entry.value;
      }
    }
    return total;
  }

  /// Sell all cargo, returns total value
  double sellAll() {
    final value = totalValue;
    _inventory.clear();
    _currentWeight = 0;
    return value;
  }

  /// Sell all units of a specific ore type, returns sale value.
  double sellOre(String oreName) {
    final count = _inventory[oreName];
    if (count == null || count <= 0) return 0;

    final ore = OreRegistry.getByName(oreName);
    if (ore == null) return 0;

    final value = ore.value.toDouble() * count;
    _currentWeight -= ore.weight * count;
    if (_currentWeight < 0) _currentWeight = 0;
    _inventory.remove(oreName);
    return value;
  }

  /// Get a detailed breakdown of cargo for display
  List<CargoItem> getCargoBreakdown() {
    final items = <CargoItem>[];
    for (final entry in _inventory.entries) {
      final ore = OreRegistry.getByName(entry.key);
      if (ore != null) {
        items.add(CargoItem(
          ore: ore,
          count: entry.value,
          totalWeight: ore.weight.toDouble() * entry.value,
          totalValue: ore.value.toDouble() * entry.value,
        ));
      }
    }
    // Sort by total value descending
    items.sort((a, b) => b.totalValue.compareTo(a.totalValue));
    return items;
  }

  /// Clear all cargo
  void clear() {
    _inventory.clear();
    _currentWeight = 0;
  }

  /// Serialize for save system
  Map<String, dynamic> toMap() {
    return {
      'maxCapacity': maxCapacity,
      'inventory': Map<String, int>.from(_inventory),
    };
  }

  /// Restore from save data (handles missing/null keys gracefully)
  void loadFromMap(Map<String, dynamic> map) {
    maxCapacity = (map['maxCapacity'] as num?)?.toDouble() ?? maxCapacity;
    _inventory.clear();
    final saved = map['inventory'] as Map<String, dynamic>?;
    if (saved != null) {
      for (final entry in saved.entries) {
        final count = entry.value;
        if (count is int) {
          _inventory[entry.key] = count;
        } else if (count is num) {
          _inventory[entry.key] = count.toInt();
        }
      }
    }
    // Recalculate weight
    _currentWeight = 0;
    for (final entry in _inventory.entries) {
      final ore = OreRegistry.getByName(entry.key);
      if (ore != null) {
        _currentWeight += ore.weight * entry.value;
      }
    }
  }
}

/// Represents a cargo line item for display
class CargoItem {
  final OreType ore;
  final int count;
  final double totalWeight;
  final double totalValue;

  const CargoItem({
    required this.ore,
    required this.count,
    required this.totalWeight,
    required this.totalValue,
  });
}
