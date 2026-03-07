import 'package:flame/components.dart';

import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/biome.dart';

/// Depth milestones with names and cash bonuses.
class DepthMilestone {
  final double depth;
  final String name;
  final double cashBonus;

  const DepthMilestone(this.depth, this.name, this.cashBonus);
}

/// All depth milestones in order.
const depthMilestones = [
  DepthMilestone(100, 'FIRST DESCENT', 100),
  DepthMilestone(250, 'GETTING DEEPER', 250),
  DepthMilestone(500, 'SHALLOW DEPTHS', 500),
  DepthMilestone(1000, 'UNDERGROUND', 1500),
  DepthMilestone(1500, 'MANTLE BREACH', 3000),
  DepthMilestone(2000, 'DEEP EARTH', 5000),
  DepthMilestone(3000, 'THE ABYSS', 15000),
  DepthMilestone(4000, 'SCORCHED EARTH', 25000),
  DepthMilestone(5000, 'INFERNO', 50000),
  DepthMilestone(7000, 'HELL\'S GATE', 150000),
  DepthMilestone(7187, 'BOSS ARENA', 250000),
  DepthMilestone(7500, 'BEDROCK', 500000),
];

/// Tracks the robot's depth, triggers biome transitions,
/// milestone celebrations, and maintains depth records
class DepthSystem extends Component {
  double currentDepth = 0; // in feet
  double maxDepthReached = 0;
  BiomeType _currentBiome = BiomeType.surface;
  BiomeType? _previousBiome;

  /// Set of milestone depths already reached (persisted across saves).
  final Set<double> reachedMilestones = {};

  // Callback for biome transition events
  void Function(BiomeType newBiome)? onBiomeChange;

  /// Callback when a new depth milestone is reached for the first time.
  /// Passes the milestone and cash bonus awarded.
  void Function(DepthMilestone milestone)? onMilestoneReached;

  /// Update depth based on robot's Y position in world units
  void updateDepth(double podWorldY) {
    // Convert world Y (tiles) to depth in feet
    // Positive Y = deeper underground
    currentDepth =
        (podWorldY * GameConstants.feetPerTile).clamp(0, double.infinity);

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

    // Check depth milestones
    _checkMilestones();
  }

  void _checkMilestones() {
    for (final milestone in depthMilestones) {
      if (currentDepth >= milestone.depth &&
          !reachedMilestones.contains(milestone.depth)) {
        reachedMilestones.add(milestone.depth);
        onMilestoneReached?.call(milestone);
      }
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

  /// Whether the robot is near the boss zone
  bool get isNearBoss => currentDepth >= GameConstants.bossDepth - 200;

  /// Whether the robot has reached a new depth record
  bool get isNewDepthRecord => currentDepth >= maxDepthReached - 1;

  /// Normalized depth (0.0 at surface, 1.0 at max depth)
  double get normalizedDepth =>
      (currentDepth / GameConstants.maxDepth).clamp(0.0, 1.0);

  /// Serialize
  Map<String, dynamic> toMap() {
    return {
      'maxDepth': maxDepthReached,
      'milestones': reachedMilestones.toList(),
    };
  }

  /// Load milestone data from a save map.
  void loadFromMap(Map<String, dynamic> map) {
    maxDepthReached = (map['maxDepth'] as num?)?.toDouble() ?? 0;
    final saved = map['milestones'];
    if (saved is List) {
      reachedMilestones.clear();
      for (final v in saved) {
        reachedMilestones.add((v as num).toDouble());
      }
    }
  }
}
