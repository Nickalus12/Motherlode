/// Creature spawn depth bands and stats
class CreatureSpawnInfo {
  final String name;
  final double minDepth; // ft
  final double maxDepth; // ft
  final double spawnChance; // 0.0 to 1.0, probability per valid spawn point
  final double health;
  final double damage;
  final double speed;
  final double cashDrop;

  const CreatureSpawnInfo({
    required this.name,
    required this.minDepth,
    required this.maxDepth,
    required this.spawnChance,
    required this.health,
    required this.damage,
    required this.speed,
    required this.cashDrop,
  });
}

/// Registry of creature spawn definitions
class CreatureDefinitions {
  CreatureDefinitions._();

  static const CreatureSpawnInfo caveWorm = CreatureSpawnInfo(
    name: 'Cave Worm',
    minDepth: 500,
    maxDepth: 1500,
    spawnChance: 0.3,
    health: 30,
    damage: 2,
    speed: 15,
    cashDrop: 200,
  );

  static const CreatureSpawnInfo rockCrab = CreatureSpawnInfo(
    name: 'Rock Crab',
    minDepth: 1500,
    maxDepth: 3000,
    spawnChance: 0.25,
    health: 50,
    damage: 5,
    speed: 20,
    cashDrop: 500,
  );

  static const CreatureSpawnInfo gasSpore = CreatureSpawnInfo(
    name: 'Gas Spore',
    minDepth: 2000,
    maxDepth: 4000,
    spawnChance: 0.35,
    health: 10,
    damage: 0, // Explosion damage
    speed: 3,
    cashDrop: 100,
  );

  static const CreatureSpawnInfo lavaEel = CreatureSpawnInfo(
    name: 'Lava Eel',
    minDepth: 3500,
    maxDepth: 5500,
    spawnChance: 0.20,
    health: 80,
    damage: 3,
    speed: 12,
    cashDrop: 1000,
  );

  static const CreatureSpawnInfo natasBoss = CreatureSpawnInfo(
    name: 'Mr. Natas',
    minDepth: 7187,
    maxDepth: 7187,
    spawnChance: 1.0, // Always spawns at boss depth
    health: 500,
    damage: 10,
    speed: 25,
    cashDrop: 100000,
  );

  static const List<CreatureSpawnInfo> allCreatures = [
    caveWorm,
    rockCrab,
    gasSpore,
    lavaEel,
    natasBoss,
  ];

  /// Get creature types that can spawn at a given depth
  static List<CreatureSpawnInfo> getCreaturesAtDepth(double depthFeet) {
    return allCreatures
        .where((c) => depthFeet >= c.minDepth && depthFeet <= c.maxDepth)
        .toList();
  }

  /// Select a creature type for spawning based on depth
  static CreatureSpawnInfo? selectCreatureForSpawn(double depthFeet) {
    final available = getCreaturesAtDepth(depthFeet);
    if (available.isEmpty) return null;

    // Weight by spawn chance
    double totalChance = 0;
    for (final c in available) {
      totalChance += c.spawnChance;
    }

    double roll = totalChance * (DateTime.now().microsecond / 1000000);
    for (final c in available) {
      roll -= c.spawnChance;
      if (roll <= 0) return c;
    }

    return available.last;
  }
}
