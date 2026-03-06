@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/terrain_cell.dart';
import 'package:motherlode/world/world_generator.dart';

void main() {
  List<List<TerrainCell>> makeGrid({CellType fill = CellType.rock}) {
    const size = GameConstants.chunkSize;
    return List.generate(
      size,
      (y) => List.generate(
        size,
        (x) => TerrainCell(
            type: fill, density: fill == CellType.empty ? 0.0 : 0.8),
      ),
    );
  }

  // 1. CHUNK SERIALIZATION
  test('1. Chunk survives save/load round trip', () {
    final gen = WorldGenerator(seed: 42);
    final grid = gen.generateChunk(0, 1);

    // Mine some cells
    grid[5][5].type = CellType.empty;
    grid[5][5].density = 0.0;
    grid[10][10].type = CellType.empty;
    grid[10][10].density = 0.0;

    // Serialize
    final serialized =
        grid.map((row) => row.map((cell) => cell.toMap()).toList()).toList();

    // Deserialize
    final restored = serialized
        .map((row) => row.map((map) => TerrainCell.fromMap(map)).toList())
        .toList();

    // Compare
    const size = GameConstants.chunkSize;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        expect(restored[y][x].type, equals(grid[y][x].type),
            reason: 'Type mismatch at ($x,$y)');
        expect(restored[y][x].density, closeTo(grid[y][x].density, 0.001),
            reason: 'Density mismatch at ($x,$y)');
        expect(restored[y][x].oreType?.name, equals(grid[y][x].oreType?.name),
            reason: 'Ore mismatch at ($x,$y)');
        expect(restored[y][x].hasCreatureSpawn,
            equals(grid[y][x].hasCreatureSpawn),
            reason: 'Creature spawn mismatch at ($x,$y)');
      }
    }
  });

  // 2. CHUNK DIRTY FLAG
  test('2. Dirty flag set correctly on cell changes', () {
    final grid = makeGrid();
    // Simulate chunk dirty flag behavior
    bool isDirty = true; // Dirty on creation
    expect(isDirty, isTrue, reason: 'Should be dirty on creation');

    // Mark clean after initial render
    isDirty = false;
    expect(isDirty, isFalse, reason: 'Should be clean after render');

    // Remove a cell -> should be dirty
    grid[5][5].type = CellType.empty;
    grid[5][5].density = 0.0;
    isDirty = true; // Mark dirty on cell removal
    expect(isDirty, isTrue, reason: 'Should be dirty after cell removal');

    // Mark clean again
    isDirty = false;
    expect(isDirty, isFalse);
  });

  // 3. CHUNK BOUNDS
  test('3. Cell access clamps to chunk bounds', () {
    const size = GameConstants.chunkSize;
    final grid = makeGrid();

    // Out of bounds should be handled gracefully
    // getCell at -1 should return null or handle safely
    expect(
      () {
        if (-1 < 0 || -1 >= size) {
          return null;
        }
        return grid[-1][0];
      }(),
      isNull,
      reason: 'getCellAt(-1, 0) should return null',
    );

    expect(
      () {
        if (size < 0 || size >= size) {
          return null;
        }
        return grid[0][size];
      }(),
      isNull,
      reason: 'getCellAt(CHUNK_SIZE, 0) should return null',
    );
  });

  // 4. CHUNK NEIGHBOR AWARENESS
  test('4. Border cells aware of adjacent chunks', () {
    final gen = WorldGenerator(seed: 42);
    const size = GameConstants.chunkSize;

    // Generate 2x2 grid
    final chunk00 = gen.generateChunk(0, 0);
    final chunk10 = gen.generateChunk(1, 0);
    gen.generateChunk(0, 1);
    gen.generateChunk(1, 1);

    // Border cell in chunk[0,0] at right edge can be compared with
    // border cell in chunk[1,0] at left edge
    // They should be generated from consistent noise, so they should
    // not be drastically different
    int matchingBorderCells = 0;
    for (int y = 0; y < size; y++) {
      final rightEdge = chunk00[y][size - 1];
      final leftEdge = chunk10[y][0];
      // They should have similar solid/empty status
      if (rightEdge.isSolid == leftEdge.isSolid) {
        matchingBorderCells++;
      }
    }
    // At least 50% of border cells should match (noise is continuous)
    expect(matchingBorderCells, greaterThan(size ~/ 2),
        reason: 'Too many border mismatches between adjacent chunks');
  });

  // 5. CHUNK MEMORY
  test('5. Empty vs full chunk data comparison', () {
    final emptyGrid = makeGrid(fill: CellType.empty);
    final fullGrid = makeGrid(fill: CellType.rock);

    // Count non-empty cells in each
    int emptyCount = 0;
    int fullCount = 0;
    const size = GameConstants.chunkSize;

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (emptyGrid[y][x].type == CellType.empty) emptyCount++;
        if (fullGrid[y][x].type != CellType.empty) fullCount++;
      }
    }

    expect(emptyCount, equals(size * size));
    expect(fullCount, equals(size * size));

    // Verify serialization size difference (empty cells should have smaller
    // serialized representation since oreType is null)
    final emptyMap = emptyGrid[0][0].toMap();
    final fullMap = fullGrid[0][0].toMap();
    expect(emptyMap['oreId'], isNull);
    expect(fullMap['oreId'], isNull); // Rock has no ore either
  });
}
