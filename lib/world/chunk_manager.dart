import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/world/chunk.dart';
import 'package:hellbore/world/terrain_cell.dart';
import 'package:hellbore/world/world_generator.dart';

/// Manages chunk loading/unloading based on pod position
class ChunkManager extends Component with HasGameReference<HellboreGame> {
  final WorldGenerator worldGenerator;
  final HellboreGame _game;

  // Active chunks keyed by "chunkX,chunkY" string
  final Map<String, Chunk> _activeChunks = {};

  // Cache of generated but unloaded chunk data
  final Map<String, List<List<TerrainCell>>> _chunkDataCache = {};

  ChunkManager({
    required this.worldGenerator,
    required HellboreGame game,
  }) : _game = game;

  @override
  void update(double dt) {
    super.update(dt);
    _updateLoadedChunks();
  }

  /// Update which chunks are loaded based on pod position
  void _updateLoadedChunks() {
    final podPos = _game.pod.position;
    final podChunkX = (podPos.x / GameConstants.chunkSize).floor();
    final podChunkY = (podPos.y / GameConstants.chunkSize).floor();

    // Determine which chunks should be loaded
    final neededChunks = <String>{};
    for (int dy = -GameConstants.chunkLoadRadius;
        dy <= GameConstants.chunkLoadRadius;
        dy++) {
      for (int dx = -GameConstants.chunkLoadRadius;
          dx <= GameConstants.chunkLoadRadius;
          dx++) {
        final cx = podChunkX + dx;
        final cy = podChunkY + dy;
        neededChunks.add(_chunkKey(cx, cy));
      }
    }

    // Load new chunks
    for (final key in neededChunks) {
      if (!_activeChunks.containsKey(key)) {
        _loadChunk(key);
      }
    }

    // Unload distant chunks
    final chunksToRemove = <String>[];
    for (final entry in _activeChunks.entries) {
      if (!neededChunks.contains(entry.key)) {
        final parts = entry.key.split(',');
        final cx = int.parse(parts[0]);
        final cy = int.parse(parts[1]);
        final dist = (cx - podChunkX).abs() + (cy - podChunkY).abs();
        if (dist > GameConstants.chunkUnloadRadius) {
          chunksToRemove.add(entry.key);
        }
      }
    }

    for (final key in chunksToRemove) {
      _unloadChunk(key);
    }

    // Rebuild dirty chunks
    for (final chunk in _activeChunks.values) {
      if (chunk.isDirty) {
        chunk.rebuild();
        chunk.rebuildCollision();
      }
    }
  }

  /// Load a chunk by key
  void _loadChunk(String key) {
    final parts = key.split(',');
    final cx = int.parse(parts[0]);
    final cy = int.parse(parts[1]);

    // Get or generate chunk data
    List<List<TerrainCell>> cellData;
    if (_chunkDataCache.containsKey(key)) {
      cellData = _chunkDataCache.remove(key)!;
    } else {
      cellData = worldGenerator.generateChunk(cx, cy);
    }

    final chunk = Chunk(chunkX: cx, chunkY: cy, cells: cellData);
    _activeChunks[key] = chunk;

    // Add to the game world
    _game.world.add(chunk);
  }

  /// Unload a chunk by key (cache data, remove component)
  void _unloadChunk(String key) {
    final chunk = _activeChunks.remove(key);
    if (chunk != null) {
      // Cache the cell data for quick reload
      _chunkDataCache[key] = chunk.cells;
      chunk.removeFromParent();
    }
  }

  /// Remove a cell at world grid coordinates
  void removeCell(int gridX, int gridY) {
    final chunkX = gridX >= 0
        ? gridX ~/ GameConstants.chunkSize
        : -(((-gridX - 1) ~/ GameConstants.chunkSize) + 1);
    final chunkY = gridY >= 0
        ? gridY ~/ GameConstants.chunkSize
        : -(((-gridY - 1) ~/ GameConstants.chunkSize) + 1);

    final localX = ((gridX % GameConstants.chunkSize) +
            GameConstants.chunkSize) %
        GameConstants.chunkSize;
    final localY = ((gridY % GameConstants.chunkSize) +
            GameConstants.chunkSize) %
        GameConstants.chunkSize;

    final key = _chunkKey(chunkX, chunkY);
    final chunk = _activeChunks[key];
    if (chunk != null) {
      chunk.removeCell(localX, localY);
    } else {
      // Modify cached data
      final cached = _chunkDataCache[key];
      if (cached != null &&
          localY < cached.length &&
          localX < cached[0].length) {
        cached[localY][localX].type = CellType.empty;
        cached[localY][localX].density = 0.0;
      }
    }
  }

  /// Get cell type at world grid coordinates
  int getCellType(int gridX, int gridY) {
    final chunkX = gridX >= 0
        ? gridX ~/ GameConstants.chunkSize
        : -(((-gridX - 1) ~/ GameConstants.chunkSize) + 1);
    final chunkY = gridY >= 0
        ? gridY ~/ GameConstants.chunkSize
        : -(((-gridY - 1) ~/ GameConstants.chunkSize) + 1);

    final localX = ((gridX % GameConstants.chunkSize) +
            GameConstants.chunkSize) %
        GameConstants.chunkSize;
    final localY = ((gridY % GameConstants.chunkSize) +
            GameConstants.chunkSize) %
        GameConstants.chunkSize;

    final key = _chunkKey(chunkX, chunkY);
    final chunk = _activeChunks[key];
    if (chunk != null) {
      final cell = chunk.getCell(localX, localY);
      return cell?.type.index ?? CellType.empty.index;
    }

    // Check cached data
    final cached = _chunkDataCache[key];
    if (cached != null &&
        localY < cached.length &&
        localX < cached[0].length) {
      return cached[localY][localX].type.index;
    }

    return CellType.empty.index;
  }

  /// Get the terrain cell at world grid coordinates
  TerrainCell? getTerrainCell(int gridX, int gridY) {
    final chunkX = gridX >= 0
        ? gridX ~/ GameConstants.chunkSize
        : -(((-gridX - 1) ~/ GameConstants.chunkSize) + 1);
    final chunkY = gridY >= 0
        ? gridY ~/ GameConstants.chunkSize
        : -(((-gridY - 1) ~/ GameConstants.chunkSize) + 1);

    final localX = ((gridX % GameConstants.chunkSize) +
            GameConstants.chunkSize) %
        GameConstants.chunkSize;
    final localY = ((gridY % GameConstants.chunkSize) +
            GameConstants.chunkSize) %
        GameConstants.chunkSize;

    final key = _chunkKey(chunkX, chunkY);
    final chunk = _activeChunks[key];
    if (chunk != null) {
      return chunk.getCell(localX, localY);
    }
    return null;
  }

  /// Get all active chunks (for rendering)
  Iterable<Chunk> get activeChunks => _activeChunks.values;

  /// Get chunk at chunk coordinates
  Chunk? getChunk(int chunkX, int chunkY) {
    return _activeChunks[_chunkKey(chunkX, chunkY)];
  }

  String _chunkKey(int cx, int cy) => '$cx,$cy';
}
