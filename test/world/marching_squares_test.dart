import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/world/marching_squares.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Helper to create a grid of TerrainCells with given SDF values.
List<List<TerrainCell>> _makeGrid(int size, double defaultSdf) {
  return List.generate(
    size,
    (y) => List.generate(
      size,
      (x) => TerrainCell(
          type: defaultSdf < 0 ? CellType.dirt : CellType.empty,
          sdf: defaultSdf),
    ),
  );
}

/// Set a single cell in the grid.
void _setCell(
    List<List<TerrainCell>> grid, int x, int y, CellType type, double sdf) {
  grid[y][x] = TerrainCell(type: type, sdf: sdf);
}

void main() {
  group('MarchingSquaresResult', () {
    test('empty grid produces no polygons', () {
      // All cells have positive SDF (air)
      final grid = _makeGrid(4, 1.0);
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      expect(result.polygons, isEmpty);
      expect(result.collisionSegments, isEmpty);
    });

    test('fully solid grid produces polygons with isInterior=true', () {
      // All cells have negative SDF (solid)
      final grid = _makeGrid(4, -3.0);
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      expect(result.polygons, isNotEmpty);
      // Deep interior cells should have isInterior = true
      final interiorPolys = result.polygons.where((p) => p.isInterior).toList();
      expect(interiorPolys, isNotEmpty);
    });

    test('single solid cell produces boundary polygons', () {
      // Small grid with one solid cell surrounded by air
      final grid = _makeGrid(4, 1.0);
      _setCell(grid, 1, 1, CellType.dirt, -2.0);
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      expect(result.polygons, isNotEmpty);
      // Should have collision edges for the boundary
      expect(result.collisionSegments, isNotEmpty);
    });

    test('ore cells are flagged as isOre', () {
      final grid = _makeGrid(4, -2.0);
      // Place an ore cell
      grid[1][1] = TerrainCell(
        type: CellType.ore,
        sdf: -2.0,
        oreType: OreRegistry.ironium,
      );
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      final orePolys = result.polygons.where((p) => p.isOre).toList();
      expect(orePolys, isNotEmpty);
    });

    test('lava cells are flagged as isLava', () {
      final grid = _makeGrid(4, -2.0);
      grid[1][1] = TerrainCell(type: CellType.lava, sdf: -2.0);
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      final lavaPolys = result.polygons.where((p) => p.isLava).toList();
      expect(lavaPolys, isNotEmpty);
    });

    test('case 15 (all solid) produces no collision segments for that subcell',
        () {
      // Deep solid region
      final grid = _makeGrid(4, -5.0);
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      // Interior cells (case 15) have no collision edges
      // All polys should be interior with no collision segments from them
      for (final poly in result.polygons) {
        if (poly.isInterior) {
          // Interior polygons don't contribute collision segments
          // (collision segments come from boundary cases only)
        }
      }
      // The total collision segments should be empty for a fully-solid
      // interior grid (only edges at the chunk boundary)
      // With no borders, range is 0 to size-2, all deep interior
      expect(result.collisionSegments, isEmpty);
    });
  });

  group('ChunkBorderData', () {
    test('empty border data is const', () {
      const border = ChunkBorderData.empty;
      expect(border.topRow, isNull);
      expect(border.bottomRow, isNull);
      expect(border.leftCol, isNull);
      expect(border.rightCol, isNull);
    });

    test('border data extends marching squares range', () {
      final grid = _makeGrid(4, -2.0);
      final topRow =
          List.generate(4, (_) => TerrainCell(sdf: -2.0, type: CellType.dirt));
      final borders = ChunkBorderData(topRow: topRow);

      final resultWithBorders = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
        borders: borders,
      );
      final resultWithout = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      // With top border, the mesh extends into y=-1 row, producing more polys
      expect(resultWithBorders.polygons.length,
          greaterThanOrEqualTo(resultWithout.polygons.length));
    });
  });

  group('MarchingSquaresPoly', () {
    test('has correct default values', () {
      final poly = MarchingSquaresPoly(
        path: Path(),
        fillColor: const Color(0xFF000000),
        strokeColor: const Color(0xFF111111),
      );
      expect(poly.isInterior, isFalse);
      expect(poly.isOre, isFalse);
      expect(poly.isLava, isFalse);
    });
  });

  group('Edge interpolation behavior', () {
    test('boundary between solid and air produces collision segments', () {
      // Left half solid, right half air
      final grid = _makeGrid(4, 1.0);
      for (int y = 0; y < 4; y++) {
        _setCell(grid, 0, y, CellType.dirt, -2.0);
        _setCell(grid, 1, y, CellType.dirt, -2.0);
      }
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      expect(result.collisionSegments, isNotEmpty);
    });

    test('gradient SDF produces smooth interpolated edges', () {
      // Create a grid with a gradient: solid on left, air on right
      final grid = _makeGrid(4, 0.0);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final sdf = (x - 1.5); // Negative on left, positive on right
          final type = sdf < 0 ? CellType.dirt : CellType.empty;
          _setCell(grid, x, y, type, sdf);
        }
      }
      final result = MarchingSquares.generateMesh(
        cells: grid,
        chunkX: 0,
        chunkY: 0,
      );
      expect(result.polygons, isNotEmpty);
      expect(result.collisionSegments, isNotEmpty);
    });
  });
}
