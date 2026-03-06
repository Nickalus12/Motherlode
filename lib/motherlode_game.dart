import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart'
    hide ParticleSystem, ParticleType;
import 'package:flutter/material.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/entities/pod/pod_controller.dart';
import 'package:motherlode/physics/debris_body.dart';
import 'package:motherlode/rendering/lighting_system.dart';
import 'package:motherlode/physics/sdf_collision.dart';
import 'package:motherlode/rendering/parallax_background.dart';
import 'package:motherlode/rendering/particle_system.dart';
import 'package:motherlode/rendering/shader_background.dart';
import 'package:motherlode/rendering/shader_terrain_renderer.dart';
import 'package:motherlode/rendering/terrain_renderer.dart';
import 'package:motherlode/systems/camera_system.dart';
import 'package:motherlode/systems/depth_system.dart';
import 'package:motherlode/systems/fuel_system.dart';
import 'package:motherlode/systems/hull_system.dart';
import 'package:motherlode/systems/creature_spawner.dart';
import 'package:motherlode/systems/earthquake_system.dart';
import 'package:motherlode/rendering/item_sprite_manager.dart';
import 'package:motherlode/systems/audio_manager.dart';
import 'package:motherlode/utils/debug_log.dart';
import 'package:motherlode/utils/perf_monitor.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/chunk_manager.dart';
import 'package:motherlode/world/genesis_pipeline.dart';
import 'package:motherlode/world/stratigraphy.dart';
import 'package:motherlode/world/world_generator.dart';
import 'package:motherlode/utils/constants.dart';

/// Root game class for Motherlode - extends Forge2DGame for physics
class MotherlodeGame extends Forge2DGame
    with HasKeyboardHandlerComponents, TapCallbacks, DragCallbacks {
  MotherlodeGame({
    this.onGameOver,
    this.onReady,
    this.worldSeed,
    this.genesisResult,
    this.stratigraphy,
    this.onGenesisProgress,
  }) : super(
          gravity: Vector2(0, GameConstants.gravity),
          zoom: GameConstants.pixelsPerMeter,
        );

  final VoidCallback? onGameOver;
  final VoidCallback? onReady;
  final int? worldSeed;

  /// Pre-generated world data from GenesisPipeline (null = use legacy WorldGenerator).
  final GenesisResult? genesisResult;

  /// Stratigraphy from GenesisPipeline for geological coloring.
  final Stratigraphy? stratigraphy;

  /// Progress callback for genesis pipeline (bridges to load screen stream).
  final GenesisProgressCallback? onGenesisProgress;

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
  late final DebrisManager debrisManager;
  late final PerfMonitor perfMonitor;
  TerrainRenderer? terrainRenderer;
  ParallaxBackground? parallaxBackground;
  late final ShaderTerrainRenderer shaderTerrainRenderer;
  late final ShaderBackground shaderBackground;
  late final SdfCollisionSystem sdfCollisionSystem;
  late final CreatureSpawner creatureSpawner;
  late final AudioManager audioManager;
  late final CameraSystem cameraSystem;

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

  // Collectibles
  int ancientScrollCount = 0;

  // Game state
  bool isAtSurface = true;
  bool isGameOver = false;
  bool usingCpuFallback = false;
  int _seed = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _seed = worldSeed ?? Random().nextInt(999999);

    // Initialize world generation (legacy fallback always available)
    worldGenerator = WorldGenerator(seed: _seed);
    chunkManager = ChunkManager(
      worldGenerator: worldGenerator,
      game: this,
    );

    // If GenesisPipeline produced pre-generated data, inject it
    if (genesisResult != null) {
      chunkManager.stratigraphy = stratigraphy;
      chunkManager.preloadChunkData(genesisResult!.chunks);
    }

    // Initialize systems
    depthSystem = DepthSystem();
    fuelSystem = FuelSystem(game: this);
    hullSystem = HullSystem(game: this);
    earthquakeSystem = EarthquakeSystem(game: this);
    lightingSystem = LightingSystem();
    particleSystem = ParticleSystem();
    debrisManager = DebrisManager();
    perfMonitor = PerfMonitor();
    shaderTerrainRenderer = ShaderTerrainRenderer();
    shaderBackground = ShaderBackground();
    sdfCollisionSystem = SdfCollisionSystem();
    creatureSpawner = CreatureSpawner(seed: worldSeed);
    audioManager = AudioManager();
    cameraSystem = CameraSystem();

    // Preload ore sprite sheets for terrain rendering
    final oreSpritePaths =
        OreRegistry.allOres.map((ore) => ore.spritePath).whereType<String>();
    await ItemSpriteManager.instance.preloadAll(oreSpritePaths);

    // Add shader renderers and await their loading so we can check compile status
    await world.add(shaderBackground);
    await world.add(chunkManager);
    await world.add(shaderTerrainRenderer);

    // Fall back to CPU renderers if shaders failed to compile
    DebugLog.info(
        'Game',
        'Background: ready=${shaderBackground.shaderReady} '
            'time=${shaderBackground.compilationTimeMs}ms '
            'error=${shaderBackground.shaderError ?? "none"}');
    DebugLog.info(
        'Game',
        'Terrain: ready=${shaderTerrainRenderer.shaderReady} '
            'time=${shaderTerrainRenderer.compilationTimeMs}ms '
            'error=${shaderTerrainRenderer.shaderError ?? "none"}');
    if (!shaderBackground.shaderReady) {
      DebugLog.warn(
          'Game', 'Background shader unavailable, using CPU fallback');
      parallaxBackground = ParallaxBackground();
      world.add(parallaxBackground!);
    }
    if (!shaderTerrainRenderer.shaderReady) {
      DebugLog.warn('Game', 'Terrain shader unavailable, using CPU fallback');
      terrainRenderer = TerrainRenderer();
      world.add(terrainRenderer!);
    }
    usingCpuFallback =
        !shaderBackground.shaderReady || !shaderTerrainRenderer.shaderReady;
    if (usingCpuFallback) {
      DebugLog.warn('Game', 'Running with CPU fallback rendering');
    } else {
      DebugLog.info(
          'Game', 'GPU shaders active for both background and terrain');
    }

    // Force-load terrain chunks around spawn and await their bodies.
    // If genesis data was preloaded, forceLoadAroundSpawn picks it up
    // from the cache instead of re-generating via WorldGenerator.
    await chunkManager.forceLoadAroundSpawn();

    // Determine safe spawn position above the surface
    final spawnY = _findSafeSpawnY();

    // Create player pod at safe position
    pod = Pod(game: this, spawnY: spawnY);
    podController = PodController(pod: pod);

    await world.add(pod);
    world.add(podController);
    world.add(depthSystem);
    world.add(fuelSystem);
    world.add(hullSystem);
    world.add(earthquakeSystem);
    world.add(particleSystem);
    world.add(debrisManager);
    world.add(sdfCollisionSystem);
    world.add(creatureSpawner);
    world.add(audioManager);

    // Add render overlays (camera-relative)
    camera.viewport.add(lightingSystem);
    camera.viewport.add(perfMonitor);

    // Wait for pod to be ready before camera follow
    try {
      await pod.loaded;
    } catch (_) {
      // Pod may still work with fallback rendering
    }
    // CameraSystem handles follow + look-ahead + dynamic zoom
    world.add(cameraSystem);

    // Notify that loading is complete
    onReady?.call();
  }

  /// Find a safe Y position to spawn the pod above the terrain surface.
  double _findSafeSpawnY() {
    // Landing pad is always flat at y=0, spawn well above it
    return -5.0;
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
    audioManager.playPurchase();
    return true;
  }

  /// Get the current depth in feet
  double get currentDepthFeet => depthSystem.currentDepth;

  /// Remove a terrain cell at world grid position
  void removeTerrainCell(int gridX, int gridY) {
    chunkManager.removeCell(gridX, gridY);
  }

  /// Mark a terrain cell as modified (SDF changed) without clearing it.
  /// Used by SDF drill carve where the cell's SDF is already updated.
  void removeTerrainCellSdf(int gridX, int gridY) {
    chunkManager.markCellDirty(gridX, gridY);
  }

  /// Get terrain cell type at world grid position
  int getCellType(int gridX, int gridY) {
    return chunkManager.getCellType(gridX, gridY);
  }

  // Touch input forwarding for mobile controls
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!pod.isMounted) return;
    podController.handleTouchDown(
      event.pointerId,
      event.canvasPosition,
    );
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (!pod.isMounted) return;
    podController.handleTouchMove(
      event.pointerId,
      event.canvasEndPosition,
    );
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!pod.isMounted) return;
    podController.handleTouchUp(event.pointerId);
  }
}
