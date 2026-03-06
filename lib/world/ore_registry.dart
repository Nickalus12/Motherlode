import 'dart:ui';

/// Definition of an ore type with all gameplay-relevant properties
class OreType {
  final String name;
  final int value; // $ when sold
  final int weight; // kg, affects pod physics
  final int minDepth; // ft to start spawning
  final Color color; // Rendered fill color
  final Color glowColor; // Subtle radial glow in darkness
  final double hardness; // Drill resistance multiplier
  final double spawnRarity; // 0.0 (common) to 1.0 (very rare)
  final bool isSpecialCollectible; // Immediate cash, no cargo space
  final String? spritePath; // Path to 4x4 sprite sheet in assets/images/

  const OreType({
    required this.name,
    required this.value,
    required this.weight,
    required this.minDepth,
    required this.color,
    required this.glowColor,
    required this.hardness,
    required this.spawnRarity,
    this.isSpecialCollectible = false,
    this.spritePath,
  });
}

/// Complete ore registry matching original Motherload + new additions
class OreRegistry {
  OreRegistry._();

  // ─── Standard Ores ───

  static const OreType ironium = OreType(
    name: 'Ironium',
    value: 30,
    weight: 10,
    minDepth: 0,
    color: Color(0xFF8B4513),
    glowColor: Color(0x408B4513),
    hardness: 1.0,
    spawnRarity: 0.05,
    spritePath: 'items/ores/iron_ore.png',
  );

  static const OreType bronzium = OreType(
    name: 'Bronzium',
    value: 60,
    weight: 10,
    minDepth: 0,
    color: Color(0xFFCD7F32),
    glowColor: Color(0x40CD7F32),
    hardness: 1.1,
    spawnRarity: 0.08,
  );

  static const OreType silverium = OreType(
    name: 'Silverium',
    value: 100,
    weight: 10,
    minDepth: 0,
    color: Color(0xFFC0C0C0),
    glowColor: Color(0x40C0C0C0),
    hardness: 1.2,
    spawnRarity: 0.12,
    spritePath: 'items/ores/silver_ore.png',
  );

  static const OreType goldium = OreType(
    name: 'Goldium',
    value: 250,
    weight: 20,
    minDepth: 0,
    color: Color(0xFFFFD700),
    glowColor: Color(0x60FFD700),
    hardness: 1.3,
    spawnRarity: 0.18,
    spritePath: 'items/ores/gold_ore.png',
  );

  static const OreType platinium = OreType(
    name: 'Platinium',
    value: 750,
    weight: 30,
    minDepth: 750,
    color: Color(0xFFE8E8FF),
    glowColor: Color(0x40E8E8FF),
    hardness: 1.5,
    spawnRarity: 0.25,
    spritePath: 'items/ores/platinum_ore.png',
  );

  static const OreType einsteinium = OreType(
    name: 'Einsteinium',
    value: 2000,
    weight: 40,
    minDepth: 1562,
    color: Color(0xFF7FFFD4),
    glowColor: Color(0x607FFFD4),
    hardness: 2.0,
    spawnRarity: 0.35,
    spritePath: 'items/ores/einsteinium_ore.png',
  );

  static const OreType emerald = OreType(
    name: 'Emerald',
    value: 5000,
    weight: 60,
    minDepth: 2375,
    color: Color(0xFF50C878),
    glowColor: Color(0x6050C878),
    hardness: 2.5,
    spawnRarity: 0.45,
    spritePath: 'items/gems/emerald.png',
  );

  static const OreType ruby = OreType(
    name: 'Ruby',
    value: 20000,
    weight: 80,
    minDepth: 3187,
    color: Color(0xFFFF0000),
    glowColor: Color(0x60FF0000),
    hardness: 3.0,
    spawnRarity: 0.55,
    spritePath: 'items/gems/ruby.png',
  );

  static const OreType diamond = OreType(
    name: 'Diamond',
    value: 100000,
    weight: 100,
    minDepth: 4000,
    color: Color(0xFFB9F2FF),
    glowColor: Color(0x80B9F2FF),
    hardness: 4.0,
    spawnRarity: 0.65,
  );

  static const OreType amazonite = OreType(
    name: 'Amazonite',
    value: 500000,
    weight: 120,
    minDepth: 4812,
    color: Color(0xFF00CED1),
    glowColor: Color(0x8000CED1),
    hardness: 5.0,
    spawnRarity: 0.75,
    spritePath: 'items/gems/amazonite.png',
  );

  // ─── New Ores ───

  static const OreType hellstone = OreType(
    name: 'Hellstone',
    value: 1000000,
    weight: 150,
    minDepth: 6000,
    color: Color(0xFFFF4500),
    glowColor: Color(0x80FF4500),
    hardness: 6.0,
    spawnRarity: 0.85,
    spritePath: 'items/rare/hellstone.png',
  );

  static const OreType soulCrystal = OreType(
    name: 'Soul Crystal',
    value: 5000000,
    weight: 200,
    minDepth: 7000,
    color: Color(0xFF8A2BE2),
    glowColor: Color(0xA08A2BE2),
    hardness: 8.0,
    spawnRarity: 0.95,
    spritePath: 'items/gems/soul_crystal.png',
  );

  // ─── Special Collectibles ───

  static const OreType dinosaurBones = OreType(
    name: 'Dinosaur Bones',
    value: 1000,
    weight: 0,
    minDepth: 950,
    color: Color(0xFFDEB887),
    glowColor: Color(0x40DEB887),
    hardness: 1.0,
    spawnRarity: 0.80,
    isSpecialCollectible: true,
    spritePath: 'items/rare/dinosaur_bone.png',
  );

  static const OreType treasureChest = OreType(
    name: 'Treasure Chest',
    value: 5000,
    weight: 0,
    minDepth: 950,
    color: Color(0xFFDAA520),
    glowColor: Color(0x60DAA520),
    hardness: 1.0,
    spawnRarity: 0.85,
    isSpecialCollectible: true,
  );

  static const OreType martianSkeleton = OreType(
    name: 'Martian Skeleton',
    value: 10000,
    weight: 0,
    minDepth: 950,
    color: Color(0xFF90EE90),
    glowColor: Color(0x6090EE90),
    hardness: 1.0,
    spawnRarity: 0.90,
    isSpecialCollectible: true,
  );

  static const OreType religiousSymbol = OreType(
    name: 'Religious Symbol',
    value: 50000,
    weight: 0,
    minDepth: 950,
    color: Color(0xFFFFFF00),
    glowColor: Color(0x80FFFF00),
    hardness: 1.0,
    spawnRarity: 0.95,
    isSpecialCollectible: true,
  );

  static const OreType ancientScroll = OreType(
    name: 'Ancient Scroll',
    value: 0, // Unlocks max-tier upgrade instead
    weight: 0,
    minDepth: 3700,
    color: Color(0xFFFFF8DC),
    glowColor: Color(0x80FFF8DC),
    hardness: 1.0,
    spawnRarity: 0.99,
    isSpecialCollectible: true,
    spritePath: 'items/rare/ancient_scroll.png',
  );

  /// All standard (mineable, takes cargo space) ores sorted by depth
  static const List<OreType> standardOres = [
    ironium,
    bronzium,
    silverium,
    goldium,
    platinium,
    einsteinium,
    emerald,
    ruby,
    diamond,
    amazonite,
    hellstone,
    soulCrystal,
  ];

  /// All special collectibles
  static const List<OreType> specialCollectibles = [
    dinosaurBones,
    treasureChest,
    martianSkeleton,
    religiousSymbol,
    ancientScroll,
  ];

  /// All ore types combined
  static const List<OreType> allOres = [
    ...standardOres,
    ...specialCollectibles,
  ];

  /// Get an ore type by name
  static OreType? getByName(String name) {
    for (final ore in allOres) {
      if (ore.name == name) return ore;
    }
    return null;
  }

  /// Get ores that can spawn at a given depth
  static List<OreType> getOresAtDepth(double depthFeet) {
    return allOres.where((ore) => depthFeet >= ore.minDepth).toList();
  }

  /// Select an ore type for spawning based on depth and rarity
  /// Returns null if no ore should spawn at this location
  static OreType? selectOreForSpawn(double depthFeet, double noiseValue) {
    final available = getOresAtDepth(depthFeet);
    if (available.isEmpty) return null;

    // Higher noise value = rarer ore selected
    // Sort by spawn rarity ascending, find the one matching our noise threshold
    final sorted = List<OreType>.from(available)
      ..sort((a, b) => a.spawnRarity.compareTo(b.spawnRarity));

    for (final ore in sorted.reversed) {
      if (noiseValue >= ore.spawnRarity) {
        return ore;
      }
    }

    // Default to most common ore at this depth
    return sorted.first;
  }
}
