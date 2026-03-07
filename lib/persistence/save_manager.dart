import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/persistence/game_state.dart';
import 'package:motherlode/utils/debug_log.dart';

/// Manages saving and loading game state using Hive.
///
/// Features:
/// - Backup-before-overwrite: current save is copied to backup key before
///   writing new data. If the write or integrity check fails, the backup is
///   restored automatically.
/// - Write-back integrity check: after saving, the data is read back and
///   parsed to verify the JSON round-trips correctly.
/// - Full try/catch around every Hive operation so corrupted data never
///   crashes the app.
class SaveManager {
  SaveManager._();

  static const String _boxName = 'motherlode_saves';
  static const String _currentSaveKey = 'current_save';
  static const String _autoSaveKey = 'auto_save';
  static const String _backupSuffix = '_backup';

  static Box? _box;

  /// Initialize the save system. Safe to call multiple times.
  static Future<void> init() async {
    try {
      _box ??= await Hive.openBox(_boxName);
    } catch (e) {
      DebugLog.error('SaveManager', 'Failed to open Hive box: $e');
      // Try to recover by deleting the corrupted box
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox(_boxName);
        DebugLog.warn('SaveManager', 'Recovered by recreating Hive box');
      } catch (e2) {
        DebugLog.error('SaveManager', 'Recovery failed: $e2');
      }
    }
  }

  static Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    await init();
    return _box ?? await Hive.openBox(_boxName);
  }

  /// Save current game state with backup and integrity check.
  static Future<bool> saveGame(MotherlodeGame game, {String? slotKey}) async {
    final key = slotKey ?? _currentSaveKey;
    final backupKey = '$key$_backupSuffix';

    try {
      final box = await _getBox();
      final state = _captureState(game);
      final json = jsonEncode(state.toMap());

      // Step 1: Backup current save before overwriting
      final existing = box.get(key) as String?;
      if (existing != null) {
        await box.put(backupKey, existing);
      }

      // Step 2: Write new save
      await box.put(key, json);

      // Step 3: Integrity check — read back and verify it parses
      final readBack = box.get(key) as String?;
      if (readBack == null) {
        throw StateError('Save written but read-back returned null');
      }
      final parsed = jsonDecode(readBack) as Map<String, dynamic>;
      if (parsed['version'] == null || parsed['worldSeed'] == null) {
        throw StateError(
            'Save integrity check failed: missing required fields');
      }

      DebugLog.info('SaveManager', 'Game saved successfully (key=$key)');
      return true;
    } catch (e) {
      DebugLog.error('SaveManager', 'Save failed: $e');

      // Attempt to restore backup
      try {
        final box = await _getBox();
        final backup = box.get('$key$_backupSuffix') as String?;
        if (backup != null) {
          await box.put(key, backup);
          DebugLog.warn(
              'SaveManager', 'Restored from backup after save failure');
        }
      } catch (restoreError) {
        DebugLog.error(
            'SaveManager', 'Backup restore also failed: $restoreError');
      }
      return false;
    }
  }

  /// Auto-save (called periodically or on surface return).
  static Future<bool> autoSave(MotherlodeGame game) async {
    return saveGame(game, slotKey: _autoSaveKey);
  }

  /// Load game state. Tries the primary save first, then falls back to
  /// the backup if the primary is corrupt.
  static Future<GameState?> loadGame({String? slotKey}) async {
    final key = slotKey ?? _currentSaveKey;

    // Try primary save
    final state = await _tryLoadFromKey(key);
    if (state != null) return state;

    // Primary corrupt or missing — try backup
    DebugLog.warn('SaveManager', 'Primary save failed, trying backup for $key');
    final backup = await _tryLoadFromKey('$key$_backupSuffix');
    if (backup != null) {
      DebugLog.info('SaveManager', 'Loaded from backup successfully');
      return backup;
    }

    // If loading a specific slot failed, try auto-save as last resort
    if (key == _currentSaveKey) {
      DebugLog.warn('SaveManager', 'Trying auto-save as fallback');
      return _tryLoadFromKey(_autoSaveKey);
    }

    return null;
  }

  /// Attempt to load and parse a save from a specific Hive key.
  static Future<GameState?> _tryLoadFromKey(String key) async {
    try {
      final box = await _getBox();
      final json = box.get(key) as String?;
      if (json == null) return null;

      final map = jsonDecode(json) as Map<String, dynamic>;
      return GameState.fromMap(map);
    } catch (e) {
      DebugLog.error('SaveManager', 'Failed to load key=$key: $e');
      return null;
    }
  }

  /// Apply loaded state to a game instance.
  ///
  /// Must be called before [ChunkManager.forceLoadAroundSpawn] so that
  /// modified chunk data is injected into the chunk cache first.
  static void applyState(MotherlodeGame game, GameState state) {
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
    game.supportBeamCount = state.supportBeamCount;
    game.flareCount = state.flareCount;

    // Fuel and hull
    game.fuelSystem.currentFuel = state.fuel;
    game.fuelSystem.maxFuel = state.maxFuel;
    game.hullSystem.currentHull = state.hull;
    game.hullSystem.maxHull = state.maxHull;

    // Depth record and milestones
    game.depthSystem.maxDepthReached = state.maxDepthReached;
    game.depthSystem.reachedMilestones
      ..clear()
      ..addAll(state.reachedMilestones.map((v) => v.toDouble()));

    // Market system
    if (state.marketState.isNotEmpty) {
      game.marketSystem.loadFromMap(state.marketState);
    }

    // Deployable system (beams, etc.)
    if (state.deployableState.isNotEmpty) {
      game.deployableSystem.loadFromMap(state.deployableState);
    }

    // Collectibles
    game.ancientScrollCount = state.ancientScrollCount;

    // Inject modified chunk data into ChunkManager cache
    if (state.modifiedChunks.isNotEmpty) {
      game.chunkManager.importModifiedChunks(state.modifiedChunks);
    }
  }

  /// Capture current game state.
  static GameState _captureState(MotherlodeGame game) {
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
      supportBeamCount: game.supportBeamCount,
      flareCount: game.flareCount,
      podX: game.pod.position.x,
      podY: game.pod.position.y,
      fuel: game.fuelSystem.currentFuel,
      maxFuel: game.fuelSystem.maxFuel,
      hull: game.hullSystem.currentHull,
      maxHull: game.hullSystem.maxHull,
      cargoInventory: Map.from(game.pod.cargoSystem.inventory),
      modifiedChunks: game.chunkManager.exportModifiedChunks(),
      maxDepthReached: game.depthSystem.maxDepthReached,
      ancientScrollCount: game.ancientScrollCount,
      reachedMilestones: game.depthSystem.reachedMilestones.toList(),
      marketState: game.marketSystem.toMap(),
      deployableState: game.deployableSystem.toMap(),
    );
  }

  /// Check if a save exists (for main menu continue button).
  static Future<bool> hasSave({String? slotKey}) async {
    try {
      final box = await _getBox();
      final key = slotKey ?? _currentSaveKey;
      // Also consider auto-save as a valid save
      return box.containsKey(key) || box.containsKey(_autoSaveKey);
    } catch (e) {
      DebugLog.error('SaveManager', 'hasSave check failed: $e');
      return false;
    }
  }

  /// Get the timestamp of the most recent save (for "last played" display).
  static Future<DateTime?> lastSavedAt({String? slotKey}) async {
    try {
      final state = await _tryLoadFromKey(slotKey ?? _currentSaveKey);
      return state?.savedAt;
    } catch (e) {
      return null;
    }
  }

  /// Delete a save and its backup.
  static Future<void> deleteSave({String? slotKey}) async {
    try {
      final box = await _getBox();
      final key = slotKey ?? _currentSaveKey;
      await box.delete(key);
      await box.delete('$key$_backupSuffix');
    } catch (e) {
      DebugLog.error('SaveManager', 'Delete failed: $e');
    }
  }

  /// Delete all saves.
  static Future<void> deleteAllSaves() async {
    try {
      final box = await _getBox();
      await box.clear();
    } catch (e) {
      DebugLog.error('SaveManager', 'Delete all failed: $e');
    }
  }
}
