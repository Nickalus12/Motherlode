import 'package:flutter/foundation.dart';

import 'package:hellbore/world/chunk_data.dart';
import 'package:hellbore/world/world_generator.dart';

/// Top-level function for compute() isolate — generates chunk data.
/// Must be top-level (not a method) for isolate serialization.
///
/// Note: This works because WorldGenerator and its dependencies
/// (NoiseUtils, BiomeRegistry, OreRegistry) are pure Dart logic.
/// The only `dart:ui` dependency is Color in OreType, which is
/// available in Flutter's isolate context.
ChunkData generateChunkIsolated(ChunkGenerationParams params) {
  final generator = WorldGenerator(seed: params.seed);
  final grid = generator.generateChunk(params.chunkX, params.chunkY);
  return ChunkData.fromGrid(
    grid,
    chunkX: params.chunkX,
    chunkY: params.chunkY,
    seed: params.seed,
  );
}

/// Async chunk generation using compute() isolate.
/// Falls back to synchronous generation if compute fails.
Future<ChunkData> generateChunkAsync(ChunkGenerationParams params) async {
  try {
    return await compute(generateChunkIsolated, params);
  } catch (_) {
    // Fallback to synchronous generation
    return generateChunkIsolated(params);
  }
}
