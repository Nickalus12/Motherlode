/// Definition of a consumable item
class ConsumableItem {
  final String name;
  final String description;
  final int cost;
  final String hotkey;
  final String icon;

  const ConsumableItem({
    required this.name,
    required this.description,
    required this.cost,
    required this.hotkey,
    required this.icon,
  });
}

/// Registry of all consumable/special items
class SpecialItems {
  SpecialItems._();

  static const ConsumableItem reserveFuelTank = ConsumableItem(
    name: 'Reserve Fuel Tank',
    description: 'Instantly adds 25L of fuel.',
    cost: 2000,
    hotkey: 'F',
    icon: '⛽',
  );

  static const ConsumableItem hullRepairNanobots = ConsumableItem(
    name: 'Hull Repair Nanobots',
    description: 'Instantly repairs 30 HP of hull damage.',
    cost: 7500,
    hotkey: 'R',
    icon: '🔧',
  );

  static const ConsumableItem dynamite = ConsumableItem(
    name: 'Dynamite',
    description: '3x3 blast radius. Destroys terrain and damages creatures.',
    cost: 2000,
    hotkey: 'X',
    icon: '💣',
  );

  static const ConsumableItem plasticExplosive = ConsumableItem(
    name: 'Plastic Explosive',
    description: '5x5 blast radius. Massive terrain destruction.',
    cost: 5000,
    hotkey: 'C',
    icon: '💥',
  );

  static const ConsumableItem quantumTeleporter = ConsumableItem(
    name: 'Quantum Teleporter',
    description: 'Teleports to a random surface location. Emergency use.',
    cost: 2000,
    hotkey: 'Q',
    icon: '⚡',
  );

  static const ConsumableItem matterTransmitter = ConsumableItem(
    name: 'Matter Transmitter',
    description: 'Safely teleports to the surface landing pad.',
    cost: 10000,
    hotkey: 'M',
    icon: '🌟',
  );

  static const List<ConsumableItem> allConsumables = [
    reserveFuelTank,
    hullRepairNanobots,
    dynamite,
    plasticExplosive,
    quantumTeleporter,
    matterTransmitter,
  ];

  /// Get a consumable by name
  static ConsumableItem? getByName(String name) {
    for (final item in allConsumables) {
      if (item.name == name) return item;
    }
    return null;
  }
}
