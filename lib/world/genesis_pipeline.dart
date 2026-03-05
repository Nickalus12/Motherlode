import 'dart:math';
import 'dart:typed_data';

import 'package:motherlode/data/creature_definitions.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/utils/noise_utils.dart';
import 'package:motherlode/world/biome.dart';
import 'package:motherlode/world/hydraulic_erosion.dart';
import 'package:motherlode/world/reaction_diffusion.dart';
import 'package:motherlode/world/sdf_primitives.dart';
import 'package:motherlode/world/stratigraphy.dart';
import 'package:motherlode/world/terrain_cell.dart';
import 'package:motherlode/world/world_generator.dart';

/// Named phases of the Genesis world-generation sequence.
///
/// Each phase corresponds to a geological process visualized on the
/// cinematic load screen (Task #6) and executed here.
enum GenesisPhase {
  tectonicFormation, // Phase 1: Base SDF terrain from noise + stratigraphy
  volcanicIntrusion, // Phase 2: Magma intrusions via SDF ops
  mineralSeeding,    // Phase 3: Reaction-diffusion ore placement
  waterTableBirth,   // Phase 4: Fluid layer population
  greatErosion,      // Phase 5: Hydraulic erosion (6 isolates)
  caveNetworks,      // Phase 6: Cave refinement and smoothing
  oreMaturation,     // Phase 7: Final ore distribution pass
  surfaceWeathering, // Phase 8: Surface detail and contour
  worldReady,        // Phase 9: Complete
}

/// Progress callback for the Genesis cinematic load screen.
///
/// [phase] is the current generation phase.
/// [progress] is 0.0-1.0 within that phase.
typedef GenesisProgressCallback = void Function(
  GenesisPhase phase,
  double progress,
);

/// Per-phase timing data for profiling.
class PhaseTimings {
  final Map<GenesisPhase, int> _durations = {};

  void record(GenesisPhase phase, int milliseconds) {
    _durations[phase] = milliseconds;
  }

  int operator [](GenesisPhase phase) => _durations[phase] ?? 0;

  int get totalMs => _durations.values.fold(0, (a, b) => a + b);

  @override
  String toString() {
    final buf = StringBuffer('Genesis Timings (${totalMs}ms total):\n');
    for (final phase in GenesisPhase.values) {
      final ms = _durations[phase];
      if (ms != null) {
        buf.writeln('  ${GenesisPipeline.phaseLabel(phase)}: ${ms}ms');
      }
    }
    return buf.toString();
  }
}

/// Orchestrates the full Genesis world-generation pipeline.
///
/// All subsystems (SDF terrain, stratigraphy, hydraulic erosion,
/// reaction-diffusion ores) plug into this pipeline. Each phase runs
/// in sequence, reporting progress for the cinematic load screen and
/// yielding to the UI thread between phases.
///
/// ```dart
/// final pipeline = GenesisPipeline(
///   seed: 42,
///   onProgress: (phase, progress) => loadScreen.update(phase, progress),
/// );
/// final result = await pipeline.generateWorld(
///   chunkRadiusX: 10,
///   chunkRadiusY: 16,
/// );
/// print(result.timings); // profiling output
/// ```
class GenesisPipeline {
  final int seed;
  final Stratigraphy stratigraphy;
  final GenesisProgressCallback? onProgress;

  // Future subsystem references (plugged in during Task #7):
  // ErosionWorkerPool? erosionPool;
  // GrayScottSimulation? reactionDiffusion;

  GenesisPipeline({
    required this.seed,
    this.onProgress,
  }) : stratigraphy = Stratigraphy(seed: seed);

  /// Generate the full world terrain for a rectangular region of chunks.
  ///
  /// Returns a [GenesisResult] containing the chunk map and phase timings.
  /// Chunk coordinates range from -[chunkRadiusX] to +[chunkRadiusX]
  /// horizontally and 0 to +[chunkRadiusY] vertically (downward = deeper).
  Future<GenesisResult> generateWorld({
    required int chunkRadiusX,
    required int chunkRadiusY,
  }) async {
    final chunks = <String, List<List<TerrainCell>>>{};
    final timings = PhaseTimings();

    // Run each phase with timing, yielding to UI thread between phases.
    await _runPhase(GenesisPhase.tectonicFormation, timings, () =>
        _phaseTectonicFormation(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.volcanicIntrusion, timings, () =>
        _phaseVolcanicIntrusion(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.mineralSeeding, timings, () =>
        _phaseMineralSeeding(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.waterTableBirth, timings, () =>
        _phaseWaterTableBirth(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.greatErosion, timings, () =>
        _phaseGreatErosion(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.caveNetworks, timings, () =>
        _phaseCaveNetworks(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.oreMaturation, timings, () =>
        _phaseOreMaturation(chunks, chunkRadiusX, chunkRadiusY));

    await _runPhase(GenesisPhase.surfaceWeathering, timings, () =>
        _phaseSurfaceWeathering(chunks, chunkRadiusX, chunkRadiusY));

    _reportProgress(GenesisPhase.worldReady, 1.0);

    return GenesisResult(chunks: chunks, timings: timings);
  }

  /// Yield to UI thread. Uses 1ms delay for reliable yielding on all platforms.
  static Future<void> _yieldToUI() =>
      Future<void>.delayed(const Duration(milliseconds: 1));

  /// Run a single phase with timing and UI-thread yielding.
  Future<void> _runPhase(
    GenesisPhase phase,
    PhaseTimings timings,
    Future<void> Function() work,
  ) async {
    // Yield to UI thread before starting (lets load screen render)
    await _yieldToUI();

    final sw = Stopwatch()..start();
    await work();
    sw.stop();

    timings.record(phase, sw.elapsedMilliseconds);

    // Yield again after completion so load screen can animate transition
    await _yieldToUI();
  }

  // -------------------------------------------------------------------------
  // Phase 1: Tectonic Formation
  // -------------------------------------------------------------------------

  /// Generate base SDF terrain using noise and stratigraphy layers.
  ///
  /// For each cell:
  /// 1. Sample multi-octave noise to produce raw SDF value
  /// 2. Look up stratum at (worldX, depthFeet) for material classification
  /// 3. Assign CellType and SDF from stratum
  ///
  /// Progress: reports per-chunk-row for smooth load screen animation.
  Future<void> _phaseTectonicFormation(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    const size = GameConstants.chunkSize;
    final totalRows = radiusY + 1;

    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = List.generate(
          size,
          (y) => List.generate(size, (x) {
            final worldX = cx * size + x;
            final worldY = cy * size + y;
            final depthFeet = worldY * GameConstants.feetPerTile;

            // Base terrain SDF from noise + cave noise
            final noise = NoiseUtils.sampleMultiOctave(
              seed: seed,
              x: worldX.toDouble(),
              y: worldY.toDouble(),
              octaves: 4,
              frequency: 0.02,
              gain: 0.5,
            );

            // Cave noise with biome-scaled influence
            final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);
            final caveNoise = NoiseUtils.sampleCaveNoise(
              seed: seed,
              x: worldX.toDouble(),
              y: worldY.toDouble(),
            );
            final caveInfluence = caveNoise * biome.caveFrequency * 0.5;
            final combinedDensity = (noise - caveInfluence).clamp(0.0, 1.0);
            final sdf = SdfPrimitives.densityToSdf(combinedDensity);

            // Classify by geological stratum
            final stratum = stratigraphy.getStratumAtPosition(
              worldX.toDouble(),
              depthFeet,
            );

            return TerrainCell(
              type: sdf < 0 ? stratum.cellType : CellType.empty,
              sdf: sdf,
              stratum: sdf < 0 ? stratum.type : null,
            );
          }),
        );

        chunks['$cx,$cy'] = grid;
      }

      // Report progress per chunk-row (granular for smooth animation)
      _reportProgress(
        GenesisPhase.tectonicFormation,
        (cy + 1) / totalRows,
      );

      // Yield every row so the UI thread can render
      await _yieldToUI();
    }
  }

  // -------------------------------------------------------------------------
  // Phase 2: Volcanic Intrusion
  // -------------------------------------------------------------------------

  /// Add magma intrusions and volcanic features to deep strata.
  ///
  /// Iterates chunks in deep strata (>2000ft depth). Places magma
  /// chambers as SDF sphere blobs blended via smoothUnion, and sets
  /// hot cells to CellType.lava based on temperature noise hotspots.
  Future<void> _phaseVolcanicIntrusion(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.volcanicIntrusion, 0.0);

    const size = GameConstants.chunkSize;
    final rng = Random(seed ^ 0xD3ADB33F);

    // Calculate which chunk rows are deep enough for volcanic activity
    final minChunkY = (2000 / GameConstants.feetPerTile / size).floor();
    if (minChunkY > radiusY) {
      _reportProgress(GenesisPhase.volcanicIntrusion, 1.0);
      return;
    }

    final deepRows = radiusY - minChunkY + 1;
    int processedRows = 0;

    // Generate magma chamber seed positions (large blobs)
    final chamberCount = 3 + rng.nextInt(4); // 3-6 chambers
    final chambers = <(double, double, double)>[]; // worldX, worldY, radius
    for (int i = 0; i < chamberCount; i++) {
      final cx = (rng.nextDouble() * 2 - 1) * radiusX * size * 0.7;
      final minWorldY = minChunkY * size;
      final maxWorldY = radiusY * size;
      final cy = minWorldY + rng.nextDouble() * (maxWorldY - minWorldY);
      final radius = 3.0 + rng.nextDouble() * 5.0; // 3-8 cell radius
      chambers.add((cx, cy, radius));
    }

    for (int cy = minChunkY; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final worldStartX = cx * size;
        final worldStartY = cy * size;

        for (int y = 0; y < size; y++) {
          final worldY = worldStartY + y;
          final depthFeet = worldY * GameConstants.feetPerTile;

          for (int x = 0; x < size; x++) {
            final worldX = worldStartX + x;
            final cell = grid[y][x];

            // Check temperature hotspots for individual lava cells
            final temp = stratigraphy.getTemperatureAtPosition(
              worldX.toDouble(),
              depthFeet,
            );

            if (temp > 800 && cell.isSolid && cell.type != CellType.ore) {
              // High temperature noise -> lava pocket
              final lavaNoise = NoiseUtils.sampleLavaNoise(
                seed: seed + 11111,
                x: worldX.toDouble(),
                y: worldY.toDouble(),
              );
              if (lavaNoise > 0.72) {
                cell.type = CellType.lava;
                cell.sdf = 0.5; // Non-blocking
              }
            }

            // Check if this cell is inside any magma chamber
            for (final (chamberX, chamberY, chamberRadius) in chambers) {
              final dist = SdfPrimitives.circle(
                worldX.toDouble(),
                worldY.toDouble(),
                chamberX,
                chamberY,
                chamberRadius,
              );

              if (dist < 0) {
                // Inside chamber — carve to lava
                cell.type = CellType.lava;
                cell.sdf = 0.5;
                cell.oreType = null;
                cell.stratum = null;
                break;
              } else if (dist < 2.0 && cell.isSolid) {
                // Near chamber — soften SDF (creates erosion-prone zone)
                final blend = SdfPrimitives.smoothUnion(cell.sdf, dist, 1.5);
                cell.sdf = blend;
              }
            }
          }
        }
      }

      processedRows++;
      _reportProgress(
        GenesisPhase.volcanicIntrusion,
        processedRows / deepRows,
      );

      await _yieldToUI();
    }

    _reportProgress(GenesisPhase.volcanicIntrusion, 1.0);
  }

  // -------------------------------------------------------------------------
  // Phase 3: Mineral Seeding
  // -------------------------------------------------------------------------

  /// Seed ore deposits using reaction-diffusion patterns.
  ///
  /// Runs GrayScottSimulation per biome depth band, mapping V-field
  /// concentrations to ore placements. Each biome uses different RD
  /// patterns producing distinct ore distributions.
  Future<void> _phaseMineralSeeding(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.mineralSeeding, 0.0);

    const size = GameConstants.chunkSize;

    // Group chunk rows by biome depth band
    final biomeChunkRows = <BiomeType, List<int>>{};
    for (int cy = 0; cy <= radiusY; cy++) {
      final depthFeet = cy * size * GameConstants.feetPerTile;
      final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);
      biomeChunkRows.putIfAbsent(biome.type, () => []).add(cy);
    }

    final totalBiomes = biomeChunkRows.length;
    int biomesDone = 0;

    for (final entry in biomeChunkRows.entries) {
      final biomeType = entry.key;
      final chunkRows = entry.value;
      final patterns = biomeOrePatterns[biomeType];

      if (patterns == null || patterns.isEmpty) {
        biomesDone++;
        _reportProgress(
          GenesisPhase.mineralSeeding,
          biomesDone / totalBiomes,
        );
        continue;
      }

      // Collect all cells for this biome band into a flat grid for RD
      final bandHeight = chunkRows.length * size;
      final bandWidth = (2 * radiusX + 1) * size;

      // Run each ore pattern config for this biome
      for (int pi = 0; pi < patterns.length; pi++) {
        final config = patterns[pi];
        final rng = Random(seed ^ (biomeType.index * 9973 + pi * 7919));

        // Run RD simulation at reduced resolution for mobile performance
        final rdSize = min(bandWidth, 128);
        final rdHeight = min(bandHeight, 128);

        final sim = GrayScottSimulation.fromPattern(
          config.pattern,
          width: rdSize,
          height: rdHeight,
        );
        sim.seedRandom(rng, count: config.seedCount, radius: 2);
        // Use async version with periodic yields to prevent main-thread blocking
        await sim.runAsync(config.iterations ~/ 2, yieldInterval: 20);

        // Apply V-field to chunk cells in this biome band
        for (final cy in chunkRows) {
          for (int cx = -radiusX; cx <= radiusX; cx++) {
            final grid = chunks['$cx,$cy'];
            if (grid == null) continue;

            placeOresFromRD(
              vField: sim.vField,
              fieldWidth: rdSize,
              fieldHeight: rdHeight,
              cells: grid,
              cellStartX: cx * size,
              cellStartY: cy * size,
              config: config,
              rng: rng,
            );
          }
        }

        // Report sub-progress per pattern within the biome
        _reportProgress(
          GenesisPhase.mineralSeeding,
          (biomesDone + (pi + 1) / patterns.length) / totalBiomes,
        );
        await _yieldToUI();
      }

      biomesDone++;
    }

    _reportProgress(GenesisPhase.mineralSeeding, 1.0);
  }

  // -------------------------------------------------------------------------
  // Phase 4: Water Table Birth
  // -------------------------------------------------------------------------

  /// Generate water table and fluid features.
  ///
  /// Uses stratigraphy.generateCellLayers() to query fluid data at each
  /// position. Places fluid cells based on geological layer properties:
  ///   - FluidType.water -> shallow aquifer pockets
  ///   - FluidType.oil -> shale layer pockets
  ///   - FluidType.lava -> deep hot zone pools (CellType.lava)
  ///   - FluidType.gas -> volcanic zone gas pockets (CellType.gas)
  Future<void> _phaseWaterTableBirth(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.waterTableBirth, 0.0);

    const size = GameConstants.chunkSize;
    final totalRows = radiusY + 1;

    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final worldStartX = cx * size;
        final worldStartY = cy * size;

        for (int y = 0; y < size; y++) {
          final worldY = worldStartY + y;
          final depthFeet = worldY * GameConstants.feetPerTile;

          for (int x = 0; x < size; x++) {
            final worldX = worldStartX + x;
            final cell = grid[y][x];

            // Only place fluids in empty cells (caves) or replace solid
            // cells at fluid pockets
            final layers = stratigraphy.generateCellLayers(
              worldX.toDouble(),
              depthFeet,
            );

            if (layers.fluidFraction < 0.05) continue;
            if (layers.fluidType == FluidType.none) continue;

            // Fluid placement depends on cell state
            switch (layers.fluidType) {
              case FluidType.lava:
                // Lava fills both solid and empty cells
                if (cell.type != CellType.ore) {
                  cell.type = CellType.lava;
                  cell.sdf = 0.5; // Non-blocking
                  cell.oreType = null;
                }
                break;

              case FluidType.gas:
                // Gas only fills empty cells
                if (cell.type == CellType.empty) {
                  cell.type = CellType.gas;
                  cell.sdf = 0.5;
                }
                break;

              case FluidType.water:
              case FluidType.oil:
                // Water/oil don't have their own CellType yet, but we can
                // mark them by keeping them empty (future: add water cell type).
                // For now, no visual effect — data is in CellLayers for future use.
                break;

              case FluidType.none:
                break;
            }
          }
        }
      }

      _reportProgress(
        GenesisPhase.waterTableBirth,
        (cy + 1) / totalRows,
      );

      await _yieldToUI();
    }

    _reportProgress(GenesisPhase.waterTableBirth, 1.0);
  }

  // -------------------------------------------------------------------------
  // Phase 5: The Great Erosion
  // -------------------------------------------------------------------------

  /// Total water droplets to simulate.
  static const int _totalDroplets = 20000;

  /// Run hydraulic erosion across the world SDF.
  ///
  /// Extracts the full world SDF into a flat Float64List, applies
  /// stratigraphy-based erosion rate scaling, runs erosion in batches
  /// with UI yields, then writes results back to chunk cells.
  Future<void> _phaseGreatErosion(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.greatErosion, 0.0);

    const size = GameConstants.chunkSize;
    final gridWidth = (2 * radiusX + 1) * size;
    final gridHeight = (radiusY + 1) * size;

    // Step 1: Extract world SDF into a flat grid (10% progress)
    final sdf = Float64List(gridWidth * gridHeight);
    _extractWorldSdf(chunks, sdf, radiusX, radiusY, size);
    _reportProgress(GenesisPhase.greatErosion, 0.1);
    await _yieldToUI();

    // Step 2: Apply stratigraphy erosion rate scaling
    _applyErosionRateScaling(sdf, gridWidth, gridHeight, radiusX, size);
    _reportProgress(GenesisPhase.greatErosion, 0.15);
    await _yieldToUI();

    // Step 3: Run erosion in batches on main thread with yields (15-85%)
    final erosion = HydraulicErosion(brushRadius: 3);
    const params = ErosionParams(
      inertia: 0.05,
      sedimentCapacityFactor: 4.0,
      erosionRate: 0.3,
      depositionRate: 0.3,
      evaporationRate: 0.01,
      gravity: 4.0,
      maxLifetime: 40,
      erosionRadius: 3,
    );

    const batchSize = 500;
    final totalBatches = (_totalDroplets / batchSize).ceil();
    int dropletsProcessed = 0;

    for (int batch = 0; batch < totalBatches; batch++) {
      final count = min(batchSize, _totalDroplets - dropletsProcessed);
      erosion.erode(
        sdf, gridWidth, gridHeight,
        dropletCount: count,
        seed: seed + 55555 + batch * 31337,
        params: params,
      );
      dropletsProcessed += count;
      _reportProgress(
        GenesisPhase.greatErosion,
        0.15 + 0.7 * dropletsProcessed / _totalDroplets,
      );
      await _yieldToUI();
    }

    _reportProgress(GenesisPhase.greatErosion, 0.85);
    await _yieldToUI();

    // Step 4: Write eroded SDF back to chunk cells (85-100%)
    _writeWorldSdf(chunks, sdf, radiusX, radiusY, size);
    _reportProgress(GenesisPhase.greatErosion, 1.0);
  }

  /// Extract SDF values from all chunks into a flat row-major Float64List.
  ///
  /// Grid layout: chunk columns [-radiusX..+radiusX] map to x,
  /// chunk rows [0..radiusY] map to y. Each chunk is [size x size].
  void _extractWorldSdf(
    Map<String, List<List<TerrainCell>>> chunks,
    Float64List sdf,
    int radiusX,
    int radiusY,
    int size,
  ) {
    final gridWidth = (2 * radiusX + 1) * size;

    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final baseX = (cx + radiusX) * size;
        final baseY = cy * size;

        for (int ly = 0; ly < size; ly++) {
          for (int lx = 0; lx < size; lx++) {
            sdf[(baseY + ly) * gridWidth + (baseX + lx)] = grid[ly][lx].sdf;
          }
        }
      }
    }
  }

  /// Apply stratigraphy-based erosion rate scaling to the SDF grid.
  ///
  /// For harder strata (low erosion rate), slightly increases the magnitude
  /// of negative SDF values, making the erosion simulation work harder to
  /// erode through them. This creates geologically-accurate differential
  /// erosion where soft layers wash away faster than hard ones.
  void _applyErosionRateScaling(
    Float64List sdf,
    int gridWidth,
    int gridHeight,
    int radiusX,
    int size,
  ) {
    for (int gy = 0; gy < gridHeight; gy++) {
      final worldY = gy;
      final depthFeet = worldY * GameConstants.feetPerTile;

      for (int gx = 0; gx < gridWidth; gx++) {
        final worldX = gx - radiusX * size;
        final idx = gy * gridWidth + gx;
        final val = sdf[idx];

        // Only scale solid cells (negative SDF)
        if (val >= 0) continue;

        final erosionRate =
            stratigraphy.getErosionRateAtPosition(worldX.toDouble(), depthFeet);

        // Scale: erosionRate=1.0 leaves SDF unchanged.
        // erosionRate=0.3 multiplies negative SDF by ~1.4 (harder to erode past).
        // Formula: newSdf = sdf / erosionRate (clamped to avoid extremes)
        if (erosionRate > 0.01) {
          final scale = min(1.0 / erosionRate, 3.0);
          sdf[idx] = val * scale;
        }
      }
    }
  }

  /// Write eroded SDF values back to chunk cells.
  ///
  /// Updates each cell's SDF and adjusts CellType: cells whose SDF
  /// became positive (eroded to air) are set to CellType.empty.
  void _writeWorldSdf(
    Map<String, List<List<TerrainCell>>> chunks,
    Float64List sdf,
    int radiusX,
    int radiusY,
    int size,
  ) {
    final gridWidth = (2 * radiusX + 1) * size;

    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final baseX = (cx + radiusX) * size;
        final baseY = cy * size;

        for (int ly = 0; ly < size; ly++) {
          for (int lx = 0; lx < size; lx++) {
            final cell = grid[ly][lx];
            final newSdf = sdf[(baseY + ly) * gridWidth + (baseX + lx)];

            // Reverse the erosion rate scaling so stored SDF is clean
            final worldX = (cx * size + lx).toDouble();
            final depthFeet = (cy * size + ly) * GameConstants.feetPerTile;
            final erosionRate =
                stratigraphy.getErosionRateAtPosition(worldX, depthFeet);
            final scale =
                (erosionRate > 0.01) ? min(1.0 / erosionRate, 3.0) : 1.0;
            final restoredSdf = (scale > 0) ? newSdf / scale : newSdf;

            cell.sdf = restoredSdf;

            // Cells that eroded to air become empty
            if (restoredSdf >= 0 && cell.type != CellType.empty) {
              cell.type = CellType.empty;
              cell.oreType = null;
              cell.stratum = null;
            }
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Phase 6: Cave Networks
  // -------------------------------------------------------------------------

  /// Post-erosion cave cleanup and smoothing.
  ///
  /// 1. Remove tiny isolated solid cells (1-2 cell islands in air)
  /// 2. Smooth cave walls with SDF averaging pass
  /// 3. Ensure caves are traversable (minimum 2-cell width)
  Future<void> _phaseCaveNetworks(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.caveNetworks, 0.0);

    const size = GameConstants.chunkSize;
    final totalChunks = (2 * radiusX + 1) * (radiusY + 1);
    int processed = 0;

    // Pass 1: Remove tiny isolated solid cells and smooth cave walls
    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        _removeIsolatedCells(grid, size);
        _smoothCaveWalls(grid, size);

        processed++;
        _reportProgress(
          GenesisPhase.caveNetworks,
          processed / totalChunks * 0.6,
        );
      }

      await _yieldToUI();
    }

    // Pass 2: Widen narrow passages to ensure 2-cell minimum traversability
    _reportProgress(GenesisPhase.caveNetworks, 0.6);
    await _yieldToUI();

    processed = 0;
    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        _widenNarrowPassages(grid, size);
        processed++;
        _reportProgress(
          GenesisPhase.caveNetworks,
          0.6 + processed / totalChunks * 0.4,
        );
      }
    }

    _reportProgress(GenesisPhase.caveNetworks, 1.0);
  }

  /// Remove solid cells that have fewer than 2 solid orthogonal neighbors.
  /// These are 1-2 cell floating islands in air that look unnatural.
  void _removeIsolatedCells(List<List<TerrainCell>> grid, int size) {
    for (int y = 1; y < size - 1; y++) {
      for (int x = 1; x < size - 1; x++) {
        final cell = grid[y][x];
        if (!cell.isSolid) continue;

        int solidNeighbors = 0;
        if (grid[y - 1][x].isSolid) solidNeighbors++;
        if (grid[y + 1][x].isSolid) solidNeighbors++;
        if (grid[y][x - 1].isSolid) solidNeighbors++;
        if (grid[y][x + 1].isSolid) solidNeighbors++;

        if (solidNeighbors < 2) {
          cell.sdf = 0.5; // Positive = air
          cell.type = CellType.empty;
          cell.oreType = null;
          cell.stratum = null;
        }
      }
    }
  }

  /// Smooth cave walls by averaging SDF values with neighbors.
  /// Only affects cells near the surface (SDF close to zero) to
  /// round off jagged erosion artifacts without destroying deep terrain.
  void _smoothCaveWalls(List<List<TerrainCell>> grid, int size) {
    // Work on a snapshot to avoid read-modify conflicts
    final snapshot = List.generate(
      size,
      (y) => List.generate(size, (x) => grid[y][x].sdf),
    );

    for (int y = 1; y < size - 1; y++) {
      for (int x = 1; x < size - 1; x++) {
        final sdf = snapshot[y][x];
        // Only smooth near-surface cells (within 1.5 cells of surface)
        if (sdf.abs() > 1.5) continue;

        // 5-sample cross average (self + 4 ortho neighbors)
        final avg = (sdf +
                snapshot[y - 1][x] +
                snapshot[y + 1][x] +
                snapshot[y][x - 1] +
                snapshot[y][x + 1]) /
            5.0;

        // Blend 40% toward average (subtle smoothing)
        grid[y][x].sdf = sdf * 0.6 + avg * 0.4;
      }
    }
  }

  /// Widen narrow cave passages to ensure minimum 2-cell traversability.
  /// If an empty cell has solid cells on opposite sides with only 1 cell
  /// gap, push the solid cells' SDF slightly positive to widen the passage.
  void _widenNarrowPassages(List<List<TerrainCell>> grid, int size) {
    for (int y = 1; y < size - 1; y++) {
      for (int x = 1; x < size - 1; x++) {
        final cell = grid[y][x];
        if (cell.isSolid) continue; // Only process empty cells

        // Check for pinch points: solid on opposite sides
        final solidLeft = x > 0 && grid[y][x - 1].isSolid;
        final solidRight = x < size - 1 && grid[y][x + 1].isSolid;
        final solidUp = y > 0 && grid[y - 1][x].isSolid;
        final solidDown = y < size - 1 && grid[y + 1][x].isSolid;

        // Horizontal pinch: solid left AND right
        if (solidLeft && solidRight) {
          // Widen by pushing the narrower side to air
          if (grid[y][x - 1].sdf > grid[y][x + 1].sdf) {
            _carveCell(grid[y][x - 1]);
          } else {
            _carveCell(grid[y][x + 1]);
          }
        }

        // Vertical pinch: solid above AND below
        if (solidUp && solidDown) {
          if (grid[y - 1][x].sdf > grid[y + 1][x].sdf) {
            _carveCell(grid[y - 1][x]);
          } else {
            _carveCell(grid[y + 1][x]);
          }
        }
      }
    }
  }

  /// Carve a single cell to air (for passage widening).
  void _carveCell(TerrainCell cell) {
    cell.sdf = 0.1; // Just barely positive = air
    cell.type = CellType.empty;
    cell.oreType = null;
    cell.stratum = null;
  }

  // -------------------------------------------------------------------------
  // Phase 7: Ore Maturation
  // -------------------------------------------------------------------------

  /// Finalize ore distributions post-erosion.
  ///
  /// 1. Remove ores in cells that eroded to air
  /// 2. Remove isolated single-cell ores (no solid ore neighbors)
  /// 3. Boost concentration near cluster centers
  Future<void> _phaseOreMaturation(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.oreMaturation, 0.0);

    const size = GameConstants.chunkSize;
    final totalChunks = (2 * radiusX + 1) * (radiusY + 1);
    int processed = 0;

    // Pass 1: Remove ores in eroded-to-air cells and isolated single-cell ores
    for (int cy = 0; cy <= radiusY; cy++) {
      for (int cx = -radiusX; cx <= radiusX; cx++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            final cell = grid[y][x];

            // Remove ore from cells that eroded to air
            if (cell.type == CellType.ore && cell.sdf >= 0) {
              cell.type = CellType.empty;
              cell.oreType = null;
              continue;
            }

            // Remove isolated single-cell ores (no adjacent ore neighbors)
            if (cell.type == CellType.ore) {
              int oreNeighbors = 0;
              if (x > 0 && grid[y][x - 1].type == CellType.ore) oreNeighbors++;
              if (x < size - 1 && grid[y][x + 1].type == CellType.ore) {
                oreNeighbors++;
              }
              if (y > 0 && grid[y - 1][x].type == CellType.ore) oreNeighbors++;
              if (y < size - 1 && grid[y + 1][x].type == CellType.ore) {
                oreNeighbors++;
              }

              if (oreNeighbors == 0) {
                // Revert to solid terrain
                final depthFeet =
                    (cy * size + y) * GameConstants.feetPerTile;
                final stratum = stratigraphy.getStratumAtPosition(
                  (cx * size + x).toDouble(),
                  depthFeet,
                );
                cell.type = stratum.cellType;
                cell.oreType = null;
              }
            }
          }
        }

        processed++;
        _reportProgress(
          GenesisPhase.oreMaturation,
          processed / totalChunks,
        );
      }

      await _yieldToUI();
    }

    _reportProgress(GenesisPhase.oreMaturation, 1.0);
  }

  // -------------------------------------------------------------------------
  // Phase 8: Surface Weathering
  // -------------------------------------------------------------------------

  /// Apply surface detail: landing pad, boss arena, creatures, hazards.
  ///
  /// 1. Surface zone: clear sky above y=0, apply surface contour noise,
  ///    flatten landing pad (|worldX| <= 5), ensure top 3 rows solid
  /// 2. Boss arena: protect rectangle at bossDepth with obsidian walls
  ///    and empty interior
  /// 3. Creature spawns: mark empty cells at depth > 500ft using
  ///    creature noise threshold (> 0.88)
  /// 4. Final hazard pass: ensure lava/gas cells are properly typed
  Future<void> _phaseSurfaceWeathering(
    Map<String, List<List<TerrainCell>>> chunks,
    int radiusX,
    int radiusY,
  ) async {
    _reportProgress(GenesisPhase.surfaceWeathering, 0.0);

    const size = GameConstants.chunkSize;

    // Use a WorldGenerator for surface height calculations (deterministic)
    final worldGen = WorldGenerator(seed: seed);

    // Sub-step 1: Surface zone (25%)
    for (int cx = -radiusX; cx <= radiusX; cx++) {
      for (int cy = 0; cy <= radiusY; cy++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final worldStartX = cx * size;
        final worldStartY = cy * size;

        for (int y = 0; y < size; y++) {
          final worldY = worldStartY + y;
          for (int x = 0; x < size; x++) {
            final worldX = worldStartX + x;
            final surfaceY = worldGen.getSurfaceHeight(worldX);
            final surfaceYInt = surfaceY.floor();

            if (worldY < surfaceYInt - 1) {
              // Above surface: sky
              grid[y][x].type = CellType.empty;
              grid[y][x].sdf = 0.5;
              grid[y][x].oreType = null;
              grid[y][x].stratum = null;
            } else if (worldY == surfaceYInt - 1 || worldY == surfaceYInt) {
              if (worldY.toDouble() < surfaceY) {
                grid[y][x].type = CellType.empty;
                grid[y][x].sdf = 0.5;
                grid[y][x].oreType = null;
                grid[y][x].stratum = null;
              } else {
                final distBelow = worldY.toDouble() - surfaceY;
                grid[y][x].type = CellType.sand;
                grid[y][x].sdf = -(distBelow * 0.3).clamp(0.0, 0.45);
              }
            } else if (worldY <= surfaceYInt + 3) {
              // First 3 rows below surface: guaranteed solid
              grid[y][x].type = CellType.sand;
              final depthBelow = worldY - surfaceYInt;
              grid[y][x].sdf = -(0.1 + depthBelow * 0.1).clamp(0.1, 0.45);
            } else if (worldY * GameConstants.feetPerTile <=
                GameConstants.sandLayerEnd) {
              if (grid[y][x].isSolid) {
                grid[y][x].type = CellType.sand;
              }
            }
          }
        }
      }
      await _yieldToUI();
    }
    _reportProgress(GenesisPhase.surfaceWeathering, 0.25);
    await _yieldToUI();

    // Sub-step 2: Boss arena (50%)
    final bossMinX = WorldGenerator.bossArenaMinX;
    final bossMaxX = WorldGenerator.bossArenaMaxX;
    final bossMinY = WorldGenerator.bossArenaMinY;
    final bossMaxY = WorldGenerator.bossArenaMaxY;

    for (int cx = -radiusX; cx <= radiusX; cx++) {
      for (int cy = 0; cy <= radiusY; cy++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final worldStartX = cx * size;
        final worldStartY = cy * size;

        for (int y = 0; y < size; y++) {
          final worldY = worldStartY + y;
          for (int x = 0; x < size; x++) {
            final worldX = worldStartX + x;
            if (worldX >= bossMinX &&
                worldX <= bossMaxX &&
                worldY >= bossMinY &&
                worldY <= bossMaxY) {
              if (worldX > bossMinX &&
                  worldX < bossMaxX &&
                  worldY > bossMinY &&
                  worldY < bossMaxY) {
                grid[y][x].type = CellType.empty;
                grid[y][x].sdf = 0.5;
                grid[y][x].oreType = null;
              } else {
                grid[y][x].type = CellType.obsidian;
                grid[y][x].sdf = -0.5;
                grid[y][x].oreType = null;
              }
            }
          }
        }
      }
      await _yieldToUI();
    }
    _reportProgress(GenesisPhase.surfaceWeathering, 0.5);
    await _yieldToUI();

    // Sub-step 3: Creature spawns (75%)
    for (int cx = -radiusX; cx <= radiusX; cx++) {
      for (int cy = 0; cy <= radiusY; cy++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final worldStartX = cx * size;
        final worldStartY = cy * size;

        for (int y = 0; y < size; y++) {
          final worldY = worldStartY + y;
          final depthFeet = worldY * GameConstants.feetPerTile;
          if (depthFeet < 500) continue;

          for (int x = 0; x < size; x++) {
            if (grid[y][x].type != CellType.empty) continue;
            final worldX = worldStartX + x;

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
      await _yieldToUI();
    }
    _reportProgress(GenesisPhase.surfaceWeathering, 0.75);
    await _yieldToUI();

    // Sub-step 4: Final hazard pass (100%)
    for (int cx = -radiusX; cx <= radiusX; cx++) {
      for (int cy = 0; cy <= radiusY; cy++) {
        final grid = chunks['$cx,$cy'];
        if (grid == null) continue;

        final worldStartX = cx * size;
        final worldStartY = cy * size;

        for (int y = 0; y < size; y++) {
          final worldY = worldStartY + y;
          final depthFeet = worldY * GameConstants.feetPerTile;
          final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);

          for (int x = 0; x < size; x++) {
            final worldX = worldStartX + x;
            final cell = grid[y][x];

            if (biome.hasLava && cell.isSolid && cell.type != CellType.ore) {
              final lavaNoise = NoiseUtils.sampleLavaNoise(
                seed: seed,
                x: worldX.toDouble(),
                y: worldY.toDouble(),
              );
              if (lavaNoise > 0.78) {
                cell.type = CellType.lava;
                cell.sdf = 0.5;
              }
            }

            if (biome.hasGas && cell.type == CellType.empty) {
              final gasNoise = NoiseUtils.sampleGasNoise(
                seed: seed,
                x: worldX.toDouble(),
                y: worldY.toDouble(),
              );
              if (gasNoise > 0.82) {
                cell.type = CellType.gas;
                cell.sdf = 0.5;
              }
            }
          }
        }
      }
      await _yieldToUI();
    }
    _reportProgress(GenesisPhase.surfaceWeathering, 1.0);
  }

  // -------------------------------------------------------------------------
  // Utility
  // -------------------------------------------------------------------------

  void _reportProgress(GenesisPhase phase, double progress) {
    onProgress?.call(phase, progress.clamp(0.0, 1.0));
  }

  /// Overall progress across all phases (0.0-1.0).
  ///
  /// Each of the 9 phases contributes equally (1/9 of total).
  static double overallProgress(GenesisPhase phase, double phaseProgress) {
    return (phase.index + phaseProgress) / GenesisPhase.values.length;
  }

  /// Human-readable label for a genesis phase (for load screen display).
  static String phaseLabel(GenesisPhase phase) {
    switch (phase) {
      case GenesisPhase.tectonicFormation:
        return 'Tectonic Formation';
      case GenesisPhase.volcanicIntrusion:
        return 'Volcanic Intrusion';
      case GenesisPhase.mineralSeeding:
        return 'Mineral Seeding';
      case GenesisPhase.waterTableBirth:
        return 'Water Table Birth';
      case GenesisPhase.greatErosion:
        return 'The Great Erosion';
      case GenesisPhase.caveNetworks:
        return 'Cave Networks';
      case GenesisPhase.oreMaturation:
        return 'Ore Maturation';
      case GenesisPhase.surfaceWeathering:
        return 'Surface Weathering';
      case GenesisPhase.worldReady:
        return 'World Ready';
    }
  }
}

/// Result of a Genesis world generation run.
class GenesisResult {
  /// Generated chunk data: `"chunkX,chunkY"` -> 2D grid of TerrainCells.
  final Map<String, List<List<TerrainCell>>> chunks;

  /// Per-phase timing data for profiling.
  final PhaseTimings timings;

  const GenesisResult({
    required this.chunks,
    required this.timings,
  });
}
