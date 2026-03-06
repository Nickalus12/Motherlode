import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

/// Parameters controlling hydraulic erosion behavior.
class ErosionParams {
  /// How much previous direction influences flow (low = follows gradient).
  final double inertia;

  /// Base sediment capacity multiplier.
  final double sedimentCapacityFactor;

  /// Minimum slope used in capacity calculation.
  final double minSlope;

  /// How fast terrain erodes per step.
  final double erosionRate;

  /// How fast sediment deposits per step.
  final double depositionRate;

  /// Fraction of water lost per step.
  final double evaporationRate;

  /// Speed gain from height drop.
  final double gravity;

  /// Maximum steps before a droplet dies.
  final int maxLifetime;

  /// Brush radius for distributing erosion across neighbors.
  final int erosionRadius;

  /// Starting water volume per droplet.
  final double initialWater;

  /// Starting speed per droplet.
  final double initialSpeed;

  /// Water volume below which the droplet stops.
  final double waterThreshold;

  const ErosionParams({
    this.inertia = 0.05,
    this.sedimentCapacityFactor = 4.0,
    this.minSlope = 0.01,
    this.erosionRate = 0.3,
    this.depositionRate = 0.3,
    this.evaporationRate = 0.01,
    this.gravity = 4.0,
    this.maxLifetime = 40,
    this.erosionRadius = 3,
    this.initialWater = 1.0,
    this.initialSpeed = 1.0,
    this.waterThreshold = 0.01,
  });
}

/// A single erosion droplet with position, velocity, and sediment state.
class ErosionDroplet {
  double x;
  double y;
  double dirX;
  double dirY;
  double speed;
  double water;
  double sediment;

  ErosionDroplet({
    required this.x,
    required this.y,
    this.dirX = 0.0,
    this.dirY = 0.0,
    this.speed = 1.0,
    this.water = 1.0,
    this.sediment = 0.0,
  });
}

/// Core hydraulic erosion simulation operating on a flat SDF grid.
///
/// Erosion increases SDF values (removes material / moves surface outward).
/// Deposition decreases SDF values (adds material / moves surface inward).
class HydraulicErosion {
  /// Precomputed brush weights for erosion distribution.
  /// Indexed by [brushIndex][neighborOffset], stores (offsetIndex, weight) pairs.
  late List<List<int>> _brushOffsets;
  late List<List<double>> _brushWeights;

  HydraulicErosion({int brushRadius = 3});

  /// Run erosion on a flat SDF grid.
  ///
  /// [sdf] is modified in place. Positive = air, negative = solid, 0 = surface.
  /// [width] and [height] are grid dimensions.
  /// [dropletCount] is the number of water droplets to simulate.
  /// [seed] provides deterministic randomness.
  /// [params] controls erosion behavior.
  void erode(
    Float64List sdf,
    int width,
    int height, {
    required int dropletCount,
    required int seed,
    ErosionParams params = const ErosionParams(),
  }) {
    _precomputeBrush(width, height, params.erosionRadius);
    final rng = Random(seed);

    for (int d = 0; d < dropletCount; d++) {
      _simulateDroplet(sdf, width, height, rng, params);
    }
  }

  /// Precompute brush kernel offsets and weights for the erosion radius.
  /// Each cell within the radius gets a weight based on distance (1 - dist/radius).
  void _precomputeBrush(int width, int height, int radius) {
    _brushOffsets = [];
    _brushWeights = [];

    // We precompute for a generic cell; offsets are relative.
    // At application time, we skip out-of-bounds cells.
    final offsets = <int>[];
    final weights = <double>[];
    double totalWeight = 0.0;

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final dist = sqrt((dx * dx + dy * dy).toDouble());
        if (dist > radius) continue;
        final w = 1.0 - dist / radius;
        if (w <= 0) continue;
        // Store as row-major offset: dy * width + dx
        // We'll add the actual cell index at application time
        offsets.add(dy);
        offsets.add(dx);
        weights.add(w);
        totalWeight += w;
      }
    }

    // Normalize weights
    if (totalWeight > 0) {
      for (int i = 0; i < weights.length; i++) {
        weights[i] /= totalWeight;
      }
    }

    // Store as single brush template (reused for every cell)
    _brushOffsets = [offsets];
    _brushWeights = [weights];
  }

  /// Apply erosion or deposition at (cellX, cellY) using the brush kernel.
  void _applyBrush(
    Float64List sdf,
    int width,
    int height,
    int cellX,
    int cellY,
    double amount,
  ) {
    final offsets = _brushOffsets[0];
    final weights = _brushWeights[0];

    for (int i = 0; i < weights.length; i++) {
      final dy = offsets[i * 2];
      final dx = offsets[i * 2 + 1];
      final nx = cellX + dx;
      final ny = cellY + dy;
      if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
      sdf[ny * width + nx] += amount * weights[i];
    }
  }

  /// Get SDF value with bilinear interpolation for sub-cell positions.
  double _sampleSdf(
      Float64List sdf, int width, int height, double x, double y) {
    final x0 = x.floor().clamp(0, width - 2);
    final y0 = y.floor().clamp(0, height - 2);
    final fx = x - x0;
    final fy = y - y0;

    final idx00 = y0 * width + x0;
    final idx10 = idx00 + 1;
    final idx01 = idx00 + width;
    final idx11 = idx01 + 1;

    return sdf[idx00] * (1 - fx) * (1 - fy) +
        sdf[idx10] * fx * (1 - fy) +
        sdf[idx01] * (1 - fx) * fy +
        sdf[idx11] * fx * fy;
  }

  /// Compute gradient at (x, y) using central differences on SDF neighbors.
  (double gx, double gy) _gradient(
    Float64List sdf,
    int width,
    int height,
    double x,
    double y,
  ) {
    final ix = x.floor().clamp(1, width - 2);
    final iy = y.floor().clamp(1, height - 2);

    final gx = sdf[iy * width + ix + 1] - sdf[iy * width + ix - 1];
    final gy = sdf[(iy + 1) * width + ix] - sdf[(iy - 1) * width + ix];
    return (gx, gy);
  }

  /// Find a surface cell (SDF near zero) to spawn a droplet.
  /// Tries random positions and picks one near the zero-crossing.
  (double x, double y)? _findSurfaceSpawn(
    Float64List sdf,
    int width,
    int height,
    Random rng,
  ) {
    // Try up to 20 random positions to find one near the surface
    for (int attempt = 0; attempt < 20; attempt++) {
      final x = 1.0 + rng.nextDouble() * (width - 3);
      final y = 1.0 + rng.nextDouble() * (height - 3);
      final val = _sampleSdf(sdf, width, height, x, y);
      // Near-surface: SDF magnitude < 2.0 (within 2 cells of surface)
      if (val.abs() < 2.0) return (x, y);
    }
    // Fallback: random position in the grid
    return (
      1.0 + rng.nextDouble() * (width - 3),
      1.0 + rng.nextDouble() * (height - 3),
    );
  }

  /// Simulate a single water droplet flowing across the SDF terrain.
  void _simulateDroplet(
    Float64List sdf,
    int width,
    int height,
    Random rng,
    ErosionParams params,
  ) {
    final spawn = _findSurfaceSpawn(sdf, width, height, rng);
    if (spawn == null) return;

    final droplet = ErosionDroplet(
      x: spawn.$1,
      y: spawn.$2,
      speed: params.initialSpeed,
      water: params.initialWater,
    );

    for (int step = 0; step < params.maxLifetime; step++) {
      final cellX = droplet.x.floor();
      final cellY = droplet.y.floor();

      // Bounds check
      if (cellX < 1 || cellX >= width - 1 || cellY < 1 || cellY >= height - 1) {
        break;
      }

      final oldSdf = _sampleSdf(sdf, width, height, droplet.x, droplet.y);

      // Calculate gradient
      final (gx, gy) = _gradient(sdf, width, height, droplet.x, droplet.y);

      // Update direction with inertia
      var newDirX = droplet.dirX * params.inertia - gx * (1.0 - params.inertia);
      var newDirY = droplet.dirY * params.inertia - gy * (1.0 - params.inertia);

      // Normalize direction
      final dirLen = sqrt(newDirX * newDirX + newDirY * newDirY);
      if (dirLen < 1e-10) {
        // No gradient — pick random direction
        final angle = rng.nextDouble() * 2.0 * pi;
        newDirX = cos(angle);
        newDirY = sin(angle);
      } else {
        newDirX /= dirLen;
        newDirY /= dirLen;
      }

      droplet.dirX = newDirX;
      droplet.dirY = newDirY;

      // Move to new position
      final newX = droplet.x + newDirX;
      final newY = droplet.y + newDirY;

      // Bounds check for new position
      if (newX < 1 || newX >= width - 1 || newY < 1 || newY >= height - 1) {
        break;
      }

      final newSdf = _sampleSdf(sdf, width, height, newX, newY);
      final deltaHeight = newSdf - oldSdf;

      // Calculate sediment capacity
      final capacity = max(-deltaHeight, params.minSlope) *
          droplet.speed *
          droplet.water *
          params.sedimentCapacityFactor;

      if (droplet.sediment > capacity || deltaHeight > 0) {
        // DEPOSIT: droplet has too much sediment or is going uphill
        var depositAmount = (deltaHeight > 0)
            ? min(droplet.sediment, deltaHeight)
            : (droplet.sediment - capacity) * params.depositionRate;
        depositAmount = max(depositAmount, 0.0);

        // Deposition decreases SDF (makes more solid)
        _applyBrush(sdf, width, height, cellX, cellY, -depositAmount);
        droplet.sediment -= depositAmount;
      } else {
        // ERODE: pick up sediment
        var erodeAmount = min(
            (capacity - droplet.sediment) * params.erosionRate, -deltaHeight);
        erodeAmount = max(erodeAmount, 0.0);

        // Depth weighting: erosion is stronger near the SDF zero-crossing
        // and diminishes deeper into solid regions
        final depthFactor = 1.0 / (1.0 + max(-oldSdf, 0.0));
        erodeAmount *= depthFactor;

        // Erosion increases SDF (removes material)
        _applyBrush(sdf, width, height, cellX, cellY, erodeAmount);
        droplet.sediment += erodeAmount;
      }

      // Update speed
      final speedSq =
          droplet.speed * droplet.speed + deltaHeight * params.gravity;
      droplet.speed = sqrt(max(speedSq, 0.0));

      // Evaporate water
      droplet.water *= (1.0 - params.evaporationRate);

      // Move droplet
      droplet.x = newX;
      droplet.y = newY;

      // Stop if water is depleted
      if (droplet.water < params.waterThreshold) break;
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate-based parallel erosion
// ---------------------------------------------------------------------------

/// A vertical strip of SDF data to be processed by an isolate worker.
class SdfStrip {
  /// Flat SDF data for this strip (height x stripWidth).
  final Float64List sdf;

  /// Width of this strip (including overlap cells).
  final int width;

  /// Height of the strip.
  final int height;

  /// Index of this strip in the overall grid.
  final int stripIndex;

  /// Number of overlap cells on each side.
  final int overlap;

  /// X offset in the full grid where this strip starts (excluding overlap).
  final int startX;

  const SdfStrip({
    required this.sdf,
    required this.width,
    required this.height,
    required this.stripIndex,
    required this.overlap,
    required this.startX,
  });
}

/// Result returned from an isolate worker after erosion.
class ErosionResult {
  final Float64List sdf;
  final int width;
  final int height;
  final int stripIndex;
  final int overlap;
  final int startX;

  const ErosionResult({
    required this.sdf,
    required this.width,
    required this.height,
    required this.stripIndex,
    required this.overlap,
    required this.startX,
  });
}

/// Message sent to an erosion worker isolate.
class _ErosionCommand {
  final SdfStrip strip;
  final int dropletCount;
  final int seed;
  final ErosionParams params;
  final SendPort replyPort;

  const _ErosionCommand({
    required this.strip,
    required this.dropletCount,
    required this.seed,
    required this.params,
    required this.replyPort,
  });
}

/// Pool of long-lived isolates for parallel hydraulic erosion.
///
/// Divides the SDF grid into vertical strips with overlap zones,
/// sends each strip to an isolate for independent erosion, then
/// blends the overlap zones on the main isolate.
class ErosionWorkerPool {
  final List<Isolate> _isolates = [];
  final List<SendPort> _workerPorts = [];
  bool _initialized = false;

  /// Number of active worker isolates.
  int get workerCount => _isolates.length;

  /// Whether the pool has been initialized.
  bool get isInitialized => _initialized;

  /// Spawn [count] long-lived worker isolates.
  Future<void> initialize(int count) async {
    if (_initialized) return;

    for (int i = 0; i < count; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _erosionWorkerEntry,
        receivePort.sendPort,
      );
      _isolates.add(isolate);
      final workerSendPort = await receivePort.first as SendPort;
      _workerPorts.add(workerSendPort);
    }
    _initialized = true;
  }

  /// Run erosion in parallel across all workers.
  ///
  /// [sdf] is the full SDF grid (flat, row-major, height x width).
  /// [width] and [height] are the full grid dimensions.
  /// [totalDroplets] is distributed evenly across workers.
  /// [seed] provides deterministic randomness.
  /// [params] controls erosion behavior.
  /// [overlapCells] is the overlap zone width for blending (default 2).
  ///
  /// Returns the eroded SDF grid (new Float64List, same dimensions).
  Future<Float64List> runParallelErosion(
    Float64List sdf,
    int width,
    int height, {
    required int totalDroplets,
    required int seed,
    ErosionParams params = const ErosionParams(),
    int overlapCells = 2,
  }) async {
    if (!_initialized || _workerPorts.isEmpty) {
      throw StateError(
          'ErosionWorkerPool not initialized. Call initialize() first.');
    }

    final stripCount = _workerPorts.length;
    final strips = _extractStrips(sdf, width, height, stripCount, overlapCells);
    final dropletsPerStrip = totalDroplets ~/ stripCount;

    // Send work to each isolate
    final futures = <Future<ErosionResult>>[];
    for (int i = 0; i < stripCount; i++) {
      futures.add(_sendToWorker(
        i,
        strips[i],
        dropletsPerStrip,
        seed + i * 31337,
        params,
      ));
    }

    // Wait for all workers to complete
    final results = await Future.wait(futures);

    // Blend overlap zones
    _blendOverlapZones(results, overlapCells);

    // Write results back to a new full-size grid
    return _assembleGrid(results, width, height, overlapCells);
  }

  /// Send an erosion command to worker [index] and await the result.
  Future<ErosionResult> _sendToWorker(
    int index,
    SdfStrip strip,
    int dropletCount,
    int seed,
    ErosionParams params,
  ) {
    final completer = Completer<ErosionResult>();
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message is TransferableTypedData) {
        final resultSdf = message.materialize().asFloat64List();
        completer.complete(ErosionResult(
          sdf: resultSdf,
          width: strip.width,
          height: strip.height,
          stripIndex: strip.stripIndex,
          overlap: strip.overlap,
          startX: strip.startX,
        ));
        receivePort.close();
      }
    });

    // Transfer SDF data with zero-copy
    final transferable =
        TransferableTypedData.fromList([strip.sdf.buffer.asByteData()]);

    _workerPorts[index].send(_ErosionCommand(
      strip: SdfStrip(
        sdf: Float64List(
            0), // Placeholder; actual data via TransferableTypedData
        width: strip.width,
        height: strip.height,
        stripIndex: strip.stripIndex,
        overlap: strip.overlap,
        startX: strip.startX,
      ),
      dropletCount: dropletCount,
      seed: seed,
      params: params,
      replyPort: receivePort.sendPort,
    ));

    // Send the actual data separately for zero-copy transfer
    _workerPorts[index].send(transferable);

    return completer.future;
  }

  /// Divide the full SDF grid into vertical strips with overlap.
  List<SdfStrip> _extractStrips(
    Float64List sdf,
    int width,
    int height,
    int stripCount,
    int overlap,
  ) {
    final baseStripWidth = width ~/ stripCount;
    final strips = <SdfStrip>[];

    for (int i = 0; i < stripCount; i++) {
      final coreStartX = i * baseStripWidth;
      final coreEndX = (i == stripCount - 1) ? width : (i + 1) * baseStripWidth;

      // Add overlap on both sides (clamped to grid bounds)
      final startX = max<int>(coreStartX - overlap, 0);
      final endX = min<int>(coreEndX + overlap, width);
      final stripWidth = endX - startX;

      // Extract strip data
      final stripSdf = Float64List(stripWidth * height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < stripWidth; x++) {
          stripSdf[y * stripWidth + x] = sdf[y * width + startX + x];
        }
      }

      strips.add(SdfStrip(
        sdf: stripSdf,
        width: stripWidth,
        height: height,
        stripIndex: i,
        overlap: overlap,
        startX: coreStartX,
      ));
    }

    return strips;
  }

  /// Blend overlap zones between adjacent strip results using linear interpolation.
  void _blendOverlapZones(List<ErosionResult> results, int overlap) {
    for (int i = 0; i < results.length - 1; i++) {
      final left = results[i];
      final right = results[i + 1];

      for (int y = 0; y < left.height; y++) {
        for (int ox = 0; ox < overlap; ox++) {
          final t = (ox + 0.5) / overlap; // 0.0 at left edge, 1.0 at right edge

          final leftIdx = y * left.width + (left.width - overlap + ox);
          final rightIdx = y * right.width + ox;

          final blended =
              left.sdf[leftIdx] * (1.0 - t) + right.sdf[rightIdx] * t;
          left.sdf[leftIdx] = blended;
          right.sdf[rightIdx] = blended;
        }
      }
    }
  }

  /// Assemble strip results back into a full-size SDF grid.
  Float64List _assembleGrid(
    List<ErosionResult> results,
    int fullWidth,
    int fullHeight,
    int overlap,
  ) {
    final output = Float64List(fullWidth * fullHeight);
    final stripCount = results.length;
    final baseStripWidth = fullWidth ~/ stripCount;

    for (int i = 0; i < stripCount; i++) {
      final result = results[i];
      final coreStartX = i * baseStripWidth;
      final coreEndX =
          (i == stripCount - 1) ? fullWidth : (i + 1) * baseStripWidth;

      // The core data within the strip starts after the left overlap
      final leftOverlap =
          coreStartX - (coreStartX - overlap).clamp(0, coreStartX);

      final coreWidth = coreEndX - coreStartX;
      for (int y = 0; y < fullHeight; y++) {
        for (int x = 0; x < coreWidth; x++) {
          output[y * fullWidth + coreStartX + x] =
              result.sdf[y * result.width + leftOverlap + x];
        }
      }
    }

    return output;
  }

  /// Kill all worker isolates and release resources.
  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _workerPorts.clear();
    _initialized = false;
  }

  /// Entry point for each worker isolate.
  static void _erosionWorkerEntry(SendPort mainPort) {
    final workerReceive = ReceivePort();
    mainPort.send(workerReceive.sendPort);

    _ErosionCommand? pendingCommand;

    workerReceive.listen((message) {
      if (message is _ErosionCommand) {
        pendingCommand = message;
      } else if (message is TransferableTypedData && pendingCommand != null) {
        final cmd = pendingCommand!;
        pendingCommand = null;

        // Materialize the transferred SDF data
        final sdfData = message.materialize().asFloat64List();

        // Run erosion on the strip
        final erosion = HydraulicErosion(brushRadius: cmd.params.erosionRadius);
        erosion.erode(
          sdfData,
          cmd.strip.width,
          cmd.strip.height,
          dropletCount: cmd.dropletCount,
          seed: cmd.seed,
          params: cmd.params,
        );

        // Send result back with zero-copy transfer
        final transferable =
            TransferableTypedData.fromList([sdfData.buffer.asByteData()]);
        cmd.replyPort.send(transferable);
      }
    });
  }
}

/// Convenience function to run erosion on an SDF grid without managing a pool.
///
/// Uses `Isolate.run()` for a single-shot parallel erosion pass.
/// For repeated erosion (e.g., during load screen animation), use
/// [ErosionWorkerPool] instead to avoid isolate spawn overhead.
Future<Float64List> erodeOnce(
  Float64List sdf,
  int width,
  int height, {
  required int dropletCount,
  required int seed,
  ErosionParams params = const ErosionParams(),
}) async {
  // Copy data for the isolate
  final sdfCopy = Float64List.fromList(sdf);

  return Isolate.run(() {
    final erosion = HydraulicErosion(brushRadius: params.erosionRadius);
    erosion.erode(
      sdfCopy,
      width,
      height,
      dropletCount: dropletCount,
      seed: seed,
      params: params,
    );
    return sdfCopy;
  });
}
