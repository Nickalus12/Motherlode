import 'dart:math';

import 'package:hellbore/data/creature_definitions.dart';
import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/utils/noise_utils.dart';
import 'package:hellbore/world/biome.dart';
import 'package:hellbore/world/ore_registry.dart';
import 'package:hellbore/world/terrain_cell.dart';

/// Generates the procedural world using multi-octave Simplex noise
/// and cellular automata smoothing
class WorldGenerator {
  final int seed;

  WorldGenerator({required this.seed});

  /// Boss arena rectangle in tile coordinates (centered at x=0, at boss depth)
  static int get bossArenaMinX => -8;
  static int get bossArenaMaxX => 8;
  static int get bossArenaTileY =>
      (GameConstants.bossDepth / GameConstants.feetPerTile).round();
  static int get bossArenaMinY => bossArenaTileY - 5;
  static int get bossArenaMaxY => bossArenaTileY + 5;

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

    // Step 3: Run cellular automata smoothing (4 passes with biome-aware rules)
    _runCellularAutomata(grid, worldStartX, worldStartY, size);

    // Step 4: Classify cells by depth biome
    _classifyCellsByBiome(grid, worldStartX, worldStartY, size);

    // Step 5: Place ore veins using drunk-walk blob generation
    _placeOreVeins(grid, worldStartX, worldStartY, size);

    // Step 6: Place hazards (lava, gas)
    _placeHazards(grid, worldStartX, worldStartY, size);

    // Step 7: Mark creature spawn points
    _markCreatureSpawns(grid, worldStartX, worldStartY, size);

    // Step 8: Handle surface zone (keep top area mostly clear)
    _handleSurfaceZone(grid, worldStartX, worldStartY, size);

    // Step 9: Protect boss arena
    _protectBossArena(grid, worldStartX, worldStartY, size);

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
        final depthFeet = worldY * GameConstants.feetPerTile;
        final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);

        final density = NoiseUtils.sampleMultiOctave(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
          octaves: 4,
          frequency: 0.02,
          lacunarity: 2.0,
          gain: 0.5,
        );

        // Cave noise with biome-scaled influence
        final caveNoise = NoiseUtils.sampleCaveNoise(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
        );

        // Scale cave influence by biome's cave frequency
        final caveInfluence = caveNoise * biome.caveFrequency * 0.5;

        // Combined density: base terrain minus cave carving
        grid[y][x].density = (density - caveInfluence).clamp(0.0, 1.0);
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

  /// Step 3: Run 4 cellular automata passes with biome-specific rules
  void _runCellularAutomata(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    // Pass 1-2: Smoothing (removes isolated cells, fills tiny gaps)
    for (int pass = 0; pass < 2; pass++) {
      _caPassSmoothing(grid, size);
    }

    // Pass 3: Cave opening (remove tiny solid pockets < 4 cells)
    _caPassCaveOpening(grid, size);

    // Pass 4: Biome-specific smoothing
    _caPassBiomeSpecific(grid, worldStartX, worldStartY, size);
  }

  /// CA Pass 1-2: Standard smoothing
  /// Solid cell with < 3 solid orthogonal neighbors -> becomes empty
  /// Empty cell with > 5 solid 8-connected neighbors -> becomes solid
  void _caPassSmoothing(List<List<TerrainCell>> grid, int size) {
    final typeCopy = List.generate(
      size,
      (y) => List.generate(size, (x) => grid[y][x].type),
    );

    for (int y = 1; y < size - 1; y++) {
      for (int x = 1; x < size - 1; x++) {
        // Count orthogonal neighbors (4-connected)
        int solidOrtho = 0;
        if (typeCopy[y - 1][x] != CellType.empty) solidOrtho++;
        if (typeCopy[y + 1][x] != CellType.empty) solidOrtho++;
        if (typeCopy[y][x - 1] != CellType.empty) solidOrtho++;
        if (typeCopy[y][x + 1] != CellType.empty) solidOrtho++;

        // Count 8-connected neighbors for fill rule
        int solid8 = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (typeCopy[y + dy][x + dx] != CellType.empty) {
              solid8++;
            }
          }
        }

        if (typeCopy[y][x] != CellType.empty) {
          // Solid cell with < 3 solid orthogonal neighbors -> empty
          if (solidOrtho < 3) {
            grid[y][x].type = CellType.empty;
            grid[y][x].density = 0.0;
          }
        } else {
          // Empty cell with > 5 solid neighbors (8-connected) -> solid
          if (solid8 > 5) {
            grid[y][x].type = CellType.dirt;
            grid[y][x].density = 0.6;
          }
        }
      }
    }
  }

  /// CA Pass 3: Remove solid regions smaller than 4 cells (prevents tiny pockets)
  void _caPassCaveOpening(List<List<TerrainCell>> grid, int size) {
    final visited = List.generate(
      size,
      (_) => List.generate(size, (_) => false),
    );

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (visited[y][x] || grid[y][x].type == CellType.empty) continue;

        // Flood fill to find connected solid region
        final region = <Point<int>>[];
        final stack = <Point<int>>[Point(x, y)];
        visited[y][x] = true;

        while (stack.isNotEmpty) {
          final p = stack.removeLast();
          region.add(p);

          for (final dir in [
            const Point(0, -1),
            const Point(0, 1),
            const Point(-1, 0),
            const Point(1, 0),
          ]) {
            final nx = p.x + dir.x;
            final ny = p.y + dir.y;
            if (nx >= 0 &&
                nx < size &&
                ny >= 0 &&
                ny < size &&
                !visited[ny][nx] &&
                grid[ny][nx].type != CellType.empty) {
              visited[ny][nx] = true;
              stack.add(Point(nx, ny));
            }
          }
        }

        // Remove regions smaller than 4 cells
        if (region.length < 4) {
          for (final p in region) {
            grid[p.y][p.x].type = CellType.empty;
            grid[p.y][p.x].density = 0.0;
          }
        }
      }
    }
  }

  /// CA Pass 4: Biome-specific smoothing
  /// Surface: extra smoothing (softer, rounder caves)
  /// Hell: NO smoothing (jagged, hostile geometry)
  void _caPassBiomeSpecific(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    final typeCopy = List.generate(
      size,
      (y) => List.generate(size, (x) => grid[y][x].type),
    );

    for (int y = 1; y < size - 1; y++) {
      final worldY = worldStartY + y;
      final depthFeet = worldY * GameConstants.feetPerTile;
      final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);

      // Skip smoothing for Hell biome - keep jagged geometry
      if (biome.type == BiomeType.hell) continue;

      // Extra smoothing for surface/topsoil - softer, rounder caves
      if (biome.type == BiomeType.topsoil ||
          biome.type == BiomeType.surface) {
        for (int x = 1; x < size - 1; x++) {
          int solidNeighbors = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              if (typeCopy[y + dy][x + dx] != CellType.empty) {
                solidNeighbors++;
              }
            }
          }

          if (typeCopy[y][x] != CellType.empty) {
            if (solidNeighbors < 4) {
              grid[y][x].type = CellType.empty;
              grid[y][x].density = 0.0;
            }
          } else {
            if (solidNeighbors > 5) {
              grid[y][x].type = CellType.dirt;
              grid[y][x].density = 0.6;
            }
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

  /// Step 5: Place ore veins using drunk-walk blob generation
  void _placeOreVeins(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    // Use a seeded random for deterministic ore placement
    final oreRandom = Random(seed ^ (worldStartX * 7919 + worldStartY * 6271));

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (grid[y][x].type == CellType.empty) continue;

        final worldX = worldStartX + x;
        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;

        // Sample ore noise to determine if a vein seed starts here
        final oreNoise = NoiseUtils.sampleOreNoise(
          seed: seed,
          x: worldX.toDouble(),
          y: worldY.toDouble(),
        );

        // Only start a vein at high-noise seed points
        if (oreNoise > 0.78) {
          final ore = OreRegistry.selectOreForSpawn(depthFeet, oreNoise);
          if (ore != null) {
            _drunkWalkOreVein(grid, x, y, size, ore, oreRandom);
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

  /// Drunk-walk ore vein from a seed cell
  /// Each step moves in a random direction weighted 70% horizontal
  void _drunkWalkOreVein(
    List<List<TerrainCell>> grid,
    int seedX,
    int seedY,
    int size,
    OreType ore,
    Random rng,
  ) {
    // Determine vein size based on ore rarity
    int baseSize;
    int variance;
    if (ore.spawnRarity < 0.15) {
      // Common: Ironium, Bronzium (4-8 cells)
      baseSize = 4;
      variance = 4;
    } else if (ore.spawnRarity < 0.30) {
      // Mid: Goldium, Platinium (3-6 cells)
      baseSize = 3;
      variance = 3;
    } else if (ore.spawnRarity < 0.50) {
      // Rare: Einsteinium, Emerald (2-4 cells)
      baseSize = 2;
      variance = 2;
    } else if (ore.spawnRarity < 0.80) {
      // Ultra rare: Ruby, Diamond, Amazonite (1-3 cells)
      baseSize = 1;
      variance = 2;
    } else {
      // Hell ores: Hellstone, Soul Crystal (2-5 cells)
      baseSize = 2;
      variance = 3;
    }

    final steps = baseSize + rng.nextInt(variance + 1);
    int cx = seedX;
    int cy = seedY;

    for (int i = 0; i < steps; i++) {
      if (cx >= 0 && cx < size && cy >= 0 && cy < size) {
        final cell = grid[cy][cx];
        if (cell.type != CellType.empty &&
            cell.type != CellType.lava &&
            cell.type != CellType.gas) {
          cell.type = CellType.ore;
          cell.oreType = ore;
        }
      }

      // Weighted random walk: 70% horizontal, 30% vertical
      if (rng.nextDouble() < 0.7) {
        cx += rng.nextBool() ? 1 : -1;
      } else {
        cy += rng.nextBool() ? 1 : -1;
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

        // Lava placement - irregular blobs
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

        // Gas placement - clusters near lava
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
        if (grid[y][x].type != CellType.empty) continue;

        final worldX = worldStartX + x;
        final worldY = worldStartY + y;
        final depthFeet = worldY * GameConstants.feetPerTile;

        if (depthFeet < 500) continue;

        final available =
            CreatureDefinitions.getCreaturesAtDepth(depthFeet);
        if (available.isEmpty) continue;

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

      if (worldY < 0) {
        for (int x = 0; x < size; x++) {
          grid[y][x].type = CellType.empty;
          grid[y][x].density = 0.0;
        }
      } else if (worldY == 0) {
        for (int x = 0; x < size; x++) {
          final worldX = worldStartX + x;
          if (worldX.abs() <= 3) {
            grid[y][x].type = CellType.empty;
            grid[y][x].density = 0.0;
          } else {
            grid[y][x].type = CellType.sand;
            grid[y][x].density = 0.8;
          }
        }
      } else if (worldY * GameConstants.feetPerTile <=
          GameConstants.sandLayerEnd) {
        for (int x = 0; x < size; x++) {
          if (grid[y][x].type != CellType.empty) {
            grid[y][x].type = CellType.sand;
          }
        }
      }
    }
  }

  /// Step 9: Protect the boss arena at -7187ft from noise corruption
  void _protectBossArena(
    List<List<TerrainCell>> grid,
    int worldStartX,
    int worldStartY,
    int size,
  ) {
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final worldX = worldStartX + x;
        final worldY = worldStartY + y;

        if (worldX >= bossArenaMinX &&
            worldX <= bossArenaMaxX &&
            worldY >= bossArenaMinY &&
            worldY <= bossArenaMaxY) {
          // Arena interior: always empty
          if (worldX > bossArenaMinX &&
              worldX < bossArenaMaxX &&
              worldY > bossArenaMinY &&
              worldY < bossArenaMaxY) {
            grid[y][x].type = CellType.empty;
            grid[y][x].density = 0.0;
            grid[y][x].oreType = null;
          }
          // Arena walls: always solid obsidian
          else {
            grid[y][x].type = CellType.obsidian;
            grid[y][x].density = 1.0;
            grid[y][x].oreType = null;
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

    if (depthFeet >= 3700 && depthFeet <= 7300 && hash % 500 == 0) {
      return OreRegistry.ancientScroll;
    }

    return available[hash.abs() % available.length];
  }

  /// Verify a path exists from surface to a target depth.
  /// Uses flood fill to check connectivity, then carves if blocked.
  void guaranteePath(
    Map<String, List<List<TerrainCell>>> chunks,
    int targetDepthTiles,
  ) {
    for (int attempt = 0; attempt < 5; attempt++) {
      if (_floodFillPathExists(chunks, targetDepthTiles)) {
        return;
      }
      _carveNaturalPath(chunks, targetDepthTiles, attempt);
    }
  }

  /// Check if a downward path exists from surface to target depth
  bool _floodFillPathExists(
    Map<String, List<List<TerrainCell>>> chunks,
    int targetDepthTiles,
  ) {
    final size = GameConstants.chunkSize;
    final visited = <String>{};
    final stack = <Point<int>>[];

    stack.add(const Point(0, 0));

    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final key = '${p.x},${p.y}';
      if (visited.contains(key)) continue;
      visited.add(key);

      if (p.y >= targetDepthTiles - 7) return true;

      for (final dir in [
        const Point(0, 1),
        const Point(-1, 0),
        const Point(1, 0),
        const Point(0, -1),
      ]) {
        final nx = p.x + dir.x;
        final ny = p.y + dir.y;
        if (ny < 0 || ny > targetDepthTiles) continue;
        if (nx.abs() > 30) continue;

        final nkey = '$nx,$ny';
        if (visited.contains(nkey)) continue;

        final chunkX = nx >= 0
            ? nx ~/ size
            : -(((-nx - 1) ~/ size) + 1);
        final chunkY = ny >= 0
            ? ny ~/ size
            : -(((-ny - 1) ~/ size) + 1);
        final localX = ((nx % size) + size) % size;
        final localY = ((ny % size) + size) % size;

        final chunkKey = '$chunkX,$chunkY';
        final chunkData = chunks[chunkKey];
        if (chunkData == null) continue;

        if (localY < chunkData.length && localX < chunkData[0].length) {
          final cell = chunkData[localY][localX];
          if (!cell.isSolid) {
            stack.add(Point(nx, ny));
          }
        }
      }
    }
    return false;
  }

  /// Carve a natural path with slight horizontal drift
  void _carveNaturalPath(
    Map<String, List<List<TerrainCell>>> chunks,
    int targetDepthTiles,
    int attempt,
  ) {
    final size = GameConstants.chunkSize;
    final pathRng = Random(seed + attempt * 31);
    int carveX = 0;

    for (int y = 0; y < targetDepthTiles; y++) {
      for (int dx = -1; dx <= 1; dx++) {
        final x = carveX + dx;
        final chunkX = x >= 0
            ? x ~/ size
            : -(((-x - 1) ~/ size) + 1);
        final chunkY = y >= 0
            ? y ~/ size
            : -(((-y - 1) ~/ size) + 1);
        final localX = ((x % size) + size) % size;
        final localY = ((y % size) + size) % size;

        final chunkKey = '$chunkX,$chunkY';
        final chunkData = chunks[chunkKey];
        if (chunkData != null &&
            localY < chunkData.length &&
            localX < chunkData[0].length) {
          final cell = chunkData[localY][localX];
          if (cell.isSolid && cell.type != CellType.ore) {
            cell.type = CellType.empty;
            cell.density = 0.0;
            cell.isDirty = true;
          }
        }
      }

      // Drift ±1 cell per ~10ft for natural appearance
      if (pathRng.nextDouble() > 0.6) {
        carveX += pathRng.nextBool() ? 1 : -1;
        carveX = carveX.clamp(-8, 8);
      }
    }
  }
}
