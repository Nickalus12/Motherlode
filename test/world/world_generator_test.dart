@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/data/creature_definitions.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/terrain_cell.dart';
import 'package:motherlode/world/world_generator.dart';

void main() {
  // Helper: generate chunks covering surface to target depth
  Map<String, List<List<TerrainCell>>> generateWorld(int seed,
      {int chunkRadius = 1}) {
    final gen = WorldGenerator(seed: seed);
    const size = GameConstants.chunkSize;
    final totalDepthTiles =
        (GameConstants.bossDepth / GameConstants.feetPerTile).ceil() + 10;
    final totalChunksY = (totalDepthTiles / size).ceil();
    final chunks = <String, List<List<TerrainCell>>>{};

    for (int cy = 0; cy <= totalChunksY; cy++) {
      for (int cx = -chunkRadius; cx <= chunkRadius; cx++) {
        chunks['$cx,$cy'] = gen.generateChunk(cx, cy);
      }
    }
    return chunks;
  }

  // Helper: get cell at world tile coordinates from chunk map
  TerrainCell? getCell(
      Map<String, List<List<TerrainCell>>> chunks, int wx, int wy) {
    const size = GameConstants.chunkSize;
    final cx = wx >= 0 ? wx ~/ size : -(((-wx - 1) ~/ size) + 1);
    final cy = wy >= 0 ? wy ~/ size : -(((-wy - 1) ~/ size) + 1);
    final lx = ((wx % size) + size) % size;
    final ly = ((wy % size) + size) % size;
    final grid = chunks['$cx,$cy'];
    if (grid == null) return null;
    return grid[ly][lx];
  }

  // 1. DETERMINISM
  test('1. Same seed produces identical world', () {
    const seed = 12345;
    final gen1 = WorldGenerator(seed: seed);
    final gen2 = WorldGenerator(seed: seed);

    // Compare several chunks
    for (int cy = 0; cy < 5; cy++) {
      for (int cx = -1; cx <= 1; cx++) {
        final grid1 = gen1.generateChunk(cx, cy);
        final grid2 = gen2.generateChunk(cx, cy);

        for (int y = 0; y < GameConstants.chunkSize; y++) {
          for (int x = 0; x < GameConstants.chunkSize; x++) {
            expect(grid1[y][x].type, equals(grid2[y][x].type),
                reason: 'Cell type mismatch at chunk($cx,$cy) local($x,$y)');
            expect(grid1[y][x].oreType?.name, equals(grid2[y][x].oreType?.name),
                reason: 'Ore type mismatch at chunk($cx,$cy) local($x,$y)');
            expect(grid1[y][x].hasCreatureSpawn,
                equals(grid2[y][x].hasCreatureSpawn),
                reason:
                    'Creature spawn mismatch at chunk($cx,$cy) local($x,$y)');
          }
        }
      }
    }
  });

  // 2. PATH EXISTS
  test('2. Every generated world has a traversable path', () {
    for (int seedIdx = 0; seedIdx < 20; seedIdx++) {
      final seed = seedIdx * 1000 + 42;
      final chunks = generateWorld(seed, chunkRadius: 2);

      // Check path: scan depth rows for empty cells within ±30 of center
      final totalDepthTiles =
          (GameConstants.bossDepth / GameConstants.feetPerTile).ceil();
      int blockedCount = 0;

      for (int y = 1; y < totalDepthTiles; y += 5) {
        bool foundEmpty = false;
        for (int x = -30; x <= 30; x++) {
          final cell = getCell(chunks, x, y);
          if (cell != null && !cell.isSolid) {
            foundEmpty = true;
            break;
          }
        }
        if (!foundEmpty) blockedCount++;
      }

      // Allow up to 2 blocked rows (player can drill through thin walls)
      expect(blockedCount, lessThanOrEqualTo(2),
          reason: 'Seed $seed has $blockedCount blocked rows (max 2 allowed)');
    }
  });

  // 3. BIOME BOUNDARIES: Correct ores at correct depths
  test('3. Biome-appropriate ores spawn at correct depths', () {
    final chunks = generateWorld(12345, chunkRadius: 2);
    const size = GameConstants.chunkSize;
    final totalDepthTiles =
        (GameConstants.maxDepth / GameConstants.feetPerTile).ceil();

    for (int wy = 0; wy < totalDepthTiles; wy++) {
      final depthFeet = wy * GameConstants.feetPerTile;
      for (int wx = -2 * size; wx < 2 * size; wx++) {
        final cell = getCell(chunks, wx, wy);
        if (cell == null || cell.type != CellType.ore || cell.oreType == null) {
          continue;
        }

        final ore = cell.oreType!;
        // No Amazonite above 4812ft
        if (ore.name == 'Amazonite') {
          expect(depthFeet, greaterThanOrEqualTo(4812),
              reason:
                  'Amazonite found at ${depthFeet}ft (should be >= 4812ft)');
        }
        // No Hellstone above 6000ft
        if (ore.name == 'Hellstone') {
          expect(depthFeet, greaterThanOrEqualTo(6000),
              reason:
                  'Hellstone found at ${depthFeet}ft (should be >= 6000ft)');
        }
        // Diamond only below 4000ft
        if (ore.name == 'Diamond') {
          expect(depthFeet, greaterThanOrEqualTo(4000),
              reason: 'Diamond found at ${depthFeet}ft (should be >= 4000ft)');
        }
      }
    }

    // Ironium spawns in first 500ft (just verify it exists there)
    bool foundIroniumShallow = false;
    for (int wy = 0; wy < (500 / GameConstants.feetPerTile).ceil(); wy++) {
      for (int wx = -size; wx < size; wx++) {
        final cell = getCell(chunks, wx, wy);
        if (cell?.oreType?.name == 'Ironium') {
          foundIroniumShallow = true;
          break;
        }
      }
      if (foundIroniumShallow) break;
    }
    expect(foundIroniumShallow, isTrue,
        reason: 'No Ironium found in first 500ft');
  });

  // 4. ORE DENSITY
  test('4. Ore density is reasonable per biome band', () {
    final oreCountByBiome = <String, int>{};
    final solidCountByBiome = <String, int>{};

    for (int seedIdx = 0; seedIdx < 10; seedIdx++) {
      final seed = seedIdx * 777 + 1;
      final chunks = generateWorld(seed);
      const size = GameConstants.chunkSize;

      for (final entry in chunks.entries) {
        final parts = entry.key.split(',');
        final cy = int.parse(parts[1]);
        final grid = entry.value;

        for (int ly = 0; ly < size; ly++) {
          final depthFeet = (cy * size + ly) * GameConstants.feetPerTile;
          final biome = _biomeBand(depthFeet);

          for (int lx = 0; lx < size; lx++) {
            final cell = grid[ly][lx];
            if (cell.isSolid || cell.type == CellType.ore) {
              solidCountByBiome[biome] = (solidCountByBiome[biome] ?? 0) + 1;
              if (cell.type == CellType.ore) {
                oreCountByBiome[biome] = (oreCountByBiome[biome] ?? 0) + 1;
              }
            }
          }
        }
      }
    }

    for (final biome in ['Surface', 'Mid', 'Deep', 'Volcanic', 'Hell']) {
      final ores = oreCountByBiome[biome] ?? 0;
      final solids = solidCountByBiome[biome] ?? 0;
      if (solids == 0) continue;
      final density = ores / solids;
      // Surface may have low ore density due to shallow depth
      final minDensity = biome == 'Surface' ? 0.0 : 0.03;
      expect(density, greaterThanOrEqualTo(minDensity),
          reason:
              '$biome ore density too low: ${(density * 100).toStringAsFixed(1)}%');
      expect(density, lessThanOrEqualTo(0.12),
          reason:
              '$biome ore density too high: ${(density * 100).toStringAsFixed(1)}%');
    }
  });

  // 5. CAVE PERCENTAGE per biome
  test('5. Cave percentages match targets per biome', () {
    final emptyByBiome = <String, int>{};
    final totalByBiome = <String, int>{};

    // Average over 3 seeds for stability
    for (int seedIdx = 0; seedIdx < 3; seedIdx++) {
      final seed = seedIdx * 5000 + 100;
      final chunks = generateWorld(seed);
      const size = GameConstants.chunkSize;

      for (final entry in chunks.entries) {
        final parts = entry.key.split(',');
        final cy = int.parse(parts[1]);
        final grid = entry.value;

        for (int ly = 0; ly < size; ly++) {
          final depthFeet = (cy * size + ly) * GameConstants.feetPerTile;
          if (depthFeet < 0) continue;
          final biome = _biomeBand(depthFeet);

          for (int lx = 0; lx < size; lx++) {
            totalByBiome[biome] = (totalByBiome[biome] ?? 0) + 1;
            final cell = grid[ly][lx];
            if (cell.type == CellType.empty ||
                cell.type == CellType.gas ||
                cell.type == CellType.lava) {
              emptyByBiome[biome] = (emptyByBiome[biome] ?? 0) + 1;
            }
          }
        }
      }
    }

    // Surface (0-200ft): 40-80% empty (higher due to natural surface contour)
    _assertCaveRange(emptyByBiome, totalByBiome, 'Surface', 0.40, 0.80);
    // Mid (200-2000ft): 30-50% empty
    _assertCaveRange(emptyByBiome, totalByBiome, 'Mid', 0.30, 0.50);
    // Deep (2000-4000ft): 20-40% empty
    _assertCaveRange(emptyByBiome, totalByBiome, 'Deep', 0.20, 0.40);
    // Hell (5500+ft): 25-45% empty
    _assertCaveRange(emptyByBiome, totalByBiome, 'Hell', 0.25, 0.45);
  });

  // 6. NO ISOLATED CELLS
  test('6. No orphaned solid cells with 0 solid neighbors', () {
    final gen = WorldGenerator(seed: 12345);
    const size = GameConstants.chunkSize;

    for (int cy = 0; cy < 5; cy++) {
      final grid = gen.generateChunk(0, cy);

      for (int y = 1; y < size - 1; y++) {
        for (int x = 1; x < size - 1; x++) {
          if (grid[y][x].type == CellType.empty) continue;
          if (grid[y][x].type == CellType.lava) continue;
          if (grid[y][x].type == CellType.gas) continue;

          int solidNeighbors = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              if (grid[y + dy][x + dx].isSolid) solidNeighbors++;
            }
          }

          // After CA passes, no solid cell should have 0 solid neighbors
          expect(solidNeighbors, greaterThan(0),
              reason: 'Isolated solid cell at chunk(0,$cy) local($x,$y)');
        }
      }
    }
  });

  // 7. CHUNK BOUNDARIES
  test('7. No seams between adjacent chunks', () {
    final gen = WorldGenerator(seed: 42);
    const size = GameConstants.chunkSize;

    // Generate a 2x2 grid of chunks
    final chunks = <String, List<List<TerrainCell>>>{};
    for (int cy = 0; cy < 2; cy++) {
      for (int cx = 0; cx < 2; cx++) {
        chunks['$cx,$cy'] = gen.generateChunk(cx, cy);
      }
    }

    // Check horizontal seam (chunk 0,0 right edge vs chunk 1,0 left edge)
    final left = chunks['0,0']!;
    final right = chunks['1,0']!;
    // The noise-based generation should produce consistent values at borders
    // We verify that border cells don't create impossible discontinuities
    // (all solid next to all empty for an entire edge would be a seam)
    int solidLeftEdge = 0;
    int solidRightEdge = 0;
    for (int y = 0; y < size; y++) {
      if (left[y][size - 1].isSolid) solidLeftEdge++;
      if (right[y][0].isSolid) solidRightEdge++;
    }
    // The ratio of solid cells should be similar on both sides (within 30%)
    final leftRatio = solidLeftEdge / size;
    final rightRatio = solidRightEdge / size;
    expect((leftRatio - rightRatio).abs(), lessThan(0.3),
        reason: 'Horizontal seam detected: left=$leftRatio right=$rightRatio');

    // Check vertical seam
    final top = chunks['0,0']!;
    final bottom = chunks['0,1']!;
    int solidTopEdge = 0;
    int solidBottomEdge = 0;
    for (int x = 0; x < size; x++) {
      if (top[size - 1][x].isSolid) solidTopEdge++;
      if (bottom[0][x].isSolid) solidBottomEdge++;
    }
    final topRatio = solidTopEdge / size;
    final bottomRatio = solidBottomEdge / size;
    expect((topRatio - bottomRatio).abs(), lessThan(0.3),
        reason: 'Vertical seam detected: top=$topRatio bottom=$bottomRatio');
  });

  // 8. ORE VEIN CONNECTIVITY
  test('8. Ore veins are connected blobs, not scattered singles', () {
    final gen = WorldGenerator(seed: 42);
    const size = GameConstants.chunkSize;

    int totalVeins = 0;
    int totalOreCells = 0;

    for (int cy = 1; cy < 10; cy++) {
      final grid = gen.generateChunk(0, cy);
      final visited = List.generate(
        size,
        (_) => List.generate(size, (_) => false),
      );

      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          if (visited[y][x] || grid[y][x].type != CellType.ore) continue;

          // Flood fill ore vein
          int veinSize = 0;
          final stack = <Point<int>>[Point(x, y)];
          visited[y][x] = true;

          while (stack.isNotEmpty) {
            final p = stack.removeLast();
            veinSize++;

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
                  grid[ny][nx].type == CellType.ore) {
                visited[ny][nx] = true;
                stack.add(Point(nx, ny));
              }
            }
          }

          totalVeins++;
          totalOreCells += veinSize;
        }
      }
    }

    if (totalVeins > 0) {
      final avgVeinSize = totalOreCells / totalVeins;
      expect(avgVeinSize, greaterThanOrEqualTo(2.0),
          reason:
              'Average vein size too small: $avgVeinSize (expected >= 2.0)');
    }
  });

  // 9. BOSS ARENA INTEGRITY
  test('9. Boss arena is always intact and clear', () {
    final gen = WorldGenerator(seed: 12345);
    const size = GameConstants.chunkSize;

    final arenaMinX = WorldGenerator.bossArenaMinX;
    final arenaMaxX = WorldGenerator.bossArenaMaxX;
    final arenaMinY = WorldGenerator.bossArenaMinY;
    final arenaMaxY = WorldGenerator.bossArenaMaxY;

    // Generate chunks that cover the arena
    for (int wy = arenaMinY; wy <= arenaMaxY; wy++) {
      for (int wx = arenaMinX; wx <= arenaMaxX; wx++) {
        final cx = wx >= 0 ? wx ~/ size : -(((-wx - 1) ~/ size) + 1);
        final cy = wy >= 0 ? wy ~/ size : -(((-wy - 1) ~/ size) + 1);
        final lx = ((wx % size) + size) % size;
        final ly = ((wy % size) + size) % size;

        final grid = gen.generateChunk(cx, cy);
        final cell = grid[ly][lx];

        // Interior should be empty
        if (wx > arenaMinX &&
            wx < arenaMaxX &&
            wy > arenaMinY &&
            wy < arenaMaxY) {
          expect(cell.type, equals(CellType.empty),
              reason: 'Boss arena interior not empty at ($wx,$wy)');
        }
        // Border should be solid obsidian
        else {
          expect(cell.type, equals(CellType.obsidian),
              reason: 'Boss arena wall not obsidian at ($wx,$wy)');
        }
      }
    }
  });

  // 10. CREATURE SPAWN VALIDITY
  test('10. Creatures spawn in correct zones and in empty cells', () {
    final chunks = generateWorld(42);
    const size = GameConstants.chunkSize;

    for (final entry in chunks.entries) {
      final parts = entry.key.split(',');
      final cy = int.parse(parts[1]);
      final grid = entry.value;

      for (int ly = 0; ly < size; ly++) {
        for (int lx = 0; lx < size; lx++) {
          if (!grid[ly][lx].hasCreatureSpawn) continue;

          final depthFeet = (cy * size + ly) * GameConstants.feetPerTile;

          // Spawns must be in empty cells
          expect(grid[ly][lx].type, equals(CellType.empty),
              reason:
                  'Creature spawn in non-empty cell at depth ${depthFeet}ft');

          // No creatures near surface
          expect(depthFeet, greaterThanOrEqualTo(500),
              reason: 'Creature spawn too shallow: ${depthFeet}ft');

          // Verify creatures available at this depth exist
          final available = CreatureDefinitions.getCreaturesAtDepth(depthFeet);
          expect(available, isNotEmpty,
              reason:
                  'Creature spawn at ${depthFeet}ft but no creatures available');
        }
      }
    }
  });

  // 11. SPECIAL COLLECTIBLE PLACEMENT
  test('11. Collectibles spawn at valid depths', () {
    final chunks = generateWorld(12345, chunkRadius: 2);
    const size = GameConstants.chunkSize;
    int ancientScrollCount = 0;

    for (final entry in chunks.entries) {
      final parts = entry.key.split(',');
      final cy = int.parse(parts[1]);
      final grid = entry.value;

      for (int ly = 0; ly < size; ly++) {
        for (int lx = 0; lx < size; lx++) {
          final cell = grid[ly][lx];
          if (cell.type != CellType.ore) continue;
          if (cell.oreType == null) continue;
          if (!cell.oreType!.isSpecialCollectible) continue;

          final depthFeet = (cy * size + ly) * GameConstants.feetPerTile;

          // No collectibles above 950ft
          expect(depthFeet, greaterThanOrEqualTo(950),
              reason:
                  '${cell.oreType!.name} found at ${depthFeet}ft (should be >= 950ft)');

          if (cell.oreType!.name == 'Ancient Scroll') {
            expect(depthFeet, greaterThanOrEqualTo(3700),
                reason:
                    'Ancient Scroll at ${depthFeet}ft (should be >= 3700ft)');
            expect(depthFeet, lessThanOrEqualTo(7300),
                reason:
                    'Ancient Scroll at ${depthFeet}ft (should be <= 7300ft)');
            ancientScrollCount++;
          }
        }
      }
    }

    // At most one ancient scroll per world
    expect(ancientScrollCount, lessThanOrEqualTo(1),
        reason: 'Found $ancientScrollCount Ancient Scrolls (expected <= 1)');
  });

  // 12. PERFORMANCE
  test('12. World gen completes in acceptable time', () {
    final stopwatch = Stopwatch()..start();

    final gen = WorldGenerator(seed: 99999);
    const size = GameConstants.chunkSize;
    final totalDepthTiles =
        (GameConstants.maxDepth / GameConstants.feetPerTile).ceil();
    final totalChunksY = (totalDepthTiles / size).ceil();

    // Generate full world width=3 chunks
    for (int cy = 0; cy <= totalChunksY; cy++) {
      for (int cx = -1; cx <= 1; cx++) {
        gen.generateChunk(cx, cy);
      }
    }

    stopwatch.stop();
    final elapsed = stopwatch.elapsedMilliseconds;
    print('World generation time: ${elapsed}ms');
    expect(elapsed, lessThan(2000),
        reason: 'World gen took ${elapsed}ms (should be < 2000ms)');
  });
}

String _biomeBand(double depthFeet) {
  if (depthFeet <= 200) return 'Surface';
  if (depthFeet <= 2000) return 'Mid';
  if (depthFeet <= 4000) return 'Deep';
  if (depthFeet <= 5500) return 'Volcanic';
  return 'Hell';
}

void _assertCaveRange(Map<String, int> empty, Map<String, int> total,
    String biome, double minPct, double maxPct) {
  final e = empty[biome] ?? 0;
  final t = total[biome] ?? 1;
  final pct = e / t;
  expect(pct, greaterThanOrEqualTo(minPct),
      reason:
          '$biome cave % too low: ${(pct * 100).toStringAsFixed(1)}% (min ${(minPct * 100).toStringAsFixed(0)}%)');
  expect(pct, lessThanOrEqualTo(maxPct),
      reason:
          '$biome cave % too high: ${(pct * 100).toStringAsFixed(1)}% (max ${(maxPct * 100).toStringAsFixed(0)}%)');
}
