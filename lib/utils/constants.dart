import 'dart:ui';

/// Core game constants for Motherlode
class GameConstants {
  GameConstants._();

  // World dimensions
  static const double tileSize = 64.0;
  static const int chunkSize = 32;
  static const double chunkPixelSize = tileSize * chunkSize;

  // Physics (Forge2D uses meters, 1 meter = tileSize pixels)
  static const double pixelsPerMeter = 24.0;
  static const double gravity = 9.8;
  static const double podBaseMass = 500.0;
  static const double podLinearDamping = 0.4;
  static const double podAngularDamping = 5.0;

  // Depth system (in feet)
  static const double maxDepth = 7500.0;
  static const double surfaceDepth = 0.0;
  static const double sandLayerEnd = 200.0;
  static const double topsoilEnd = 1000.0;
  static const double rockEnd = 3000.0;
  static const double volcanicEnd = 5000.0;
  static const double hellStart = 5000.0;
  static const double bossDepth = 7187.0;
  static const double feetPerTile = 15.0;

  // Chunk loading
  static const int chunkLoadRadius = 3;
  static const int chunkUnloadRadius = 5;

  // Rendering
  static const double podLightBaseRadius = 400.0;
  static const double podLightPerLevel = 10.0;
  static const double maxDarknessOpacity = 0.92;
  static const double terrainStrokeWidth = 2.0;

  // Drilling
  static const double baseDrillSpeed = 50.0; // ft/s
  static const double drillParticleCount = 10.0;

  // Fuel
  static const double baseFuelCapacity = 10.0; // liters
  static const double fuelCostPerLiter = 10.0;
  static const double fuelConsumptionIdle = 0.003; // Near-zero when grounded
  static const double fuelConsumptionThrust = 0.20; // ~50s flight on a 10L tank
  static const double fuelConsumptionDrill = 0.08; // Cheaper than flying
  static const double lowFuelThreshold = 0.15;
  static const double reducedThrustThreshold = 0.20;

  // Hull
  static const double baseHullHP = 50.0;
  static const double lowHullThreshold = 0.20;
  static const double lavaDamagePerSecond = 12.0; // ~4s to kill at base hull
  static const double gasDamagePerSecond = 5.0; // ~10s at base hull

  // Cargo
  static const double baseCargoCapacity = 50.0; // kg

  // Explosions
  static const int dynamiteRadius = 3;
  static const int plasticExplosiveRadius = 5;
  static const double dynamiteForce = 5000.0;
  static const double plasticExplosiveForce = 10000.0;
  static const double dynamiteCameraTrauma = 0.8;
  static const double plasticCameraTrauma = 1.0;

  // Collapse
  static const int collapseCheckRadius = 5;
  static const int collapseMinSupportNeighbors = 3;
  static const double debrisSettleTime = 3.0;
  static const double debrisDamageMultiplier = 0.1;

  // Creatures
  static const double creatureChaseRange = 200.0;
  static const double gasSporeChainRadius = 3.0;

  // Biome colors — Terraria/Motherload inspired palette
  // Surface: lush green grass
  static const Color grassColor = Color(0xFF4CAF50); // Vivid grass green
  static const Color grassDarkColor = Color(0xFF2E7D32); // Darker grass shade
  static const Color grassAccentColor =
      Color(0xFF66BB6A); // Light grass highlight

  // Topsoil: warm brown earth (0-200ft)
  static const Color surfaceTerrainColor =
      Color(0xFF8B6B3D); // Rich brown earth
  static const Color surfaceAccentColor = Color(0xFFA0845A); // Light brown
  // Shallow/Topsoil (200-1000ft): darker brown, clay tones
  static const Color shallowTerrainColor =
      Color(0xFF6B4E2A); // Dark earth brown
  static const Color shallowAccentColor = Color(0xFF5A3D1F); // Deep clay
  // Rock layer (1000-3000ft): gray stone tones
  static const Color deepTerrainColor = Color(0xFF696969); // Medium gray stone
  static const Color deepAccentColor = Color(0xFF505050); // Darker gray
  // Volcanic (3000-5000ft): dark red/orange volcanic rock
  static const Color volcanicTerrainColor =
      Color(0xFF5C2020); // Dark volcanic red
  static const Color volcanicAccentColor =
      Color(0xFFCC4400); // Glowing orange accent
  // Hell (5000ft+): near-black with red undertone
  static const Color hellTerrainColor =
      Color(0xFF2A0A0A); // Near-black hell rock
  static const Color hellAccentColor = Color(0xFFCC0000); // Deep red accent

  // Grass rendering
  static const double grassDepthThreshold =
      30.0; // feet — grass only on surface
  static const double grassThickness = 0.3; // tile fraction for grass cap

  // Ambient light levels by depth
  static const double surfaceAmbientLight = 1.0;
  static const double shallowAmbientLight = 0.8;
  static const double deepAmbientLight = 0.5;
  static const double volcanicAmbientLight = 0.25;
  static const double hellAmbientLight = 0.1;

  // Particle system
  static const int drillParticlesMin = 4;
  static const int drillParticlesMax = 6;
  static const int oreSparkleParticles = 8;
  static const int explosionParticlesMin = 20;
  static const int explosionParticlesMax = 40;
  static const int lavaSplashParticles = 10;
  static const int caveDustParticlesMin = 15;
  static const int caveDustParticlesMax = 25;

  // Forge2D collision filter categories (bitmask)
  // Pod excludes terrain so SdfCollisionSystem is the sole terrain handler.
  // Debris collides with both terrain and pod normally.
  static const int collisionCategoryPod = 0x0001;
  static const int collisionCategoryTerrain = 0x0002;
  static const int collisionCategoryDebris = 0x0004;
  static const int collisionMaskPod = 0xFFFF; // everything including terrain
  static const int collisionMaskTerrain = 0xFFFF; // everything
  static const int collisionMaskDebris = 0xFFFF; // everything

  // Physics limits
  static const double podMaxSpeed = 14.0; // m/s — soft-capped via drag force in Pod.update()

  // Economy
  static const double startingCash = 0.0;
  static const double reserveFuelAmount = 25.0;
  static const double nanobotHealAmount = 150.0; // Scaled with 50 base HP
}
