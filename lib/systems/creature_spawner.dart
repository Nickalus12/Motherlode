import 'dart:math';

import 'package:flame/components.dart';

import 'package:motherlode/data/creature_definitions.dart';
import 'package:motherlode/entities/creatures/cave_worm.dart';
import 'package:motherlode/entities/creatures/creature.dart';
import 'package:motherlode/entities/creatures/gas_spore.dart';
import 'package:motherlode/entities/creatures/lava_eel.dart';
import 'package:motherlode/entities/creatures/natas_boss.dart';
import 'package:motherlode/entities/creatures/rock_crab.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/chunk.dart';

/// Manages creature lifecycle: spawning from chunk data, despawning on
/// chunk unload, and enforcing a global creature cap for performance.
class CreatureSpawner extends Component with HasGameReference<MotherlodeGame> {
  /// Maximum number of creatures alive at once.
  static const int maxActiveCreatures = 12;

  /// Minimum distance (tiles) from the pod to spawn a creature.
  static const double minSpawnDistance = 10.0;

  /// How often (seconds) to scan for spawns.
  static const double _scanInterval = 2.0;

  final Random _rng;

  /// Active creatures keyed by chunk key.
  final Map<String, List<Creature>> _creaturesByChunk = {};

  /// Chunk keys that have already been scanned (avoid re-spawning).
  final Set<String> _scannedChunks = {};

  double _scanTimer = 0;

  CreatureSpawner({int? seed}) : _rng = Random(seed ?? 0);

  int get activeCreatureCount =>
      _creaturesByChunk.values.fold(0, (sum, list) => sum + list.length);

  @override
  void update(double dt) {
    super.update(dt);

    _scanTimer += dt;
    if (_scanTimer < _scanInterval) return;
    _scanTimer = 0;

    _despawnUnloadedChunks();
    _scanForSpawns();
  }

  /// Remove creatures whose chunk is no longer loaded.
  void _despawnUnloadedChunks() {
    final loadedKeys = <String>{};
    for (final chunk in game.chunkManager.activeChunks) {
      loadedKeys.add('${chunk.chunkX},${chunk.chunkY}');
    }

    final keysToRemove = <String>[];
    for (final entry in _creaturesByChunk.entries) {
      if (!loadedKeys.contains(entry.key)) {
        for (final creature in entry.value) {
          creature.removeFromParent();
        }
        keysToRemove.add(entry.key);
        _scannedChunks.remove(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _creaturesByChunk.remove(key);
    }

    // Also clean up dead creatures from active lists
    for (final list in _creaturesByChunk.values) {
      list.removeWhere((c) => c.state == CreatureState.dead || !c.isMounted);
    }
  }

  /// Scan loaded chunks for creature spawn points.
  void _scanForSpawns() {
    if (activeCreatureCount >= maxActiveCreatures) return;

    final podPos = game.pod.position;

    for (final chunk in game.chunkManager.activeChunks) {
      final key = '${chunk.chunkX},${chunk.chunkY}';
      if (_scannedChunks.contains(key)) continue;

      _spawnFromChunk(chunk, key, podPos);

      if (activeCreatureCount >= maxActiveCreatures) break;
    }
  }

  /// Check a chunk's cells for spawn points and create creatures.
  void _spawnFromChunk(Chunk chunk, String key, Vector2 podPos) {
    _scannedChunks.add(key);

    const size = GameConstants.chunkSize;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final cell = chunk.cells[y][x];
        if (!cell.hasCreatureSpawn) continue;

        // World position of this spawn point
        final worldX = (chunk.chunkX * size + x).toDouble();
        final worldY = (chunk.chunkY * size + y).toDouble();
        final spawnPos = Vector2(worldX, worldY);

        // Don't spawn too close to the pod
        if (spawnPos.distanceTo(podPos) < minSpawnDistance) continue;

        // Check creature cap
        if (activeCreatureCount >= maxActiveCreatures) return;

        final depthFeet = worldY * GameConstants.feetPerTile;
        final info =
            CreatureDefinitions.selectCreatureForSpawn(depthFeet, _rng);
        if (info == null) continue;

        // Roll against spawn chance
        if (_rng.nextDouble() > info.spawnChance) continue;

        final creature = _createCreature(info.name, spawnPos);
        if (creature == null) continue;

        game.world.add(creature);
        _creaturesByChunk.putIfAbsent(key, () => []).add(creature);

        // Clear the spawn flag so reloading doesn't re-spawn
        cell.hasCreatureSpawn = false;
      }
    }
  }

  /// Instantiate the correct creature subclass by name.
  Creature? _createCreature(String name, Vector2 position) {
    switch (name) {
      case 'Cave Worm':
        return CaveWorm(initialPosition: position);
      case 'Rock Crab':
        return RockCrab(initialPosition: position);
      case 'Gas Spore':
        return GasSpore(initialPosition: position);
      case 'Lava Eel':
        return LavaEel(initialPosition: position);
      case 'Mr. Natas':
        return NatasBoss(initialPosition: position);
      default:
        return null;
    }
  }

  @override
  void onRemove() {
    // Clean up all creatures
    for (final list in _creaturesByChunk.values) {
      for (final creature in list) {
        creature.removeFromParent();
      }
    }
    _creaturesByChunk.clear();
    _scannedChunks.clear();
    super.onRemove();
  }
}
