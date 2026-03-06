import 'dart:collection';

import 'package:flame/components.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/chunk.dart';
import 'package:motherlode/world/marching_squares.dart';
import 'package:motherlode/world/sdf_primitives.dart';
import 'package:motherlode/world/stratigraphy.dart';
import 'package:motherlode/world/terrain_cell.dart';
import 'package:motherlode/world/world_generator.dart';

/// Manages chunk loading/unloading based on pod position
class ChunkManager extends Component with HasGameReference<MotherlodeGame> {
  final WorldGenerator worldGenerator;
  final MotherlodeGame _game;

  /// Stratigraphy instance for geological coloring (from GenesisPipeline).
  /// Null when using legacy WorldGenerator (falls back to depth-based colors).
  Stratigraphy? stratigraphy;

  // Active chunks keyed by "chunkX,chunkY" string
  final Map<String, Chunk> _activeChunks = {};

  // LRU cache of generated but unloaded chunk data.
  // LinkedHashMap preserves access order; oldest entries are evicted first.
  static const int _maxCacheSize = 200;
  final LinkedHashMap<String, List<List<TerrainCell>>> _chunkDataCache =
      LinkedHashMap<String, List<List<TerrainCell>>>();

  // Keys of chunks that have been modified since genesis (drilled, etc.)
  final Set<String> _modifiedChunks = {};

  // Throttle: max chunks to load per frame to avoid jank
  static const int _maxChunkLoadsPerFrame = 2;

  ChunkManager({
    required this.worldGenerator,
    required MotherlodeGame game,
  }) : _game = game;

  /// Pre-populate the chunk data cache with Genesis pipeline results.
  /// Called before forceLoadAroundSpawn() so chunks use pre-generated data.
  void preloadChunkData(Map<String, List<List<TerrainCell>>> genesisChunks) {
    for (final entry in genesisChunks.entries) {
      _putCache(entry.key, entry.value);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_game.pod.isMounted) return;
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

    // Load new chunks (throttled to avoid frame jank)
    int chunksLoaded = 0;
    for (final key in neededChunks) {
      if (!_activeChunks.containsKey(key)) {
        if (chunksLoaded >= _maxChunkLoadsPerFrame) break;
        _loadChunk(key);
        chunksLoaded++;
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

    // Rebuild dirty chunks with border data from neighbors
    for (final chunk in _activeChunks.values) {
      if (chunk.isDirty) {
        _updateBorderData(chunk);
        chunk.rebuild();
        chunk.rebuildCollision();
      }
    }
  }

  /// Gather border data from neighbor chunks and apply to a chunk
  void _updateBorderData(Chunk chunk) {
    final topChunk = _activeChunks[_chunkKey(chunk.chunkX, chunk.chunkY - 1)];
    final bottomChunk =
        _activeChunks[_chunkKey(chunk.chunkX, chunk.chunkY + 1)];
    final leftChunk = _activeChunks[_chunkKey(chunk.chunkX - 1, chunk.chunkY)];
    final rightChunk = _activeChunks[_chunkKey(chunk.chunkX + 1, chunk.chunkY)];

    // Also check cached chunk data for unloaded neighbors
    List<TerrainCell>? topRow = topChunk?.bottomRow;
    List<TerrainCell>? bottomRow = bottomChunk?.topRow;
    List<TerrainCell>? leftCol = leftChunk?.rightCol;
    List<TerrainCell>? rightCol = rightChunk?.leftCol;

    // Fall back to cached data if neighbor chunk isn't active
    topRow ??= _getBorderFromCache(chunk.chunkX, chunk.chunkY - 1, 'bottom');
    bottomRow ??= _getBorderFromCache(chunk.chunkX, chunk.chunkY + 1, 'top');
    leftCol ??= _getBorderFromCache(chunk.chunkX - 1, chunk.chunkY, 'right');
    rightCol ??= _getBorderFromCache(chunk.chunkX + 1, chunk.chunkY, 'left');

    // Synthesize empty borders when no neighbor data is available
    const size = GameConstants.chunkSize;

    // Top: sky above surface chunk
    if (topRow == null && chunk.chunkY == 0) {
      topRow = List.generate(
        size,
        (_) => TerrainCell(type: CellType.empty, sdf: 1.0),
      );
    }

    // Bottom: assume solid terrain continues below
    bottomRow ??= List.generate(
      size,
      (_) => TerrainCell(type: CellType.rock, sdf: -1.0),
    );

    // Left/Right: assume solid terrain continues laterally
    leftCol ??= List.generate(
      size,
      (_) => TerrainCell(type: CellType.rock, sdf: -1.0),
    );
    rightCol ??= List.generate(
      size,
      (_) => TerrainCell(type: CellType.rock, sdf: -1.0),
    );

    chunk.setBorderData(ChunkBorderData(
      topRow: topRow,
      bottomRow: bottomRow,
      leftCol: leftCol,
      rightCol: rightCol,
    ));
  }

  /// Try to get a border row/col from cached (unloaded) chunk data
  List<TerrainCell>? _getBorderFromCache(int chunkX, int chunkY, String side) {
    final key = _chunkKey(chunkX, chunkY);
    final cached = _chunkDataCache[key];
    if (cached == null) return null;
    _touchCache(key);

    const size = GameConstants.chunkSize;
    switch (side) {
      case 'top':
        return cached[0];
      case 'bottom':
        return cached[size - 1];
      case 'left':
        return List.generate(size, (y) => cached[y][0]);
      case 'right':
        return List.generate(size, (y) => cached[y][size - 1]);
      default:
        return null;
    }
  }

  /// Load a chunk by key
  void _loadChunk(String key) {
    final parts = key.split(',');
    final cx = int.parse(parts[0]);
    final cy = int.parse(parts[1]);

    // Get or generate chunk data (remove from cache since it's now active)
    List<List<TerrainCell>> cellData;
    final cached = _chunkDataCache.remove(key);
    if (cached != null) {
      cellData = cached;
    } else {
      cellData = worldGenerator.generateChunk(cx, cy);
    }

    final chunk = Chunk(chunkX: cx, chunkY: cy, cells: cellData);
    chunk.stratigraphy = stratigraphy;
    _activeChunks[key] = chunk;

    // Set border data before adding to world (so collision is correct on first build)
    _updateBorderData(chunk);

    // Add to the game world
    _game.world.add(chunk);

    // When a new chunk loads, mark adjacent chunks dirty so they can
    // regenerate boundary edges using this chunk's data
    _markNeighborsDirty(cx, cy);
  }

  /// Mark neighbor chunks as dirty so they rebuild boundary collision
  void _markNeighborsDirty(int cx, int cy) {
    for (final offset in [
      [0, -1],
      [0, 1],
      [-1, 0],
      [1, 0],
    ]) {
      final neighbor = _activeChunks[_chunkKey(cx + offset[0], cy + offset[1])];
      if (neighbor != null && !neighbor.isDirty) {
        neighbor.markDirty();
      }
    }
  }

  /// Unload a chunk by key (cache data, remove component)
  void _unloadChunk(String key) {
    final chunk = _activeChunks.remove(key);
    if (chunk != null) {
      // Cache the cell data for quick reload (LRU-managed)
      _putCache(key, chunk.cells);
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

    final localX =
        ((gridX % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;
    final localY =
        ((gridY % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;

    final key = _chunkKey(chunkX, chunkY);
    _modifiedChunks.add(key);
    final chunk = _activeChunks[key];
    if (chunk != null) {
      chunk.removeCell(localX, localY);
      // Also mark neighbors dirty if the removed cell is on a border
      if (localX == 0 ||
          localX == GameConstants.chunkSize - 1 ||
          localY == 0 ||
          localY == GameConstants.chunkSize - 1) {
        _markNeighborsDirty(chunkX, chunkY);
      }
    } else {
      // Modify cached data
      final cached = _chunkDataCache[key];
      if (cached != null &&
          localY < cached.length &&
          localX < cached[0].length) {
        cached[localY][localX].type = CellType.empty;
        cached[localY][localX].sdf = 0.5; // Positive = air
      }
    }
  }

  /// Mark a cell's chunk as dirty (SDF was modified externally).
  /// Does not clear the cell -- just triggers visual/physics rebuild.
  void markCellDirty(int gridX, int gridY) {
    final chunkX = gridX >= 0
        ? gridX ~/ GameConstants.chunkSize
        : -(((-gridX - 1) ~/ GameConstants.chunkSize) + 1);
    final chunkY = gridY >= 0
        ? gridY ~/ GameConstants.chunkSize
        : -(((-gridY - 1) ~/ GameConstants.chunkSize) + 1);

    final localX =
        ((gridX % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;
    final localY =
        ((gridY % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;

    final key = _chunkKey(chunkX, chunkY);
    final chunk = _activeChunks[key];
    if (chunk != null) {
      chunk.markDirty();
      if (localX == 0 ||
          localX == GameConstants.chunkSize - 1 ||
          localY == 0 ||
          localY == GameConstants.chunkSize - 1) {
        _markNeighborsDirty(chunkX, chunkY);
      }
    }
  }

  /// Drill a smooth round hole at world coordinates using SDF sphere subtraction.
  ///
  /// Carves a circle of [radius] centered at ([worldX], [worldY]) from the
  /// terrain. Affects all cells within range across chunk boundaries.
  /// Uses [SdfPrimitives.smoothSubtract] for natural rounded edges.
  ///
  /// [smoothK] controls edge smoothness (larger = rounder).
  ///
  /// Returns a list of modified cells as (gridX, gridY, cell) tuples,
  /// useful for ore collection checks.
  List<(int, int, TerrainCell)> drillAtWorld(
    double worldX,
    double worldY,
    double radius, {
    double smoothK = 0.3,
  }) {
    final modified = <(int, int, TerrainCell)>[];
    final margin = (radius + smoothK + 1).ceil();
    final centerGX = worldX.round();
    final centerGY = worldY.round();

    final dirtyChunks = <String>{};

    for (int dy = -margin; dy <= margin; dy++) {
      for (int dx = -margin; dx <= margin; dx++) {
        final gx = centerGX + dx;
        final gy = centerGY + dy;

        final cell = getTerrainCell(gx, gy);
        if (cell == null) continue;

        // SDF of the drill sphere at this cell
        final drillSdf = SdfPrimitives.circle(
          gx.toDouble(),
          gy.toDouble(),
          worldX,
          worldY,
          radius,
        );

        // Smooth subtraction: carve drill hole from terrain SDF
        final oldSdf = cell.sdf;
        final newSdf = SdfPrimitives.smoothSubtract(oldSdf, drillSdf, smoothK);

        if (newSdf != oldSdf) {
          cell.sdf = newSdf;

          // If cell became air (SDF >= 0), clear its type
          if (newSdf >= 0) {
            cell.type = CellType.empty;
            cell.oreType = null;
          }

          modified.add((gx, gy, cell));

          // Track which chunks need rebuild
          final chunkX = gx >= 0
              ? gx ~/ GameConstants.chunkSize
              : -(((-gx - 1) ~/ GameConstants.chunkSize) + 1);
          final chunkY = gy >= 0
              ? gy ~/ GameConstants.chunkSize
              : -(((-gy - 1) ~/ GameConstants.chunkSize) + 1);
          dirtyChunks.add(_chunkKey(chunkX, chunkY));

          // Border cells also dirty the neighbor
          final localX =
              ((gx % GameConstants.chunkSize) + GameConstants.chunkSize) %
                  GameConstants.chunkSize;
          final localY =
              ((gy % GameConstants.chunkSize) + GameConstants.chunkSize) %
                  GameConstants.chunkSize;
          if (localX == 0 ||
              localX == GameConstants.chunkSize - 1 ||
              localY == 0 ||
              localY == GameConstants.chunkSize - 1) {
            _markNeighborsDirty(chunkX, chunkY);
          }
        }
      }
    }

    // Mark all affected chunks dirty for visual/physics rebuild
    for (final key in dirtyChunks) {
      _activeChunks[key]?.markDirty();
    }
    _modifiedChunks.addAll(dirtyChunks);

    return modified;
  }

  /// Get cell type at world grid coordinates
  int getCellType(int gridX, int gridY) {
    final chunkX = gridX >= 0
        ? gridX ~/ GameConstants.chunkSize
        : -(((-gridX - 1) ~/ GameConstants.chunkSize) + 1);
    final chunkY = gridY >= 0
        ? gridY ~/ GameConstants.chunkSize
        : -(((-gridY - 1) ~/ GameConstants.chunkSize) + 1);

    final localX =
        ((gridX % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;
    final localY =
        ((gridY % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;

    final key = _chunkKey(chunkX, chunkY);
    final chunk = _activeChunks[key];
    if (chunk != null) {
      final cell = chunk.getCell(localX, localY);
      return cell?.type.index ?? CellType.empty.index;
    }

    // Check cached data (touch for LRU)
    final cached = _chunkDataCache[key];
    if (cached != null && localY < cached.length && localX < cached[0].length) {
      _touchCache(key);
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

    final localX =
        ((gridX % GameConstants.chunkSize) + GameConstants.chunkSize) %
            GameConstants.chunkSize;
    final localY =
        ((gridY % GameConstants.chunkSize) + GameConstants.chunkSize) %
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

  /// Alias for viewport culling - get an already-loaded chunk
  Chunk? getLoadedChunk(int chunkX, int chunkY) {
    return _activeChunks[_chunkKey(chunkX, chunkY)];
  }

  /// Number of currently loaded chunks
  int get loadedChunkCount => _activeChunks.length;

  /// Number of dirty chunks needing rebuild
  int get dirtyChunkCount =>
      _activeChunks.values.where((c) => c.isDirty).length;

  /// Force-load chunks around spawn point (0,0) and await their bodies.
  /// Must complete before the pod is created so collision geometry exists.
  Future<void> forceLoadAroundSpawn() async {
    final futures = <Future<void>>[];
    for (int dy = -GameConstants.chunkLoadRadius;
        dy <= GameConstants.chunkLoadRadius;
        dy++) {
      for (int dx = -GameConstants.chunkLoadRadius;
          dx <= GameConstants.chunkLoadRadius;
          dx++) {
        final key = _chunkKey(dx, dy);
        if (!_activeChunks.containsKey(key)) {
          futures.add(_loadChunkAsync(key));
        }
      }
    }
    await Future.wait(futures);

    // After all chunks are loaded, do a border-data pass and rebuild
    // so all chunks have correct boundary collision
    for (final chunk in _activeChunks.values) {
      _updateBorderData(chunk);
      chunk.markDirty();
    }
    for (final chunk in _activeChunks.values) {
      chunk.rebuild();
      chunk.rebuildCollision();
    }
  }

  /// Load a chunk and await its body creation
  Future<void> _loadChunkAsync(String key) async {
    final parts = key.split(',');
    final cx = int.parse(parts[0]);
    final cy = int.parse(parts[1]);

    List<List<TerrainCell>> cellData;
    final cached = _chunkDataCache.remove(key);
    if (cached != null) {
      cellData = cached;
    } else {
      cellData = worldGenerator.generateChunk(cx, cy);
    }

    final chunk = Chunk(chunkX: cx, chunkY: cy, cells: cellData);
    chunk.stratigraphy = stratigraphy;
    _activeChunks[key] = chunk;

    await _game.world.add(chunk);
    await chunk.loaded;
  }

  /// Export all modified chunk cell data for saving.
  ///
  /// Returns both active and cached chunks that have been modified since
  /// genesis. Unmodified chunks are skipped (they can be regenerated).
  Map<String, List<List<TerrainCell>>> exportModifiedChunks() {
    final result = <String, List<List<TerrainCell>>>{};
    for (final key in _modifiedChunks) {
      final chunk = _activeChunks[key];
      if (chunk != null) {
        result[key] = chunk.cells;
      } else if (_chunkDataCache.containsKey(key)) {
        result[key] = _chunkDataCache[key]!;
      }
    }
    return result;
  }

  /// Import previously saved modified chunks into the data cache.
  ///
  /// Called before [forceLoadAroundSpawn] so loaded chunks use saved data.
  /// Also marks imported keys as modified so subsequent saves include them.
  void importModifiedChunks(Map<String, List<List<TerrainCell>>> chunks) {
    for (final entry in chunks.entries) {
      _putCache(entry.key, entry.value);
    }
    _modifiedChunks.addAll(chunks.keys);
  }

  /// Touch a cache entry to mark it as recently used (move to end of LinkedHashMap).
  void _touchCache(String key) {
    final data = _chunkDataCache.remove(key);
    if (data != null) {
      _chunkDataCache[key] = data;
    }
  }

  /// Add data to the LRU cache, evicting oldest entries if over capacity.
  /// Modified chunks are never evicted (they contain unsaved player changes).
  void _putCache(String key, List<List<TerrainCell>> data) {
    // Remove first so re-inserting puts it at the end (most recent)
    _chunkDataCache.remove(key);
    _chunkDataCache[key] = data;
    _evictCache();
  }

  /// Evict oldest cache entries until at or below capacity.
  void _evictCache() {
    while (_chunkDataCache.length > _maxCacheSize) {
      // Find the oldest entry that is NOT modified
      String? toEvict;
      for (final key in _chunkDataCache.keys) {
        if (!_modifiedChunks.contains(key)) {
          toEvict = key;
          break;
        }
      }
      if (toEvict == null) break; // All entries are modified, can't evict
      _chunkDataCache.remove(toEvict);
    }
  }

  String _chunkKey(int cx, int cy) => '$cx,$cy';
}
