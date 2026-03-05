import 'dart:ui';

import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/world/terrain_cell.dart';

/// Depth-banded biome definitions
enum BiomeType {
  surface,
  topsoil,
  rock,
  volcanic,
  hell,
}

/// Biome definition with depth ranges, colors, and generation parameters
class Biome {
  final BiomeType type;
  final String name;
  final double minDepth; // in feet
  final double maxDepth; // in feet
  final Color primaryColor;
  final Color accentColor;
  final double ambientLight; // 0.0 to 1.0
  final double solidThreshold; // Noise threshold for solid cells
  final double caveFrequency; // How common caves are (0=none, 1=lots)
  final CellType primaryCellType;
  final bool hasLava;
  final bool hasGas;
  final double collapseResistance; // 0=always collapses, 1=never

  const Biome({
    required this.type,
    required this.name,
    required this.minDepth,
    required this.maxDepth,
    required this.primaryColor,
    required this.accentColor,
    required this.ambientLight,
    required this.solidThreshold,
    required this.caveFrequency,
    required this.primaryCellType,
    this.hasLava = false,
    this.hasGas = false,
    this.collapseResistance = 0.5,
  });

  /// Check if a depth falls within this biome
  bool containsDepth(double depthFeet) {
    return depthFeet >= minDepth && depthFeet < maxDepth;
  }
}

/// Registry of all biomes
class BiomeRegistry {
  BiomeRegistry._();

  static const Biome surface = Biome(
    type: BiomeType.surface,
    name: 'Surface',
    minDepth: 0,
    maxDepth: 50,
    primaryColor: Color(0xFF87CEEB), // sky blue
    accentColor: Color(0xFF90EE90),
    ambientLight: 1.0,
    solidThreshold: 0.52,
    caveFrequency: 0.0,
    primaryCellType: CellType.sand,
    collapseResistance: 0.0,
  );

  static const Biome topsoil = Biome(
    type: BiomeType.topsoil,
    name: 'Sandy Topsoil',
    minDepth: 0,
    maxDepth: GameConstants.topsoilEnd,
    primaryColor: GameConstants.surfaceTerrainColor,
    accentColor: GameConstants.surfaceAccentColor,
    ambientLight: GameConstants.surfaceAmbientLight,
    solidThreshold: 0.48, // Lower threshold = more solid, easier to traverse
    caveFrequency: 0.3,
    primaryCellType: CellType.dirt,
    collapseResistance: 0.2, // Low - easy collapse
  );

  static const Biome rock = Biome(
    type: BiomeType.rock,
    name: 'Dense Rock',
    minDepth: GameConstants.topsoilEnd,
    maxDepth: GameConstants.rockEnd,
    primaryColor: GameConstants.shallowTerrainColor,
    accentColor: GameConstants.shallowAccentColor,
    ambientLight: GameConstants.shallowAmbientLight,
    solidThreshold: 0.55, // Higher threshold = more solid, more ore veins
    caveFrequency: 0.4,
    primaryCellType: CellType.rock,
    hasGas: true,
    collapseResistance: 0.7,
  );

  static const Biome volcanic = Biome(
    type: BiomeType.volcanic,
    name: 'Volcanic Zone',
    minDepth: GameConstants.rockEnd,
    maxDepth: GameConstants.volcanicEnd,
    primaryColor: GameConstants.volcanicTerrainColor,
    accentColor: GameConstants.volcanicAccentColor,
    ambientLight: GameConstants.volcanicAmbientLight,
    solidThreshold: 0.52,
    caveFrequency: 0.5,
    primaryCellType: CellType.rock,
    hasLava: true,
    hasGas: true,
    collapseResistance: 0.6,
  );

  static const Biome hell = Biome(
    type: BiomeType.hell,
    name: 'Hell',
    minDepth: GameConstants.hellStart,
    maxDepth: GameConstants.maxDepth + 500,
    primaryColor: GameConstants.hellTerrainColor,
    accentColor: GameConstants.hellAccentColor,
    ambientLight: GameConstants.hellAmbientLight,
    solidThreshold: 0.50,
    caveFrequency: 0.6,
    primaryCellType: CellType.obsidian,
    hasLava: true,
    collapseResistance: 0.9,
  );

  static const List<Biome> allBiomes = [
    topsoil,
    rock,
    volcanic,
    hell,
  ];

  /// Get the biome for a given depth in feet
  static Biome getBiomeAtDepth(double depthFeet) {
    if (depthFeet < 0) return surface;
    for (final biome in allBiomes) {
      if (biome.containsDepth(depthFeet)) return biome;
    }
    return hell; // Default to hell for extreme depths
  }

  /// Get biome name as display string
  static String getBiomeName(double depthFeet) {
    return getBiomeAtDepth(depthFeet).name;
  }
}
