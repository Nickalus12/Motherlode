import 'dart:ui';

import 'package:motherlode/data/ore_types.dart';

/// Types of terrain cells in the world grid
enum CellType {
  empty,
  dirt,
  rock,
  sand,
  obsidian,
  lava,
  gas,
  ore,
  bedrock, // Indestructible boundary
}

/// Individual terrain cell with type, density, and optional ore data
class TerrainCell {
  CellType type;
  double density; // 0.0 = fully empty, 1.0 = fully solid
  OreType? oreType; // Non-null only if type == CellType.ore
  bool isDirty; // Needs visual rebuild
  bool hasCreatureSpawn; // Creature should spawn here

  TerrainCell({
    this.type = CellType.empty,
    this.density = 0.0,
    this.oreType,
    this.isDirty = true,
    this.hasCreatureSpawn = false,
  });

  /// Whether this cell blocks movement
  bool get isSolid =>
      type != CellType.empty && type != CellType.lava && type != CellType.gas;

  /// Whether this cell can be drilled
  bool get isDrillable =>
      type == CellType.dirt ||
      type == CellType.rock ||
      type == CellType.sand ||
      type == CellType.obsidian ||
      type == CellType.ore;

  /// Whether this cell is a hazard
  bool get isHazard => type == CellType.lava || type == CellType.gas;

  /// Get the hardness multiplier for drilling resistance
  double get hardness {
    switch (type) {
      case CellType.sand:
        return 0.5;
      case CellType.dirt:
        return 1.0;
      case CellType.rock:
        return 2.0;
      case CellType.obsidian:
        return 4.0;
      case CellType.ore:
        return oreType?.hardness ?? 1.0;
      case CellType.bedrock:
        return double.infinity;
      default:
        return 0.0;
    }
  }

  /// Get the base color for this cell type
  Color get baseColor {
    switch (type) {
      case CellType.sand:
        return const Color(0xFFD4A96A);
      case CellType.dirt:
        return const Color(0xFF8B6914);
      case CellType.rock:
        return const Color(0xFF5A5A5A);
      case CellType.obsidian:
        return const Color(0xFF1A1A2E);
      case CellType.lava:
        return const Color(0xFFFF4500);
      case CellType.gas:
        return const Color(0xFF00FF4420);
      case CellType.ore:
        return oreType?.color ?? const Color(0xFFFFD700);
      case CellType.bedrock:
        return const Color(0xFF111111);
      case CellType.empty:
        return const Color(0x00000000);
    }
  }

  /// Whether sand/gravel always collapses (no support check needed)
  bool get alwaysCollapses => type == CellType.sand;

  /// Create a copy of this cell
  TerrainCell copy() {
    return TerrainCell(
      type: type,
      density: density,
      oreType: oreType,
      isDirty: isDirty,
      hasCreatureSpawn: hasCreatureSpawn,
    );
  }

  /// Convert to serializable map
  Map<String, dynamic> toMap() {
    return {
      'type': type.index,
      'density': density,
      'oreId': oreType?.name,
      'hasCreature': hasCreatureSpawn,
    };
  }

  /// Restore from serialized map
  factory TerrainCell.fromMap(Map<String, dynamic> map) {
    return TerrainCell(
      type: CellType.values[map['type'] as int],
      density: (map['density'] as num).toDouble(),
      oreType: map['oreId'] != null
          ? OreRegistry.getByName(map['oreId'] as String)
          : null,
      hasCreatureSpawn: map['hasCreature'] as bool? ?? false,
    );
  }
}
