import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'package:hellbore/entities/pod/pod.dart';
import 'package:hellbore/entities/pod/pod_controller.dart';
import 'package:hellbore/physics/pod_body.dart';
import 'package:hellbore/rendering/depth_fog.dart';
import 'package:hellbore/rendering/lighting_system.dart';
import 'package:hellbore/rendering/particle_system.dart';
import 'package:hellbore/systems/depth_system.dart';
import 'package:hellbore/systems/fuel_system.dart';
import 'package:hellbore/systems/hull_system.dart';
import 'package:hellbore/systems/earthquake_system.dart';
import 'package:hellbore/world/chunk_manager.dart';
import 'package:hellbore/world/world_generator.dart';
import 'package:hellbore/utils/constants.dart';

/// Root game class for Hellbore - extends Forge2DGame for physics
class HellboreGame extends Forge2DGame
    with HasKeyboardHandlerComponents, TapCallbacks, DragCallbacks {
  HellboreGame({
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
    lightingSystem = LightingSystem(game: this);
    particleSystem = ParticleSystem();
    depthFog = DepthFog();

    // Create player pod
    pod = Pod(game: this);
    podController = PodController(pod: pod);

    // Add components to world
    world.add(chunkManager);
    world.add(pod);
    world.add(podController);
    world.add(depthSystem);
    world.add(fuelSystem);
    world.add(hullSystem);
    world.add(earthquakeSystem);
    world.add(particleSystem);

    // Add render overlays (camera-relative)
    camera.viewport.add(lightingSystem);
    camera.viewport.add(depthFog);

    // Center camera on pod
    camera.follow(pod);
  }

  @override
  void update(double dt) {
    if (isGameOver) return;
    super.update(dt);

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
