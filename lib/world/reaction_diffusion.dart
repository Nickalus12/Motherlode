import 'dart:math';
import 'dart:typed_data';

import 'package:motherlode/world/biome.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Preset reaction-diffusion patterns for different ore distribution types.
enum RDPattern {
  /// Isolated dots - rare ores (Diamond, Ruby)
  spots(f: 0.035, k: 0.065),

  /// Winding lines - vein ores (Gold, Platinum)
  stripes(f: 0.060, k: 0.062),

  /// Branching networks - common ore networks (Iron, Bronze)
  coral(f: 0.040, k: 0.060),

  /// Splitting blobs - cluster ores (Emerald, Amazonite)
  mitosis(f: 0.035, k: 0.058),

  /// Holes in field - gas/lava pocket placement
  holes(f: 0.035, k: 0.060);

  final double f;
  final double k;

  const RDPattern({required this.f, required this.k});
}

/// Gray-Scott reaction-diffusion simulation.
///
/// Simulates two chemicals U (substrate) and V (catalyst) that react and
/// diffuse on a 2D grid. Different f/k parameters produce different spatial
/// patterns (spots, stripes, coral, etc.) used to place ores naturally.
///
/// Uses flat [Float64List] buffers for cache-friendly access and performance.
class GrayScottSimulation {
  final int width;
  final int height;
  final double du;
  final double dv;
  final double f;
  final double k;
  final double dt;

  late Float64List _u;
  late Float64List _v;
  late Float64List _nextU;
  late Float64List _nextV;

  GrayScottSimulation({
    required this.width,
    required this.height,
    this.du = 1.0,
    this.dv = 0.5,
    required this.f,
    required this.k,
    this.dt = 1.0,
  }) {
    final size = width * height;
    _u = Float64List(size)..fillRange(0, size, 1.0);
    _v = Float64List(size)..fillRange(0, size, 0.0);
    _nextU = Float64List(size);
    _nextV = Float64List(size);
  }

  /// Create a simulation from a preset pattern.
  factory GrayScottSimulation.fromPattern(
    RDPattern pattern, {
    required int width,
    required int height,
    double du = 1.0,
    double dv = 0.5,
    double dt = 1.0,
  }) {
    return GrayScottSimulation(
      width: width,
      height: height,
      du: du,
      dv: dv,
      f: pattern.f,
      k: pattern.k,
      dt: dt,
    );
  }

  /// Seed a circular region of catalyst (V=1.0, U=0.5) at (cx, cy).
  void seedPoint(int cx, int cy, {int radius = 3}) {
    final r2 = radius * radius;
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy > r2) continue;
        final px = (cx + dx).clamp(0, width - 1);
        final py = (cy + dy).clamp(0, height - 1);
        final idx = py * width + px;
        _v[idx] = 1.0;
        _u[idx] = 0.5;
      }
    }
  }

  /// Seed multiple random points using the given RNG.
  void seedRandom(Random rng, {int count = 10, int radius = 3}) {
    for (int i = 0; i < count; i++) {
      seedPoint(
        rng.nextInt(width),
        rng.nextInt(height),
        radius: radius,
      );
    }
  }

  /// Execute one simulation step using the Gray-Scott equations.
  void step() {
    for (int y = 1; y < height - 1; y++) {
      final rowOffset = y * width;
      final rowAbove = (y - 1) * width;
      final rowBelow = (y + 1) * width;

      for (int x = 1; x < width - 1; x++) {
        final idx = rowOffset + x;
        final uVal = _u[idx];
        final vVal = _v[idx];
        final uvv = uVal * vVal * vVal;

        // Laplacian using 3x3 kernel:
        // orthogonal neighbors: weight 0.2, diagonal: 0.05, center: -1.0
        final lapU = _u[rowAbove + x] * 0.2 +
            _u[rowBelow + x] * 0.2 +
            _u[rowOffset + x - 1] * 0.2 +
            _u[rowOffset + x + 1] * 0.2 +
            _u[rowAbove + x - 1] * 0.05 +
            _u[rowAbove + x + 1] * 0.05 +
            _u[rowBelow + x - 1] * 0.05 +
            _u[rowBelow + x + 1] * 0.05 +
            uVal * -1.0;

        final lapV = _v[rowAbove + x] * 0.2 +
            _v[rowBelow + x] * 0.2 +
            _v[rowOffset + x - 1] * 0.2 +
            _v[rowOffset + x + 1] * 0.2 +
            _v[rowAbove + x - 1] * 0.05 +
            _v[rowAbove + x + 1] * 0.05 +
            _v[rowBelow + x - 1] * 0.05 +
            _v[rowBelow + x + 1] * 0.05 +
            vVal * -1.0;

        _nextU[idx] = uVal + (du * lapU - uvv + f * (1.0 - uVal)) * dt;
        _nextV[idx] = vVal + (dv * lapV + uvv - (f + k) * vVal) * dt;
      }
    }

    // Swap buffers
    final tmpU = _u;
    _u = _nextU;
    _nextU = tmpU;

    final tmpV = _v;
    _v = _nextV;
    _nextV = tmpV;
  }

  /// Run multiple simulation steps.
  void run(int iterations) {
    for (int i = 0; i < iterations; i++) {
      step();
    }
  }

  /// Run simulation steps asynchronously, yielding to the event loop
  /// every [yieldInterval] steps to prevent main-thread blocking.
  Future<void> runAsync(int iterations, {int yieldInterval = 25}) async {
    for (int i = 0; i < iterations; i++) {
      step();
      if (i % yieldInterval == yieldInterval - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
  }

  /// Get the V-field value at (x, y). V concentration determines ore placement.
  double getV(int x, int y) => _v[y * width + x];

  /// Get the U-field value at (x, y).
  double getU(int x, int y) => _u[y * width + x];

  /// Get the entire V-field as a flat list (read-only view).
  Float64List get vField => _v;

  /// Get the entire U-field as a flat list (read-only view).
  Float64List get uField => _u;
}

/// Maps ore patterns to biome depths, defining which RD pattern and ores
/// appear in each geological layer.
class OrePatternConfig {
  final RDPattern pattern;
  final double vThreshold;
  final List<OreType> ores;
  final int seedCount;
  final int iterations;

  const OrePatternConfig({
    required this.pattern,
    this.vThreshold = 0.25,
    required this.ores,
    this.seedCount = 10,
    this.iterations = 300,
  });
}

/// Ore pattern configurations by biome type.
///
/// Each biome uses a different RD pattern to create visually distinct
/// ore distributions at different depths.
final Map<BiomeType, List<OrePatternConfig>> biomeOrePatterns = {
  BiomeType.topsoil: [
    const OrePatternConfig(
      pattern: RDPattern.coral,
      vThreshold: 0.20,
      ores: [OreRegistry.ironium, OreRegistry.bronzium],
      seedCount: 15,
      iterations: 250,
    ),
    const OrePatternConfig(
      pattern: RDPattern.stripes,
      vThreshold: 0.30,
      ores: [OreRegistry.silverium],
      seedCount: 8,
      iterations: 300,
    ),
  ],
  BiomeType.rock: [
    const OrePatternConfig(
      pattern: RDPattern.stripes,
      vThreshold: 0.25,
      ores: [OreRegistry.goldium, OreRegistry.platinium],
      seedCount: 10,
      iterations: 350,
    ),
    const OrePatternConfig(
      pattern: RDPattern.coral,
      vThreshold: 0.22,
      ores: [OreRegistry.ironium, OreRegistry.bronzium, OreRegistry.silverium],
      seedCount: 12,
      iterations: 250,
    ),
    const OrePatternConfig(
      pattern: RDPattern.spots,
      vThreshold: 0.35,
      ores: [OreRegistry.einsteinium],
      seedCount: 5,
      iterations: 400,
    ),
  ],
  BiomeType.volcanic: [
    const OrePatternConfig(
      pattern: RDPattern.mitosis,
      vThreshold: 0.28,
      ores: [OreRegistry.emerald, OreRegistry.amazonite],
      seedCount: 8,
      iterations: 350,
    ),
    const OrePatternConfig(
      pattern: RDPattern.spots,
      vThreshold: 0.35,
      ores: [OreRegistry.ruby, OreRegistry.diamond],
      seedCount: 4,
      iterations: 450,
    ),
    const OrePatternConfig(
      pattern: RDPattern.holes,
      vThreshold: 0.20,
      ores: [OreRegistry.goldium, OreRegistry.platinium],
      seedCount: 10,
      iterations: 300,
    ),
  ],
  BiomeType.hell: [
    const OrePatternConfig(
      pattern: RDPattern.spots,
      vThreshold: 0.30,
      ores: [OreRegistry.hellstone, OreRegistry.soulCrystal],
      seedCount: 6,
      iterations: 500,
    ),
    const OrePatternConfig(
      pattern: RDPattern.mitosis,
      vThreshold: 0.25,
      ores: [OreRegistry.diamond, OreRegistry.amazonite],
      seedCount: 8,
      iterations: 400,
    ),
  ],
};

/// Place ores into a terrain grid using reaction-diffusion V-field output.
///
/// [vField] is the flat Float64List from GrayScottSimulation (width x height).
/// [fieldWidth]/[fieldHeight] are the simulation grid dimensions.
/// [cells] is the target terrain grid to place ores into.
/// [cellStartX]/[cellStartY] are world-tile offsets for the cell grid.
/// [config] defines which ores to place and at what threshold.
/// [rng] provides deterministic randomness for ore selection within a config.
void placeOresFromRD({
  required Float64List vField,
  required int fieldWidth,
  required int fieldHeight,
  required List<List<TerrainCell>> cells,
  required int cellStartX,
  required int cellStartY,
  required OrePatternConfig config,
  required Random rng,
}) {
  final cellHeight = cells.length;
  final cellWidth = cells.isEmpty ? 0 : cells[0].length;

  // Scale factors to map cell grid onto the RD field
  final scaleX = fieldWidth / cellWidth;
  final scaleY = fieldHeight / cellHeight;

  for (int cy = 0; cy < cellHeight; cy++) {
    for (int cx = 0; cx < cellWidth; cx++) {
      final cell = cells[cy][cx];
      if (!cell.isSolid) continue;
      // Don't overwrite existing ores from other patterns
      if (cell.type == CellType.ore) continue;

      // Map cell position to RD field position
      final fx = ((cx * scaleX).floor()).clamp(0, fieldWidth - 1);
      final fy = ((cy * scaleY).floor()).clamp(0, fieldHeight - 1);
      final concentration = vField[fy * fieldWidth + fx];

      if (concentration > config.vThreshold) {
        cell.type = CellType.ore;
        // Select ore type: higher concentration favors rarer ores in the list
        final oreIndex = _selectOreIndex(
          concentration,
          config.vThreshold,
          config.ores.length,
          rng,
        );
        cell.oreType = config.ores[oreIndex];
      }
    }
  }
}

/// Select an ore index from the available ores based on V concentration.
/// Higher concentration relative to threshold biases toward later (rarer) ores.
int _selectOreIndex(
  double concentration,
  double threshold,
  int oreCount,
  Random rng,
) {
  if (oreCount == 1) return 0;

  // Normalize concentration above threshold to 0.0-1.0 range
  // Cap at 1.0 since V values rarely exceed ~0.5
  final normalized = ((concentration - threshold) / (0.5 - threshold))
      .clamp(0.0, 1.0);

  // Bias toward common (index 0) with exponential falloff
  // Higher concentration = chance of rarer ore
  final roll = rng.nextDouble();
  for (int i = oreCount - 1; i > 0; i--) {
    final rarityThreshold = pow(normalized, 2.0 - (i / oreCount));
    if (roll < rarityThreshold * 0.3) return i;
  }
  return 0;
}

/// Run the full reaction-diffusion ore placement pipeline for a chunk.
///
/// This generates RD patterns for the chunk's biome and places ores
/// into the cell grid. Designed to be called from an isolate.
void runReactionDiffusionForChunk({
  required List<List<TerrainCell>> cells,
  required int chunkWorldX,
  required int chunkWorldY,
  required int chunkSize,
  required int seed,
}) {
  final depthFeet = chunkWorldY * 10.0; // Approximate feet per tile
  final biome = BiomeRegistry.getBiomeAtDepth(depthFeet);
  final patterns = biomeOrePatterns[biome.type];
  if (patterns == null) return;

  // Deterministic RNG from seed + chunk position
  final rng = Random(seed ^ (chunkWorldX * 7919 + chunkWorldY * 6271));

  // RD simulation grid — use chunk size directly for 1:1 mapping,
  // or a fixed size (e.g. 64) for performance when chunks are large
  final rdSize = min(chunkSize, 64);

  for (final config in patterns) {
    final sim = GrayScottSimulation.fromPattern(
      config.pattern,
      width: rdSize,
      height: rdSize,
    );

    // Seed catalyst points deterministically
    sim.seedRandom(rng, count: config.seedCount, radius: 2);

    // Run simulation
    sim.run(config.iterations);

    // Place ores from V-field into cells
    placeOresFromRD(
      vField: sim.vField,
      fieldWidth: rdSize,
      fieldHeight: rdSize,
      cells: cells,
      cellStartX: chunkWorldX,
      cellStartY: chunkWorldY,
      config: config,
      rng: rng,
    );
  }
}
