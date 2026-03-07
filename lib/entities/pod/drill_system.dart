import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Drilling logic using SDF sphere subtraction for smooth terrain removal.
///
/// Robot must be grounded to drill down. Drill direction is DOWN only
/// (faithful to original Motherload). When a cell is fully drilled,
/// an SDF sphere subtraction is applied to carve a smooth round hole.
///
/// Features:
/// - Material-specific haptic feedback patterns
/// - Progressive drill speed momentum (1.0x -> 1.3x over 3s of same material)
/// - Drill overshoot carry-over to next cell
/// - Multi-cell pre-warming for same-material veins
/// - Bedrock stall feedback with distinct haptic
class DrillSystem extends Component {
  final Pod pod;
  final MotherlodeGame game;

  double _currentCellProgress = 0;
  int? _targetGridX;
  int? _targetGridY;
  double _hapticTimer = 0;

  /// Momentum tracking for progressive drill speed.
  /// Builds from 1.0 to [_maxMomentum] over [_momentumBuildTime] seconds
  /// while drilling the same material type. Resets on material change.
  double _momentumMultiplier = 1.0;
  double _momentumTimer = 0;
  CellType? _lastDrilledMaterial;

  /// Set to true for one frame when an ore cell is collected.
  /// PodRenderer reads this to trigger the pickup animation.
  bool oreCollectedThisFrame = false;

  /// Base radius of the drill carve in grid units (level 0).
  static const double _baseRadius = 1.0;

  /// Additional radius per drill upgrade level.
  static const double _radiusPerLevel = 0.15;

  /// Smoothing factor for SDF subtraction (larger = rounder edges)
  static const double _drillSmoothing = 0.3;

  /// Maximum momentum multiplier for sustained drilling.
  static const double _maxMomentum = 1.3;

  /// Time in seconds to reach max momentum.
  static const double _momentumBuildTime = 3.0;

  /// Percentage of progress pre-warmed for next cell of same material.
  static const double _preWarmPercent = 10.0;

  /// Current drill radius, scaling with the game's drill upgrade level.
  double get _drillRadius => _baseRadius + game.drillLevel * _radiusPerLevel;

  DrillSystem({required this.pod, required this.game});

  /// Process one drill tick
  void drill(double dt) {
    oreCollectedThisFrame = false;
    if (!pod.podBody.isGrounded) return;

    // Find the cell directly below the robot
    final podX = pod.position.x;
    final podY = pod.position.y;

    // Convert robot position to grid coordinates
    final gridX = podX.round();
    final gridY = (podY + 1.2).round(); // Below the robot

    // Check if target cell exists and is drillable
    final cell = game.chunkManager.getTerrainCell(gridX, gridY);
    if (cell == null) return;

    // Bedrock stall feedback: distinct heavy haptic + no progress
    if (cell.type == CellType.bedrock) {
      _hapticTimer += dt;
      if (_hapticTimer >= 0.25) {
        _hapticTimer = 0;
        HapticFeedback.heavyImpact();
      }
      // Reset momentum when hitting bedrock
      _momentumMultiplier = 1.0;
      _momentumTimer = 0;
      return;
    }

    if (!cell.isDrillable) return;

    // Track target for progress — only reset when targeting a different cell
    if (_targetGridX != gridX || _targetGridY != gridY) {
      // If the new target is adjacent to the old one, carry over partial
      // progress scaled by hardness ratio. This prevents the "stutter" feel
      // when the robot drifts slightly while drilling through a vein.
      if (_targetGridX != null &&
          (gridX - _targetGridX!).abs() <= 1 &&
          (gridY - _targetGridY!).abs() <= 1 &&
          _currentCellProgress > 0) {
        // Carry 25% of progress to the new cell to smooth transitions
        _currentCellProgress *= 0.25;
      } else {
        _currentCellProgress = 0;
      }
      _targetGridX = gridX;
      _targetGridY = gridY;
    }

    // Progressive drill speed momentum
    _updateMomentum(cell.type, dt);

    // Calculate drill speed based on drill level, material hardness, and momentum
    final drillRate = (pod.drillSpeed / cell.hardness) * _momentumMultiplier;
    _currentCellProgress += drillRate * dt;

    // Check if cell is fully drilled
    if (_currentCellProgress >= 100.0) {
      // Capture overshoot for carry-over to next cell
      final overshoot = _currentCellProgress - 100.0;

      _removeCell(gridX, gridY, cell);

      // Carry overshoot progress to the next cell below
      _targetGridX = null;
      _targetGridY = null;
      _currentCellProgress =
          _computeCarryOver(gridX, gridY, cell.type, overshoot);
    }

    // Emit drill particles with terrain color
    game.audioManager.playDrill();
    game.particleSystem.emitDrillParticles(
      Vector2(podX, podY + 1.2),
      cell.baseColor,
      cell.type,
    );

    // Camera vibration scales with drill progress for satisfying feedback
    game.earthquakeSystem.setDrillVibrating(intensity: drillProgress);

    // Material-specific haptic feedback
    _applyMaterialHaptic(cell.type, dt);

    // Fuel consumption is handled by Pod._consumeFuel() when state == drilling.
    // Do NOT consume fuel here to avoid double consumption.
  }

  /// Update momentum multiplier based on material continuity.
  void _updateMomentum(CellType currentMaterial, double dt) {
    if (currentMaterial != _lastDrilledMaterial) {
      // Material changed — reset momentum
      _momentumMultiplier = 1.0;
      _momentumTimer = 0;
      _lastDrilledMaterial = currentMaterial;
    } else {
      // Same material — build momentum toward max
      _momentumTimer += dt;
      final t = (_momentumTimer / _momentumBuildTime).clamp(0.0, 1.0);
      _momentumMultiplier = 1.0 + (_maxMomentum - 1.0) * t;
    }
  }

  /// Compute carry-over progress for the next cell after drilling through.
  /// Includes overshoot from the current cell + pre-warming if same material.
  double _computeCarryOver(
      int gridX, int gridY, CellType currentType, double overshoot) {
    // Check the cell below the one we just drilled
    final nextCell = game.chunkManager.getTerrainCell(gridX, gridY + 1);
    if (nextCell == null || !nextCell.isDrillable) return 0;

    double carry = 0;

    // Overshoot carry-over: scale by hardness ratio between old and new cell
    if (overshoot > 0) {
      final hardnessRatio =
          nextCell.hardness > 0 ? 1.0 / nextCell.hardness : 1.0;
      carry += overshoot * hardnessRatio * 0.5; // 50% efficiency on overshoot
    }

    // Pre-warming: if next cell is same material, add bonus
    if (nextCell.type == currentType) {
      carry += _preWarmPercent;
    }

    return carry.clamp(0.0, 90.0); // Never fully pre-drill a cell
  }

  /// Apply haptic feedback appropriate to the material being drilled.
  void _applyMaterialHaptic(CellType type, double dt) {
    _hapticTimer += dt;

    double interval;
    switch (type) {
      case CellType.sand:
        interval = 0.20;
      case CellType.dirt:
        interval = 0.15;
      case CellType.rock:
        interval = 0.12;
      case CellType.obsidian:
        interval = 0.10;
      case CellType.ore:
        interval = 0.08;
      default:
        interval = 0.15;
    }

    if (_hapticTimer >= interval) {
      _hapticTimer = 0;

      switch (type) {
        case CellType.sand:
        case CellType.dirt:
          HapticFeedback.lightImpact();
        case CellType.rock:
          HapticFeedback.mediumImpact();
        case CellType.obsidian:
          HapticFeedback.heavyImpact();
        case CellType.ore:
          HapticFeedback.selectionClick();
        default:
          HapticFeedback.lightImpact();
      }
    }
  }

  /// Remove a drilled cell using SDF sphere subtraction and collect any ore.
  ///
  /// Delegates terrain carving to [ChunkManager.drillAtWorld] which handles
  /// cross-chunk SDF subtraction and dirty marking. Ore collection is
  /// checked on the target cell before carving, and on any newly-exposed
  /// ore cells after carving.
  void _removeCell(int gridX, int gridY, TerrainCell cell) {
    // Try to collect ore before carving; if cargo is full, ore is destroyed
    // but terrain is still carved so the player isn't stuck.
    if (cell.type == CellType.ore && cell.oreType != null) {
      _collectOre(gridX, gridY, cell);
    }

    // Carve smooth round hole via centralized SDF drill on ChunkManager
    final modified = game.chunkManager.drillAtWorld(
      gridX.toDouble(),
      gridY.toDouble(),
      _drillRadius,
      smoothK: _drillSmoothing,
    );

    // Collect ore from any cells that were newly cleared by the carve
    for (final (gx, gy, modifiedCell) in modified) {
      if (gx == gridX && gy == gridY) continue; // Already collected above
      if (modifiedCell.type == CellType.empty && modifiedCell.oreType != null) {
        // Cell was ore but got carved to empty — ore is lost (destroyed)
        modifiedCell.oreType = null;
      }
    }

    // Trigger collapse check in surrounding area
    game.earthquakeSystem.checkCollapse(gridX, gridY);
  }

  /// Try to collect ore from a cell. Returns false if cargo is full.
  bool _collectOre(int gridX, int gridY, TerrainCell cell) {
    final ore = cell.oreType!;

    if (ore.isSpecialCollectible) {
      // Ancient Scroll: increment count and show special effects
      if (ore == OreRegistry.ancientScroll) {
        game.ancientScrollCount++;
        final pos = Vector2(gridX.toDouble(), gridY.toDouble());
        // Extra celebration: multiple sparkle bursts
        game.particleSystem.emitOreSparkle(pos, ore.color);
        game.particleSystem.emitOreSparkle(pos, const Color(0xFFFFD700));
        game.particleSystem.emitOrePickup(pos, ore.color, ore.spritePath);
        game.audioManager.playOrePickup();
        game.earthquakeSystem.startShake(0.4, 0.5);
        oreCollectedThisFrame = true;
        return true;
      }
      game.addCash(ore.value.toDouble());
      final pos = Vector2(gridX.toDouble(), gridY.toDouble());
      game.particleSystem.emitOreSparkle(pos, ore.color);
      game.particleSystem.emitOrePickup(pos, ore.color, ore.spritePath);
      game.audioManager.playOrePickup();
      oreCollectedThisFrame = true;
      return true;
    }

    if (pod.cargoSystem.canAdd(ore.weight.toDouble())) {
      pod.cargoSystem.addOre(ore);
      final pos = Vector2(gridX.toDouble(), gridY.toDouble());
      game.particleSystem.emitOreSparkle(pos, ore.color);
      game.particleSystem.emitOrePickup(pos, ore.color, ore.spritePath);
      game.audioManager.playOrePickup();
      pod.updateMass();
      oreCollectedThisFrame = true;
      return true;
    }

    return false; // Cargo full
  }

  /// Get drill progress as 0.0 to 1.0
  double get drillProgress => _currentCellProgress / 100.0;

  /// Whether actively drilling a cell
  bool get isDrilling => _targetGridX != null;

  /// Current momentum multiplier (1.0 to 1.3).
  /// Exposed for HUD or visual feedback systems.
  double get momentum => _momentumMultiplier;
}
