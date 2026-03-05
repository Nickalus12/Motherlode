import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/marching_squares.dart';
import 'package:motherlode/world/stratigraphy.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// A 32x32 cell chunk of terrain, loaded/unloaded based on pod depth
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
  }

  /// Mark chunk as clean with a cached picture
  void markClean(ui.Picture picture) {
    _isDirty = false;
    _cachedPicture = picture;
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

  /// Get the left column of cells (for neighbor border data)
  List<TerrainCell> get leftCol =>
      List.generate(GameConstants.chunkSize, (y) => cells[y][0]);

  /// Get the right column of cells (for neighbor border data)
  List<TerrainCell> get rightCol => List.generate(
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

  void _buildCollisionShapes(Body body) {
    // Generate collision edges from the mesh result
    if (_isDirty) rebuild();

    for (final segment in _meshResult.collisionSegments) {
      if (segment.length < 2) continue;

      // Create edge chain from segment vertices
      final vertices = segment.map((v) => Vector2(v.dx, v.dy)).toList();

      if (vertices.length == 2) {
        final edgeShape = EdgeShape()..set(vertices[0], vertices[1]);
        body.createFixture(FixtureDef(edgeShape)
          ..friction = 0.3
          ..restitution = 0.0);
      } else {
        final chainShape = ChainShape()..createChain(vertices);
        body.createFixture(FixtureDef(chainShape)
          ..friction = 0.3
          ..restitution = 0.0);
      }
    }
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
      'cells': cells
          .map((row) => row.map((cell) => cell.toMap()).toList())
          .toList(),
    };
  }
}
