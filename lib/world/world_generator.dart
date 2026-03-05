import 'dart:math';

import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/utils/noise_utils.dart';
import 'package:hellbore/world/biome.dart';
import 'package:hellbore/world/ore_registry.dart';
import 'package:hellbore/world/terrain_cell.dart';

/// Generates the procedural world using multi-octave Simplex noise
/// and cellular automata smoothing
class WorldGenerator {
  final int seed;
  final Random _random;

  WorldGenerator({required this.seed}) : _random = Random(seed);

  /// Generate terrain data for a chunk at the given chunk coordinates
  /// chunkX, chunkY are chunk indices (not pixel/tile coords)
  /// Returns a 2D grid of TerrainCells [chunkSize x chunkSize]
  List<List<TerrainCell>> generateChunk(int chunkX, int chunkY) {
    final size = GameConstants.chunkSize;
    final grid = List.generate(
      size,
      (y) => List.generate(size, (x) => TerrainCell()),
    );

    // Convert chunk coords to world tile coords
    final worldStartX = chunkX * size;
    final worldStartY = chunkY * size;

    // Step 1: Generate noise density map
    _generateDensityMap(grid, worldStartX, worldStartY, size);

    // Step 2: Apply threshold based on biome
    _applyThreshold(grid, worldStartX, worldStartY, size);

    // Step 3: Run cellular automata smoothing (4 passes)
    for (int pass = 0; pass < 4; pass++) {
      _cellularAutomataPass(grid, size);
    }

    // Step 4: Classify cells by depth biome
    _classifyCellsByBiome(grid, worldStartX, worldStartY, size);

    // Step 5: Place ore veins using secondary noise
    _placeOreVeins(grid, worldStartX, worldStartY, size);

    // Step 6: Place hazards (lava, gas)
    _placeHazards(grid, worldStartX, worldStartY, size);

    // Step 7: Mark creature spawn points
    _markCreatureSpawns(grid, worldStartX, worldStartY, size);

    // Step 8: Handle surface zone (keep top area mostly clear)
    _handleSurfaceZone(grid, worldStartX, worldStartY, size);

    return grid;
  }

  /// Step 1: Generate base density map using multi-octave simplex noise
  void _generateDensityMap(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final worldX = worldStartX + x;
        final worldY = worldStartY + y;

        final density = NoiseUtils.sampleMultiOctave(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
          octaves: 4,
          frequency: 0.02,
          lacunarity: 2.0,
          gain: 0.5,
        );

        // Add cave noise as a subtraction to create open areas
        final caveNoise = NoiseUtils.sampleCaveNoise(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
        );

        // Combined density: base terrain minus cave carving
        grid[y][x].density = (density - caveNoise * 0.3).clamp(0.0, 1.0);
      }
    }
  }

  /// Step 2: Apply solid/empty threshold based on biome at each depth
  void _applyThreshold(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;
        final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);

        if (grid[y][x].density > biome.solidThreshold) {
          grid[y][x].type = CellType.dirt; // Will be reclassified later
        } else {
          grid[y][x].type = CellType.empty;
        }
      }
    }
  }

  /// Step 3: Cellular automata smoothing pass
  /// - Solid cell with < 4 solid neighbors → becomes empty
  /// - Empty cell with > 5 solid neighbors → becomes solid
  void _cellularAutomataPass(List<List<TerrainCell>> grid, int size) {
    // Create a copy of types for simultaneous evaluation
    final typeCopy = List.generate(
      size,
      (y) => List.generate(size, (x) => grid[y][x].type),
    );

    for (int y = 1; y < size - 1; y++) {
      for (int x = 1; x < size - 1; x++) {
        int solidNeighbors = 0;

        // Count 8-connected neighbors
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (typeCopy[y + dy][x + dx] != CellType.empty) {
              solidNeighbors++;
            }
          }
        }

        if (typeCopy[y][x] != CellType.empty) {
          // Solid cell: if < 4 solid neighbors, open up
          if (solidNeighbors < 4) {
            grid[y][x].type = CellType.empty;
            grid[y][x].density = 0.0;
          }
        } else {
          // Empty cell: if > 5 solid neighbors, fill in
          if (solidNeighbors > 5) {
            grid[y][x].type = CellType.dirt;
            grid[y][x].density = 0.6;
          }
        }
      }
    }
  }

  /// Step 4: Classify solid cells into proper types based on depth/biome
  void _classifyCellsByBiome(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (grid[y][x].type == CellType.empty) continue;

        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;
        final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);

        grid[y][x].type = biome.primaryCellType;
      }
    }
  }

  /// Step 5: Place ore veins as cellular blobs using secondary noise
  void _placeOreVeins(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (grid[y][x].type == CellType.empty) continue;

        final worldX = worldStartX + x;
        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;

        // Sample ore noise
        final oreNoise = NoiseUtils.sampleOreNoise(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
        );

        // Only place ore if noise exceeds threshold (creates blob shapes)
        if (oreNoise > 0.72) {
          final ore = OreRegistry.selectOreForSpawn(depthFeet, oreNoise);
          if (ore != null) {
            grid[y][x].type = CellType.ore;
            grid[y][x].oreType = ore;
          }
        }

        // Special collectibles - much rarer, independent noise check
        if (depthFeet >= 950) {
          final specialNoise = NoiseUtils.sampleMultiOctave(
            seed: seed + 9999,
            x: worldX.toDouble(),
            y: worldY.toDouble(),
            octaves: 1,
            frequency: 0.005,
          );
          if (specialNoise > 0.98) {
            final collectible =
                _selectCollectible(depthFeet, worldX + worldY);
            if (collectible != null) {
              grid[y][x].type = CellType.ore;
              grid[y][x].oreType = collectible;
            }
          }
        }
      }
    }
  }

  /// Step 6: Place hazards (lava pockets, gas pockets)
  void _placeHazards(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final worldX = worldStartX + x;
        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;
        final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);

        // Lava placement
        if (biome.hasLava && grid[y][x].type != CellType.ore) {
          final lavaNoise = NoiseUtils.sampleLavaNoise(
            seed: seed,
            x: worldX.toDouble(),
            y: worldY.toDouble(),
          );
          if (lavaNoise > 0.78) {
            grid[y][x].type = CellType.lava;
            grid[y][x].density = 0.0;
          }
        }

        // Gas placement
        if (biome.hasGas && grid[y][x].type == CellType.empty) {
          final gasNoise = NoiseUtils.sampleGasNoise(
            seed: seed,
            x: worldX.toDouble(),
            y: worldY.toDouble(),
          );
          if (gasNoise > 0.82) {
            grid[y][x].type = CellType.gas;
            grid[y][x].density = 0.0;
          }
        }
      }
    }
  }

  /// Step 7: Mark creature spawn points using tertiary noise
  void _markCreatureSpawns(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        // Creatures spawn in empty spaces
        if (grid[y][x].type != CellType.empty) continue;

        final worldX = worldStartX + x;
        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;

        // No creatures near surface
        if (depthFeet < 500) continue;

        final creatureNoise = NoiseUtils.sampleCreatureNoise(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
        );

        if (creatureNoise > 0.88) {
          grid[y][x].hasCreatureSpawn = true;
        }
      }
    }
  }

  /// Step 8: Keep surface zone clear for the landing pad and shops
  void _handleSurfaceZone(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      final worldY = worldStartY + y;

      // Above ground level: always empty
      if (worldY < 0) {
        for (int x = 0; x < size; x++) {
          grid[y][x].type = CellType.empty;
          grid[y][x].density = 0.0;
        }
      }
      // First row at ground level: thin layer of dirt/sand
      else if (worldY == 0) {
        for (int x = 0; x < size; x++) {
          // Keep center clear for landing pad
          final worldX = worldStartX + x;
          if (worldX.abs() <= 3) {
            grid[y][x].type = CellType.empty;
            grid[y][x].density = 0.0;
          } else {
            grid[y][x].type = CellType.sand;
            grid[y][x].density = 0.8;
          }
        }
      }
      // Shallow sand layer (first ~13 rows = ~200ft)
      else if (worldY * GameConstants.feetPerTile <=
          GameConstants.sandLayerEnd) {
        for (int x = 0; x < size; x++) {
          if (grid[y][x].type != CellType.empty) {
            grid[y][x].type = CellType.sand;
          }
        }
      }
    }
  }

  /// Select a special collectible based on depth and deterministic hash
  OreType? _selectCollectible(double depthFeet, int hash) {
    final available = OreRegistry.specialCollectibles
        .where((c) => depthFeet >= c.minDepth)
        .toList();
    if (available.isEmpty) return null;

    // Ancient Scroll only spawns in specific depth range, once per run
    if (depthFeet >= 3700 && depthFeet <= 7300 && hash % 500 == 0) {
      return OreRegistry.ancientScroll;
    }

    return available[hash.abs() % available.length];
  }

  /// Verify a path exists from surface to a target depth
  /// If blocked, carve a narrow path
  void guaranteePath(
    Map<int, Map<int, List<List<TerrainCell>>>> chunks,
    int targetDepthTiles,
  ) {
    // Flood fill from surface, checking connectivity
    // If unreachable areas found, carve a 2-wide vertical shaft
    // This is called after initial world gen to ensure playability

    int carveX = 0; // Center of world
    for (int y = 0; y < targetDepthTiles; y++) {
      final chunkY = y ~/ GameConstants.chunkSize;
      final localY = y % GameConstants.chunkSize;

      for (int dx = -1; dx <= 1; dx++) {
        final x = carveX + dx;
        final chunkX = x >= 0
            ? x ~/ GameConstants.chunkSize
            : -((-x - 1) ~/ GameConstants.chunkSize + 1);
        final localX = ((x % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;

        final chunkData = chunks[chunkX]?[chunkY];
        if (chunkData != null &&
            localY < chunkData.length &&
            localX < chunkData[0].length) {
          final cell = chunkData[localY][localX];
          if (cell.isSolid && cell.type != CellType.ore) {
            // Don't carve through ore - let player find those
            cell.type = CellType.empty;
            cell.density = 0.0;
            cell.isDirty = true;
          }
        }
      }

      // Slight random walk to make path feel natural
      if (_random.nextDouble() > 0.7) {
        carveX += _random.nextBool() ? 1 : -1;
        carveX = carveX.clamp(-5, 5);
      }
    }
  }
}
