import 'package:fast_noise/fast_noise.dart';

/// Wrapped simplex noise helpers for world generation
class NoiseUtils {
  NoiseUtils._();

  /// Create a simplex noise generator with given seed
  static PerlinNoise createSimplexNoise(int seed) {
    return PerlinNoise(seed: seed);
  }

  /// Sample multi-octave noise at (x, y)
  /// Returns value in range [0.0, 1.0]
  static double sampleMultiOctave({
    required int seed,
    required double x,
    required double y,
    int octaves = 4,
    double frequency = 0.02,
    double lacunarity = 2.0,
    double gain = 0.5,
  }) {
    double value = 0.0;
    double amplitude = 1.0;
    double totalAmplitude = 0.0;
    double freq = frequency;

    final noise = PerlinNoise(seed: seed);

    for (int i = 0; i < octaves; i++) {
      // PerlinNoise returns values in [-1, 1]
      final sample = noise.getNoise2(x * freq, y * freq);
      value += sample * amplitude;
      totalAmplitude += amplitude;
      amplitude *= gain;
      freq *= lacunarity;
    }

    // Normalize to [0, 1]
    return (value / totalAmplitude + 1.0) / 2.0;
  }

  /// Sample noise specifically for ore vein generation
  /// Uses different frequency and octaves for blob-like formations
  static double sampleOreNoise({
    required int seed,
    required double x,
    required double y,
    double frequency = 0.08,
  }) {
    return sampleMultiOctave(
      seed: seed + 1000, // Offset seed for different pattern
      x: x,
      y: y,
      octaves: 3,
      frequency: frequency,
      lacunarity: 2.0,
      gain: 0.6,
    );
  }

  /// Sample noise for cave generation (large, smooth)
  static double sampleCaveNoise({
    required int seed,
    required double x,
    required double y,
  }) {
    return sampleMultiOctave(
      seed: seed + 2000,
      x: x,
      y: y,
      octaves: 3,
      frequency: 0.04,
      lacunarity: 2.0,
      gain: 0.45,
    );
  }

  /// Sample noise for creature spawn placement
  static double sampleCreatureNoise({
    required int seed,
    required double x,
    required double y,
  }) {
    return sampleMultiOctave(
      seed: seed + 3000,
      x: x,
      y: y,
      octaves: 2,
      frequency: 0.015,
      lacunarity: 2.0,
      gain: 0.5,
    );
  }

  /// Sample noise for gas pocket placement
  static double sampleGasNoise({
    required int seed,
    required double x,
    required double y,
  }) {
    return sampleMultiOctave(
      seed: seed + 4000,
      x: x,
      y: y,
      octaves: 2,
      frequency: 0.06,
      lacunarity: 2.0,
      gain: 0.5,
    );
  }

  /// Sample noise for lava pocket placement
  static double sampleLavaNoise({
    required int seed,
    required double x,
    required double y,
  }) {
    return sampleMultiOctave(
      seed: seed + 5000,
      x: x,
      y: y,
      octaves: 2,
      frequency: 0.05,
      lacunarity: 2.0,
      gain: 0.5,
    );
  }
}
