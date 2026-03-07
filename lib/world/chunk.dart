import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/marching_squares.dart';
import 'package:motherlode/world/stratigraphy.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// A 32x32 cell chunk of terrain, loaded/unloaded based on robot depth
class Chunk extends BodyComponent {
  final int chunkX;
  final int chunkY;
  final List<List<TerrainCell>> cells;

  bool _isDirty = true;
  bool _physicsBuilt = false;
  late MarchingSquaresResult _meshResult;

  /// Border data from neighboring chunks (set by ChunkManager)
  ChunkBorderData? _borderData;

  /// Stratigraphy reference for geological coloring (set by ChunkManager).
  /// Null when using the legacy WorldGenerator (falls back to depth colors).
  Stratigraphy? stratigraphy;

  /// Cached rendered picture for this chunk (null when dirty)
  ui.Picture? _cachedPicture;

  Chunk({
    required this.chunkX,
    required this.chunkY,
    required this.cells,
  });

  /// World-space position of the top-left corner in pixels
  Vector2 get worldPosition => Vector2(
        chunkX * GameConstants.chunkPixelSize,
        chunkY * GameConstants.chunkPixelSize,
      );

  /// World-space position in Forge2D meters
  Vector2 get worldPositionMeters => Vector2(
        chunkX * GameConstants.chunkSize.toDouble(),
        chunkY * GameConstants.chunkSize.toDouble(),
      );

  /// Whether this chunk needs a visual/physics rebuild
  bool get isDirty => _isDirty;

  /// Cached picture for skip-rendering clean chunks
  ui.Picture? get cachedPicture => _cachedPicture;

  /// Mark chunk for rebuild (after cell removal, etc.)
  void markDirty() {
    _isDirty = true;
    _cachedPicture = null;
    _leftColCache = null;
    _rightColCache = null;
  }

  /// Mark chunk as clean with a cached picture
  void markClean(ui.Picture picture) {
    _isDirty = false;
    _cachedPicture = picture;
  }

  /// Mark chunk as clean without a cached picture (used by GPU shader path).
  void clearDirty() {
    _isDirty = false;
  }

  /// Set border data from neighboring chunks
  void setBorderData(ChunkBorderData data) {
    if (_borderData != data) {
      _borderData = data;
      // Only mark dirty if we didn't have border data before
      // (first time neighbors provide data)
    }
  }

  /// Get cell at local chunk coordinates
  TerrainCell? getCell(int localX, int localY) {
    if (localX < 0 ||
        localX >= GameConstants.chunkSize ||
        localY < 0 ||
        localY >= GameConstants.chunkSize) {
      return null;
    }
    return cells[localY][localX];
  }

  /// Get the top row of cells (for neighbor border data)
  List<TerrainCell> get topRow => cells[0];

  /// Get the bottom row of cells (for neighbor border data)
  List<TerrainCell> get bottomRow => cells[GameConstants.chunkSize - 1];

  /// Get the left column of cells (for neighbor border data).
  /// Cached to avoid repeated List.generate allocations during border updates.
  List<TerrainCell>? _leftColCache;
  List<TerrainCell> get leftCol => _leftColCache ??=
      List.generate(GameConstants.chunkSize, (y) => cells[y][0]);

  /// Get the right column of cells (for neighbor border data).
  List<TerrainCell>? _rightColCache;
  List<TerrainCell> get rightCol => _rightColCache ??= List.generate(
      GameConstants.chunkSize, (y) => cells[y][GameConstants.chunkSize - 1]);

  /// Remove a cell (set to empty) and mark dirty
  void removeCell(int localX, int localY) {
    if (localX < 0 ||
        localX >= GameConstants.chunkSize ||
        localY < 0 ||
        localY >= GameConstants.chunkSize) {
      return;
    }
    cells[localY][localX].type = CellType.empty;
    cells[localY][localX].sdf = 0.5; // Positive = air
    cells[localY][localX].oreType = null;
    _isDirty = true;
  }

  /// Build or rebuild the marching squares mesh and physics body
  void rebuild() {
    _meshResult = MarchingSquares.generateMesh(
      cells: cells,
      chunkX: chunkX,
      chunkY: chunkY,
      borders: _borderData,
      stratigraphy: stratigraphy,
    );
    _isDirty = false;
    _cachedPicture = null;
  }

  /// Get the mesh result for rendering
  MarchingSquaresResult get meshResult {
    if (_isDirty) rebuild();
    return _meshResult;
  }

  @override
  Body createBody() {
    // Create a static body at the chunk's world position
    final bodyDef = BodyDef(
      type: BodyType.static,
      position: worldPositionMeters,
    );

    final body = world.createBody(bodyDef);

    // Build collision shapes from marching squares vertex data
    _buildCollisionShapes(body);
    _physicsBuilt = true;

    return body;
  }

  /// Rebuild collision shapes after terrain modification
  void rebuildCollision() {
    if (!_physicsBuilt) return;

    // Remove all existing fixtures
    while (body.fixtures.isNotEmpty) {
      body.destroyFixture(body.fixtures.first);
    }

    _buildCollisionShapes(body);
  }

  /// Fast collision-only rebuild using base-resolution marching squares.
  /// Skips visual polygon generation (2x subdivision, colors, etc.)
  /// for much faster response during drilling.
  void rebuildCollisionOnly() {
    if (!_physicsBuilt) return;

    // Remove all existing fixtures
    while (body.fixtures.isNotEmpty) {
      body.destroyFixture(body.fixtures.first);
    }

    // Generate collision edges at base resolution (no subdivision)
    final segments = MarchingSquares.generateCollisionOnly(
      cells: cells,
      borders: _borderData,
    );

    final chains = _mergeSegments(segments);

    for (final chain in chains) {
      if (chain.length < 2) continue;
      final vertices = chain.map((v) => Vector2(v.dx, v.dy)).toList();
      if (vertices.length == 2) {
        final edgeShape = EdgeShape()..set(vertices[0], vertices[1]);
        body.createFixture(FixtureDef(edgeShape)
          ..friction = 0.3
          ..restitution = 0.0
          ..filter.categoryBits = GameConstants.collisionCategoryTerrain
          ..filter.maskBits = GameConstants.collisionMaskTerrain);
      } else {
        final chainShape = ChainShape()..createChain(vertices);
        body.createFixture(FixtureDef(chainShape)
          ..friction = 0.3
          ..restitution = 0.0
          ..filter.categoryBits = GameConstants.collisionCategoryTerrain
          ..filter.maskBits = GameConstants.collisionMaskTerrain);
      }
    }
  }

  void _buildCollisionShapes(Body body) {
    // Generate collision edges from the mesh result
    if (_isDirty) rebuild();

    // Merge adjacent segments that share endpoints into longer chains.
    // Individual EdgeShapes have "ghost vertex" problems in Forge2D —
    // box shapes can catch on the join between two EdgeShapes and get
    // deflected downward, causing fall-through. ChainShapes handle
    // internal vertices smoothly.
    final chains = _mergeSegments(_meshResult.collisionSegments);

    for (final chain in chains) {
      if (chain.length < 2) continue;

      final vertices = chain.map((v) => Vector2(v.dx, v.dy)).toList();

      if (vertices.length == 2) {
        final edgeShape = EdgeShape()..set(vertices[0], vertices[1]);
        body.createFixture(FixtureDef(edgeShape)
          ..friction = 0.3
          ..restitution = 0.0
          ..filter.categoryBits = GameConstants.collisionCategoryTerrain
          ..filter.maskBits = GameConstants.collisionMaskTerrain);
      } else {
        final chainShape = ChainShape()..createChain(vertices);
        body.createFixture(FixtureDef(chainShape)
          ..friction = 0.3
          ..restitution = 0.0
          ..filter.categoryBits = GameConstants.collisionCategoryTerrain
          ..filter.maskBits = GameConstants.collisionMaskTerrain);
      }
    }
  }

  /// Merge segments that share endpoints into longer chains.
  /// Uses a spatial hash on endpoints (quantized to 4 decimal places)
  /// for O(n) merging instead of O(n²) brute force.
  static List<List<Offset>> _mergeSegments(List<List<Offset>> segments) {
    if (segments.isEmpty) return segments;

    // Tolerance for considering two points as the same vertex
    const quantize = 10000.0; // 4 decimal places

    String ptKey(Offset p) =>
        '${(p.dx * quantize).round()},${(p.dy * quantize).round()}';

    // Build adjacency: map each endpoint to the segment indices that touch it
    final endpointToSegments = <String, List<int>>{};
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.length < 2) continue;
      final startKey = ptKey(seg.first);
      final endKey = ptKey(seg.last);
      (endpointToSegments[startKey] ??= []).add(i);
      (endpointToSegments[endKey] ??= []).add(i);
    }

    final used = List.filled(segments.length, false);
    final result = <List<Offset>>[];

    for (int i = 0; i < segments.length; i++) {
      if (used[i] || segments[i].length < 2) continue;

      // Start a new chain from this segment
      used[i] = true;
      final chain = List<Offset>.from(segments[i]);

      // Extend forward (from chain.last)
      bool extended = true;
      while (extended) {
        extended = false;
        final tailKey = ptKey(chain.last);
        final neighbors = endpointToSegments[tailKey];
        if (neighbors == null) break;
        for (final j in neighbors) {
          if (used[j]) continue;
          final seg = segments[j];
          if (seg.length < 2) continue;
          if (ptKey(seg.first) == tailKey) {
            // seg starts where chain ends — append seg (skip first point)
            used[j] = true;
            chain.addAll(seg.skip(1));
            extended = true;
            break;
          } else if (ptKey(seg.last) == tailKey) {
            // seg ends where chain ends — append reversed seg (skip last point)
            used[j] = true;
            chain.addAll(seg.reversed.skip(1));
            extended = true;
            break;
          }
        }
      }

      // Extend backward (from chain.first)
      extended = true;
      while (extended) {
        extended = false;
        final headKey = ptKey(chain.first);
        final neighbors = endpointToSegments[headKey];
        if (neighbors == null) break;
        for (final j in neighbors) {
          if (used[j]) continue;
          final seg = segments[j];
          if (seg.length < 2) continue;
          if (ptKey(seg.last) == headKey) {
            // seg ends where chain starts — prepend seg (skip last point)
            used[j] = true;
            chain.insertAll(0, seg.take(seg.length - 1));
            extended = true;
            break;
          } else if (ptKey(seg.first) == headKey) {
            // seg starts where chain starts — prepend reversed seg (skip first)
            used[j] = true;
            final reversed = seg.reversed.toList();
            chain.insertAll(0, reversed.take(reversed.length - 1));
            extended = true;
            break;
          }
        }
      }

      result.add(chain);
    }

    return result;
  }

  @override
  void render(ui.Canvas canvas) {
    // Visual rendering handled by TerrainRenderer
  }

  /// Count solid cells in this chunk
  int get solidCellCount {
    int count = 0;
    for (final row in cells) {
      for (final cell in row) {
        if (cell.isSolid) count++;
      }
    }
    return count;
  }

  /// Serialize chunk data for save system
  Map<String, dynamic> toMap() {
    return {
      'cx': chunkX,
      'cy': chunkY,
      'cells':
          cells.map((row) => row.map((cell) => cell.toMap()).toList()).toList(),
    };
  }
}
