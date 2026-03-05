import 'package:flame/components.dart';

import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/biome.dart';

/// Tracks the pod's depth, triggers biome transitions,
/// and maintains depth records
class DepthSystem extends Component {
  double currentDepth = 0; // in feet
  double maxDepthReached = 0;
  BiomeType _currentBiome = BiomeType.surface;
  BiomeType? _previousBiome;

  // Callback for biome transition events
  void Function(BiomeType newBiome)? onBiomeChange;

  /// Update depth based on pod's Y position in world units
  void updateDepth(double podWorldY) {
    // Convert world Y (tiles) to depth in feet
    // Positive Y = deeper underground
    currentDepth = (podWorldY * GameConstants.feetPerTile).clamp(0, double.infinity);

    // Track maximum depth
    if (currentDepth > maxDepthReached) {
      maxDepthReached = currentDepth;
    }

    // Check for biome transitions
    final newBiome = BiomeRegistry.getBiomeAtDepth(currentDepth).type;
    if (newBiome != _currentBiome) {
      _previousBiome = _currentBiome;
      _currentBiome = newBiome;
      onBiomeChange?.call(newBiome);
    }
  }

  /// Current biome type
  BiomeType get currentBiomeType => _currentBiome;

  /// Current biome data
  Biome get currentBiome => BiomeRegistry.getBiomeAtDepth(currentDepth);

  /// Whether a biome transition just occurred
  bool get justTransitioned => _previousBiome != null;

  /// Get the biome name for display
  String get currentBiomeName => BiomeRegistry.getBiomeName(currentDepth);

  /// Whether the pod is near the boss zone
  bool get isNearBoss =>
      currentDepth >= GameConstants.bossDepth - 200;

  /// Whether the pod has reached a new depth record
  bool get isNewDepthRecord => currentDepth >= maxDepthReached - 1;

  /// Normalized depth (0.0 at surface, 1.0 at max depth)
  double get normalizedDepth =>
      (currentDepth / GameConstants.maxDepth).clamp(0.0, 1.0);

  /// Serialize
  Map<String, dynamic> toMap() {
    return {
      'maxDepth': maxDepthReached,
    };
  }
}
