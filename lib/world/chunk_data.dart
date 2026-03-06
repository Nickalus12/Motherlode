import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Plain data result from chunk generation.
/// Contains serializable cell data that can cross isolate boundaries.
class ChunkData {
  /// Cell types as integer indices (CellType.index)
  final List<List<int>> cellTypes;

  /// Cell SDF values (negative=solid, positive=air)
  final List<List<double>> cellSdfValues;

  /// Ore type names (null if no ore)
  final List<List<String?>> oreNames;

  /// Creature spawn flags
  final List<List<bool>> creatureSpawns;

  final int chunkX;
  final int chunkY;
  final int seed;

  const ChunkData({
    required this.cellTypes,
    required this.cellSdfValues,
    required this.oreNames,
    required this.creatureSpawns,
    required this.chunkX,
    required this.chunkY,
    required this.seed,
  });

  /// Convert a grid of TerrainCells to ChunkData
  factory ChunkData.fromGrid(
    List<List<TerrainCell>> grid, {
    required int chunkX,
    required int chunkY,
    required int seed,
  }) {
    final size = grid.length;
    return ChunkData(
      cellTypes: List.generate(
        size,
        (y) => List.generate(size, (x) => grid[y][x].type.index),
      ),
      cellSdfValues: List.generate(
        size,
        (y) => List.generate(size, (x) => grid[y][x].sdf),
      ),
      oreNames: List.generate(
        size,
        (y) => List.generate(size, (x) => grid[y][x].oreType?.name),
      ),
      creatureSpawns: List.generate(
        size,
        (y) => List.generate(size, (x) => grid[y][x].hasCreatureSpawn),
      ),
      chunkX: chunkX,
      chunkY: chunkY,
      seed: seed,
    );
  }

  /// Convert back to a grid of TerrainCells
  List<List<TerrainCell>> toGrid() {
    final size = cellTypes.length;
    return List.generate(size, (y) {
      return List.generate(size, (x) {
        final oreName = oreNames[y][x];
        return TerrainCell(
          type: CellType.values[cellTypes[y][x]],
          sdf: cellSdfValues[y][x],
          oreType: oreName != null ? OreRegistry.getByName(oreName) : null,
          hasCreatureSpawn: creatureSpawns[y][x],
        );
      });
    });
  }
}
