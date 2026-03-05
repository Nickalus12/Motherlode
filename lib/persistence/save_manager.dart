import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:hellbore/hellbore_game.dart';
import 'package:hellbore/persistence/game_state.dart';

/// Manages saving and loading game state using Hive
class SaveManager {
  SaveManager._();

  static const String _boxName = 'hellbore_saves';
  static const String _currentSaveKey = 'current_save';
  static const String _autoSaveKey = 'auto_save';

  static Box? _box;

  /// Initialize the save system
  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Save current game state
  static Future<void> saveGame(HellboreGame game, {String? slotKey}) async {
    final box = _box ?? await Hive.openBox(_boxName);

    final state = _captureState(game);
    final json = jsonEncode(state.toMap());

    await box.put(slotKey ?? _currentSaveKey, json);
  }

  /// Auto-save (called periodically or on surface return)
  static Future<void> autoSave(HellboreGame game) async {
    await saveGame(game, slotKey: _autoSaveKey);
  }

  /// Load game state
  static Future<GameState?> loadGame({String? slotKey}) async {
    final box = _box ?? await Hive.openBox(_boxName);
    final json = box.get(slotKey ?? _currentSaveKey) as String?;

    if (json == null) return null;

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return GameState.fromMap(map);
    } catch (e) {
      return null;
    }
  }

  /// Apply loaded state to a game instance
  static void applyState(HellboreGame game, GameState state) {
    // Player stats
    game.playerCash = state.cash;
    game.drillLevel = state.drillLevel;
    game.hullLevel = state.hullLevel;
    game.engineLevel = state.engineLevel;
    game.fuelTankLevel = state.fuelTankLevel;
    game.radiatorLevel = state.radiatorLevel;
    game.cargoLevel = state.cargoLevel;

    // Consumables
    game.dynamiteCount = state.dynamiteCount;
    game.plasticExplosiveCount = state.plasticExplosiveCount;
    game.reserveFuelCount = state.reserveFuelCount;
    game.nanobotCount = state.nanobotCount;
    game.teleporterCount = state.teleporterCount;
    game.transmitterCount = state.transmitterCount;

    // Fuel and hull
    game.fuelSystem.currentFuel = state.fuel;
    game.fuelSystem.maxFuel = state.maxFuel;
    game.hullSystem.currentHull = state.hull;
    game.hullSystem.maxHull = state.maxHull;

    // Depth record
    game.depthSystem.maxDepthReached = state.maxDepthReached;
  }

  /// Capture current game state
  static GameState _captureState(HellboreGame game) {
    return GameState(
      worldSeed: game.worldSeed ?? 0,
      cash: game.playerCash,
      drillLevel: game.drillLevel,
      hullLevel: game.hullLevel,
      engineLevel: game.engineLevel,
      fuelTankLevel: game.fuelTankLevel,
      radiatorLevel: game.radiatorLevel,
      cargoLevel: game.cargoLevel,
      dynamiteCount: game.dynamiteCount,
      plasticExplosiveCount: game.plasticExplosiveCount,
      reserveFuelCount: game.reserveFuelCount,
      nanobotCount: game.nanobotCount,
      teleporterCount: game.teleporterCount,
      transmitterCount: game.transmitterCount,
      podX: game.pod.position.x,
      podY: game.pod.position.y,
      fuel: game.fuelSystem.currentFuel,
      maxFuel: game.fuelSystem.maxFuel,
      hull: game.hullSystem.currentHull,
      maxHull: game.hullSystem.maxHull,
      cargoInventory: Map.from(game.pod.cargoSystem.inventory),
      maxDepthReached: game.depthSystem.maxDepthReached,
    );
  }

  /// Check if a save exists
  static Future<bool> hasSave({String? slotKey}) async {
    final box = _box ?? await Hive.openBox(_boxName);
    return box.containsKey(slotKey ?? _currentSaveKey);
  }

  /// Delete a save
  static Future<void> deleteSave({String? slotKey}) async {
    final box = _box ?? await Hive.openBox(_boxName);
    await box.delete(slotKey ?? _currentSaveKey);
  }

  /// Delete all saves
  static Future<void> deleteAllSaves() async {
    final box = _box ?? await Hive.openBox(_boxName);
    await box.clear();
  }
}
