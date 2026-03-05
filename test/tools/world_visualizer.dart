@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hellbore/data/creature_definitions.dart';
import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/world/terrain_cell.dart';
import 'package:hellbore/world/world_generator.dart';

/// Headless world gen visualizer — prints ASCII cross-sections of generated worlds.
/// Run with: flutter test test/tools/world_visualizer.dart
void main() {
  test('World Visualizer — generate and print 5 seeds', () {
    final seeds = [12345, 42, 99999, 7, 314159];

    for (final seed in seeds) {
      print('\n${'=' * 120}');
      print('SEED: $seed');
      print('=' * 120);

      final gen = WorldGenerator(seed: seed);
      final size = GameConstants.chunkSize;

      // Generate enough chunks to cover surface to boss depth
      // 120 chars wide ≈ 4 chunks horizontal, 60 chars tall sampled from full depth
      final totalDepthTiles =
          (GameConstants.bossDepth / GameConstants.feetPerTile).ceil() + 10;
      final totalChunksY = (totalDepthTiles / size).ceil();

      // Generate a 4-wide column of chunks centered at x=0
      final chunks = <String, List<List<TerrainCell>>>{};
      for (int cy = 0; cy <= totalChunksY; cy++) {
        for (int cx = -2; cx <= 1; cx++) {
          final key = '$cx,$cy';
          chunks[key] = gen.generateChunk(cx, cy);
        }
      }

      // Collect stats
      int totalCells = 0;
      int emptyCells = 0;
      int oreCells = 0;
      int lavaCells = 0;
      int gasCells = 0;
      int creatureSpawns = 0;
      final oreByBiome = <String, int>{};
      final solidByBiome = <String, int>{};
      final emptyByBiome = <String, int>{};
      int caveWormCount = 0;
      int rockCrabCount = 0;
      int gasSporeCount = 0;
      int lavaEelCount = 0;

      // Scan all cells for stats
      for (final entry in chunks.entries) {
        final parts = entry.key.split(',');
        final cy = int.parse(parts[1]);
        final grid = entry.value;

        for (int ly = 0; ly < size; ly++) {
          for (int lx = 0; lx < size; lx++) {
            final worldY = cy * size + ly;
            final depthFeet = worldY * GameConstants.feetPerTile;
            final cell = grid[ly][lx];
            totalCells++;

            final biomeName = _getBiomeBand(depthFeet);

            if (cell.type == CellType.empty) {
              emptyCells++;
              emptyByBiome[biomeName] = (emptyByBiome[biomeName] ?? 0) + 1;
            } else if (cell.type == CellType.ore) {
              oreCells++;
              oreByBiome[biomeName] = (oreByBiome[biomeName] ?? 0) + 1;
              solidByBiome[biomeName] =
                  (solidByBiome[biomeName] ?? 0) + 1;
            } else if (cell.type == CellType.lava) {
              lavaCells++;
            } else if (cell.type == CellType.gas) {
              gasCells++;
              emptyByBiome[biomeName] = (emptyByBiome[biomeName] ?? 0) + 1;
            } else {
              solidByBiome[biomeName] =
                  (solidByBiome[biomeName] ?? 0) + 1;
            }

            if (cell.hasCreatureSpawn) {
              creatureSpawns++;
              final creatures =
                  CreatureDefinitions.getCreaturesAtDepth(depthFeet);
              for (final c in creatures) {
                switch (c.name) {
                  case 'Cave Worm':
                    caveWormCount++;
                  case 'Rock Crab':
                    rockCrabCount++;
                  case 'Gas Spore':
                    gasSporeCount++;
                  case 'Lava Eel':
                    lavaEelCount++;
                }
              }
            }
          }
        }
      }

      // Print ASCII visualization (120 wide x 60 tall, sampled)
      const viewWidth = 120;
      const viewHeight = 60;
      final startWorldX = -viewWidth ~/ 2;
      final sampleStepY = max(1, totalDepthTiles ~/ viewHeight);

      for (int vy = 0; vy < viewHeight; vy++) {
        final worldY = vy * sampleStepY;
        final depthFeet = worldY * GameConstants.feetPerTile;
        final buf = StringBuffer();
        buf.write('${depthFeet.toStringAsFixed(0).padLeft(5)}ft |');

        for (int vx = 0; vx < viewWidth; vx++) {
          final worldX = startWorldX + vx;

          final cx = worldX >= 0
              ? worldX ~/ size
              : -(((-worldX - 1) ~/ size) + 1);
          final cy = worldY >= 0
              ? worldY ~/ size
              : -(((-worldY - 1) ~/ size) + 1);
          final lx = ((worldX % size) + size) % size;
          final ly = ((worldY % size) + size) % size;

          final key = '$cx,$cy';
          final grid = chunks[key];
          if (grid == null) {
            buf.write('?');
            continue;
          }

          final cell = grid[ly][lx];

          // Pod spawn point
          if (worldX == 0 && worldY == 0) {
            buf.write('@');
            continue;
          }

          // Natas boss position
          if (worldX == 0 &&
              (depthFeet - GameConstants.bossDepth).abs() <
                  GameConstants.feetPerTile) {
            buf.write('N');
            continue;
          }

          // Creature spawns
          if (cell.hasCreatureSpawn) {
            final creatures =
                CreatureDefinitions.getCreaturesAtDepth(depthFeet);
            if (creatures.any((c) => c.name == 'Cave Worm')) {
              buf.write('W');
              continue;
            }
            if (creatures.any((c) => c.name == 'Rock Crab')) {
              buf.write('C');
              continue;
            }
            if (creatures.any((c) => c.name == 'Gas Spore')) {
              buf.write('S');
              continue;
            }
            if (creatures.any((c) => c.name == 'Lava Eel')) {
              buf.write('E');
              continue;
            }
          }

          switch (cell.type) {
            case CellType.empty:
              buf.write(' ');
            case CellType.sand:
            case CellType.dirt:
              buf.write('\u2591'); // ░
            case CellType.rock:
              buf.write('\u2592'); // ▒
            case CellType.obsidian:
              buf.write('\u2593'); // ▓
            case CellType.ore:
              buf.write('\u2726'); // ✦
            case CellType.lava:
              buf.write('~');
            case CellType.gas:
              buf.write('*');
            case CellType.bedrock:
              buf.write('\u2588'); // █
          }
        }
        print(buf.toString());
      }

      // Print stats
      print('\n--- STATS for seed $seed ---');
      print(
          'Total cave %: ${(emptyCells / totalCells * 100).toStringAsFixed(1)}%');
      print('Ore cells: $oreCells');
      print('Lava cells: $lavaCells');
      print('Gas cells: $gasCells');
      print('Creature spawns: $creatureSpawns');
      print(
          '  Cave Worms: $caveWormCount, Rock Crabs: $rockCrabCount, Gas Spores: $gasSporeCount, Lava Eels: $lavaEelCount');

      // Per-biome stats
      for (final biome in [
        'Surface',
        'Mid',
        'Deep',
        'Volcanic',
        'Hell'
      ]) {
        final empty = emptyByBiome[biome] ?? 0;
        final solid = solidByBiome[biome] ?? 0;
        final ore = oreByBiome[biome] ?? 0;
        final total = empty + solid;
        if (total == 0) continue;
        final emptyPct = (empty / total * 100).toStringAsFixed(1);
        final orePct =
            solid > 0 ? (ore / solid * 100).toStringAsFixed(1) : '0.0';
        print('  $biome: $emptyPct% empty, ore density: $orePct% of solid');
      }

      // Path check (simplified — check if any empty cell exists at each depth sample)
      bool pathExists = true;
      for (int y = 0; y < totalDepthTiles; y += 5) {
        bool foundEmpty = false;
        for (int x = -10; x <= 10; x++) {
          final cx = x >= 0
              ? x ~/ size
              : -(((-x - 1) ~/ size) + 1);
          final cy = y ~/ size;
          final lx = ((x % size) + size) % size;
          final ly = y % size;
          final key = '$cx,$cy';
          final grid = chunks[key];
          if (grid != null && grid[ly][lx].type == CellType.empty) {
            foundEmpty = true;
            break;
          }
        }
        if (!foundEmpty) {
          pathExists = false;
          break;
        }
      }
      print('Path guarantee (surface to Hell): ${pathExists ? "Y" : "N"}');
    }
  });
}

String _getBiomeBand(double depthFeet) {
  if (depthFeet <= 200) return 'Surface';
  if (depthFeet <= 2000) return 'Mid';
  if (depthFeet <= 4000) return 'Deep';
  if (depthFeet <= 5500) return 'Volcanic';
  return 'Hell';
}
