import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart'
    hide ParticleSystem, ParticleType;
import 'package:flutter/material.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/entities/pod/pod_controller.dart';
import 'package:motherlode/physics/debris_body.dart';
import 'package:motherlode/rendering/depth_fog.dart';
import 'package:motherlode/rendering/lighting_system.dart';
import 'package:motherlode/rendering/particle_system.dart';
import 'package:motherlode/systems/depth_system.dart';
import 'package:motherlode/systems/fuel_system.dart';
import 'package:motherlode/systems/hull_system.dart';
import 'package:motherlode/systems/earthquake_system.dart';
import 'package:motherlode/utils/perf_monitor.dart';
import 'package:motherlode/world/chunk_manager.dart';
import 'package:motherlode/world/world_generator.dart';
import 'package:motherlode/utils/constants.dart';

/// Root game class for Motherlode - extends Forge2DGame for physics
class MotherlodeGame extends Forge2DGame
    with HasKeyboardHandlerComponents, TapCallbacks, DragCallbacks {
  MotherlodeGame({
    this.onGameOver,
    this.worldSeed,
  }) : super(
          gravity: Vector2(0, GameConstants.gravity),
          zoom: GameConstants.pixelsPerMeter,
        );

  final VoidCallback? onGameOver;
  final int? worldSeed;

  // Core systems
  late final WorldGenerator worldGenerator;
  late final ChunkManager chunkManager;
  late final Pod pod;
  late final PodController podController;
  late final DepthSystem depthSystem;
  late final FuelSystem fuelSystem;
  late final HullSystem hullSystem;
  late final EarthquakeSystem earthquakeSystem;
  late final LightingSystem lightingSystem;
  late final ParticleSystem particleSystem;
  late final DepthFog depthFog;
  late final DebrisManager debrisManager;
  late final PerfMonitor perfMonitor;

  // Player state
  double playerCash = GameConstants.startingCash;
  int drillLevel = 0;
  int hullLevel = 0;
  int engineLevel = 0;
  int fuelTankLevel = 0;
  int radiatorLevel = 0;
  int cargoLevel = 0;

  // Consumable inventory
  int dynamiteCount = 0;
  int plasticExplosiveCount = 0;
  int reserveFuelCount = 0;
  int nanobotCount = 0;
  int teleporterCount = 0;
  int transmitterCount = 0;

  // Game state
  bool isAtSurface = true;
  bool isGameOver = false;
  int _seed = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _seed = worldSeed ?? Random().nextInt(999999);

    // Initialize world generation
    worldGenerator = WorldGenerator(seed: _seed);
    chunkManager = ChunkManager(
      worldGenerator: worldGenerator,
      game: this,
    );

    // Initialize systems
    depthSystem = DepthSystem();
    fuelSystem = FuelSystem(game: this);
    hullSystem = HullSystem(game: this);
    earthquakeSystem = EarthquakeSystem(game: this);
    lightingSystem = LightingSystem();
    particleSystem = ParticleSystem();
    depthFog = DepthFog();
    debrisManager = DebrisManager();
    perfMonitor = PerfMonitor();

    // Create player pod
    pod = Pod(game: this);
    podController = PodController(pod: pod);

    // Add components to world
    world.add(chunkManager);
    await world.add(pod);
    world.add(podController);
    world.add(depthSystem);
    world.add(fuelSystem);
    world.add(hullSystem);
    world.add(earthquakeSystem);
    world.add(particleSystem);
    world.add(debrisManager);

    // Add render overlays (camera-relative)
    camera.viewport.add(lightingSystem);
    camera.viewport.add(depthFog);
    camera.viewport.add(perfMonitor);

    // Wait for pod body to be ready before camera follow
    await pod.loaded;
    camera.follow(pod);
  }

  @override
  void update(double dt) {
    if (isGameOver) return;
    super.update(dt);

    if (!pod.isMounted) return;

    // Update depth based on pod position
    depthSystem.updateDepth(pod.position.y);

    // Check if at surface
    isAtSurface = pod.position.y <= 0;
  }

  /// Called when the pod runs out of hull HP or fuel
  void triggerGameOver() {
    if (isGameOver) return;
    isGameOver = true;
    onGameOver?.call();
  }

  /// Add cash with floating text effect
  void addCash(double amount) {
    playerCash += amount;
  }

  /// Spend cash, returns false if insufficient
  bool spendCash(double amount) {
    if (playerCash < amount) return false;
    playerCash -= amount;
    return true;
  }

  /// Get the current depth in feet
  double get currentDepthFeet => depthSystem.currentDepth;

  /// Remove a terrain cell at world grid position
  void removeTerrainCell(int gridX, int gridY) {
    chunkManager.removeCell(gridX, gridY);
  }

  /// Get terrain cell type at world grid position
  int getCellType(int gridX, int gridY) {
    return chunkManager.getCellType(gridX, gridY);
  }
}
