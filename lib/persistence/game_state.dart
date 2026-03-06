import 'package:motherlode/world/terrain_cell.dart';

/// Save format version. Bump when the serialization layout changes.
const int saveFormatVersion = 1;

/// Full serializable game state model
///
/// Captures all state needed to save and restore a game session:
/// - Player stats (cash, upgrade levels, consumable counts)
/// - Pod state (position, fuel, hull, cargo)
/// - World seed (for regeneration)
/// - Modified chunk terrain data
/// - Depth records
class GameState {
  // Save format
  int version;

  // World
  int worldSeed;

  // Player stats
  double cash;
  int drillLevel;
  int hullLevel;
  int engineLevel;
  int fuelTankLevel;
  int radiatorLevel;
  int cargoLevel;

  // Consumables
  int dynamiteCount;
  int plasticExplosiveCount;
  int reserveFuelCount;
  int nanobotCount;
  int teleporterCount;
  int transmitterCount;

  // Pod state
  double podX;
  double podY;
  double fuel;
  double maxFuel;
  double hull;
  double maxHull;
  Map<String, int> cargoInventory;

  // Progress
  double maxDepthReached;
  double totalOreValue;
  int totalCellsDrilled;
  int ancientScrollCount;
  List<double> reachedMilestones;

  // NG+ tracking
  int ngPlusLevel;

  // Modified terrain chunks (key = "chunkX,chunkY")
  Map<String, List<List<TerrainCell>>> modifiedChunks;

  // Timestamps
  DateTime savedAt;
  Duration playTime;

  GameState({
    this.version = saveFormatVersion,
    this.worldSeed = 0,
    this.cash = 0,
    this.drillLevel = 0,
    this.hullLevel = 0,
    this.engineLevel = 0,
    this.fuelTankLevel = 0,
    this.radiatorLevel = 0,
    this.cargoLevel = 0,
    this.dynamiteCount = 0,
    this.plasticExplosiveCount = 0,
    this.reserveFuelCount = 0,
    this.nanobotCount = 0,
    this.teleporterCount = 0,
    this.transmitterCount = 0,
    this.podX = 0,
    this.podY = -2,
    this.fuel = 10,
    this.maxFuel = 10,
    this.hull = 10,
    this.maxHull = 10,
    Map<String, int>? cargoInventory,
    Map<String, List<List<TerrainCell>>>? modifiedChunks,
    this.maxDepthReached = 0,
    this.totalOreValue = 0,
    this.totalCellsDrilled = 0,
    this.ancientScrollCount = 0,
    List<double>? reachedMilestones,
    this.ngPlusLevel = 0,
    DateTime? savedAt,
    this.playTime = Duration.zero,
  })  : cargoInventory = cargoInventory ?? {},
        modifiedChunks = modifiedChunks ?? {},
        reachedMilestones = reachedMilestones ?? [],
        savedAt = savedAt ?? DateTime.now();

  /// Serialize to JSON-compatible map
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'worldSeed': worldSeed,
      'cash': cash,
      'drillLevel': drillLevel,
      'hullLevel': hullLevel,
      'engineLevel': engineLevel,
      'fuelTankLevel': fuelTankLevel,
      'radiatorLevel': radiatorLevel,
      'cargoLevel': cargoLevel,
      'dynamiteCount': dynamiteCount,
      'plasticExplosiveCount': plasticExplosiveCount,
      'reserveFuelCount': reserveFuelCount,
      'nanobotCount': nanobotCount,
      'teleporterCount': teleporterCount,
      'transmitterCount': transmitterCount,
      'podX': podX,
      'podY': podY,
      'fuel': fuel,
      'maxFuel': maxFuel,
      'hull': hull,
      'maxHull': maxHull,
      'cargoInventory': cargoInventory,
      'maxDepthReached': maxDepthReached,
      'totalOreValue': totalOreValue,
      'totalCellsDrilled': totalCellsDrilled,
      'ancientScrollCount': ancientScrollCount,
      'reachedMilestones': reachedMilestones,
      'ngPlusLevel': ngPlusLevel,
      'savedAt': savedAt.toIso8601String(),
      'playTimeMs': playTime.inMilliseconds,
      'modifiedChunks': _serializeChunks(modifiedChunks),
    };
  }

  /// Serialize modified chunks: key -> list of rows of cell maps.
  static Map<String, dynamic> _serializeChunks(
    Map<String, List<List<TerrainCell>>> chunks,
  ) {
    final result = <String, dynamic>{};
    for (final entry in chunks.entries) {
      result[entry.key] = [
        for (final row in entry.value) [for (final cell in row) cell.toMap()],
      ];
    }
    return result;
  }

  /// Deserialize chunk data from saved map.
  static Map<String, List<List<TerrainCell>>> _deserializeChunks(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return {};
    final result = <String, List<List<TerrainCell>>>{};
    for (final entry in data.entries) {
      final rows = entry.value as List<dynamic>;
      result[entry.key] = [
        for (final row in rows)
          [
            for (final cellMap in (row as List<dynamic>))
              TerrainCell.fromMap(cellMap as Map<String, dynamic>),
          ],
      ];
    }
    return result;
  }

  /// Restore from serialized map
  factory GameState.fromMap(Map<String, dynamic> map) {
    return GameState(
      version: map['version'] as int? ?? 0,
      worldSeed: map['worldSeed'] as int? ?? 0,
      cash: (map['cash'] as num?)?.toDouble() ?? 0,
      drillLevel: map['drillLevel'] as int? ?? 0,
      hullLevel: map['hullLevel'] as int? ?? 0,
      engineLevel: map['engineLevel'] as int? ?? 0,
      fuelTankLevel: map['fuelTankLevel'] as int? ?? 0,
      radiatorLevel: map['radiatorLevel'] as int? ?? 0,
      cargoLevel: map['cargoLevel'] as int? ?? 0,
      dynamiteCount: map['dynamiteCount'] as int? ?? 0,
      plasticExplosiveCount: map['plasticExplosiveCount'] as int? ?? 0,
      reserveFuelCount: map['reserveFuelCount'] as int? ?? 0,
      nanobotCount: map['nanobotCount'] as int? ?? 0,
      teleporterCount: map['teleporterCount'] as int? ?? 0,
      transmitterCount: map['transmitterCount'] as int? ?? 0,
      podX: (map['podX'] as num?)?.toDouble() ?? 0,
      podY: (map['podY'] as num?)?.toDouble() ?? -2,
      fuel: (map['fuel'] as num?)?.toDouble() ?? 10,
      maxFuel: (map['maxFuel'] as num?)?.toDouble() ?? 10,
      hull: (map['hull'] as num?)?.toDouble() ?? 10,
      maxHull: (map['maxHull'] as num?)?.toDouble() ?? 10,
      cargoInventory: (map['cargoInventory'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      modifiedChunks: _deserializeChunks(
        map['modifiedChunks'] as Map<String, dynamic>?,
      ),
      maxDepthReached: (map['maxDepthReached'] as num?)?.toDouble() ?? 0,
      totalOreValue: (map['totalOreValue'] as num?)?.toDouble() ?? 0,
      totalCellsDrilled: map['totalCellsDrilled'] as int? ?? 0,
      ancientScrollCount: map['ancientScrollCount'] as int? ??
          (map['hasAncientScroll'] == true ? 1 : 0),
      reachedMilestones: (map['reachedMilestones'] as List<dynamic>?)
              ?.map((v) => (v as num).toDouble())
              .toList() ??
          [],
      ngPlusLevel: map['ngPlusLevel'] as int? ?? 0,
      savedAt: map['savedAt'] != null
          ? DateTime.parse(map['savedAt'] as String)
          : DateTime.now(),
      playTime: Duration(
        milliseconds: map['playTimeMs'] as int? ?? 0,
      ),
    );
  }

  /// Create a copy
  GameState copyWith({
    int? worldSeed,
    double? cash,
  }) {
    return GameState(
      version: version,
      worldSeed: worldSeed ?? this.worldSeed,
      cash: cash ?? this.cash,
      drillLevel: drillLevel,
      hullLevel: hullLevel,
      engineLevel: engineLevel,
      fuelTankLevel: fuelTankLevel,
      radiatorLevel: radiatorLevel,
      cargoLevel: cargoLevel,
      dynamiteCount: dynamiteCount,
      plasticExplosiveCount: plasticExplosiveCount,
      reserveFuelCount: reserveFuelCount,
      nanobotCount: nanobotCount,
      teleporterCount: teleporterCount,
      transmitterCount: transmitterCount,
      podX: podX,
      podY: podY,
      fuel: fuel,
      maxFuel: maxFuel,
      hull: hull,
      maxHull: maxHull,
      cargoInventory: Map.from(cargoInventory),
      modifiedChunks: Map.from(modifiedChunks),
      maxDepthReached: maxDepthReached,
      totalOreValue: totalOreValue,
      totalCellsDrilled: totalCellsDrilled,
      ancientScrollCount: ancientScrollCount,
      reachedMilestones: List.from(reachedMilestones),
      ngPlusLevel: ngPlusLevel,
      savedAt: savedAt,
      playTime: playTime,
    );
  }
}
